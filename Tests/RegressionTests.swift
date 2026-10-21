//
//  RegressionTests.swift
//  MihomoMonitor
//
//  [架构层级] Tests / 临时数据回归
//  [核心职责] 用真实生产类型验证跨日、幂等、事务、筛选、可见性和重连；不启动应用。
//  [关键类型] RegressionTests, FakeClock, StubProtocol, QueryGate, SnapshotFeed
//  [依赖关系] Foundation、SQLite3、项目 Services / Persistence / Feature
//  [并发安全] 测试编排位于 MainActor；传输替身和时钟使用锁，快照源使用 actor。
//

import Foundation
import SQLite3

/// 可控时间避免端点退避测试真实等待，并让速率测试有确定分母。
nonisolated final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: Double) { lock.lock(); value.addTimeInterval(seconds); lock.unlock() }
}

/// URLProtocol 拦截所有测试 HTTP 请求，不连接真实代理，也不监听网络端口。
nonisolated final class StubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var availablePort: Int?
    nonisolated(unsafe) private static var requestedPorts: [Int] = []
    static func configure(port: Int?) {
        lock.lock(); availablePort = port; requestedPorts = []; lock.unlock()
    }
    static func requests() -> [Int] { lock.lock(); defer { lock.unlock() }; return requestedPorts }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let port = request.url!.port!
        Self.requestedPorts.append(port)
        let available = Self.availablePort == port
        Self.lock.unlock()
        guard available else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"uploadTotal":0,"downloadTotal":0,"connections":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// 使用 continuation 精确控制查询完成顺序，防止依赖机器速度的竞态测试。
@MainActor
final class QueryGate {
    var requests: [(Date, String)] = []
    private var continuations: [CheckedContinuation<DashboardStats, Never>] = []
    func load(_ start: Date, _ search: String) async -> DashboardStats {
        requests.append((start, search))
        return await withCheckedContinuation { continuations.append($0) }
    }
    func finish(_ stats: DashboardStats) { continuations.removeFirst().resume(returning: stats) }
}

/// 模拟成功快照、失败、连接关闭，全部来自内存。
actor SnapshotFeed {
    private var values: [MihomoConnectionsSnapshot?]
    init(_ values: [MihomoConnectionsSnapshot?]) { self.values = values }
    func next() throws -> MihomoConnectionsSnapshot {
        guard let value = values.removeFirst() else { throw URLError(.cannotConnectToHost) }
        return value
    }
}

@main
@MainActor
enum RegressionTests {
    struct Failure: Error { let message: String }
    private static var assertions = 0

    /// 每个测试独立的 SQLite 文件，测试结束删除整个临时目录。
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mihomo-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await crossDay(directory.appendingPathComponent("days.db"))
        try await restartDedup(directory.appendingPathComponent("restart.db"))
        try await rollback(directory.appendingPathComponent("rollback.db"))
        try await search51(directory.appendingPathComponent("search.db"))
        try await latestFilters()
        try await endpointReconnect()
        try await trackerShutdown(directory.appendingPathComponent("tracker.db"))
        print("PASS: 7 regression groups, \(assertions) assertions; temporary databases only")
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        assertions += 1
        guard condition else { throw Failure(message: message) }
    }

    /// 有限等待只用于让 MainActor 任务开始执行，查询顺序由 QueryGate 明确控制。
    private static func eventually(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw Failure(message: "Timed out waiting for controlled async event")
    }

    private static func date(_ raw: String) -> Date { ISO8601DateFormatter().date(from: raw)! }

    private static func sample(id: String = "conn", token: String = "2026-10-20T23:59:58Z",
                               host: String = "test.example", up: Int64, down: Int64 = 0,
                               at: Date, closed: Bool = false) -> TrafficCheckpoint {
        TrafficCheckpoint(connectionID: id, startToken: token, appName: "TestApp", host: host,
            destinationIP: "192.0.2.1", proxyNode: "TestProxy", upload: up, download: down,
            startedAt: date(token), observedAt: at, isClosed: closed)
    }

    /// 仅针对调用方提供的临时 URL 执行 SQL，用于故障注入和独立验证数据库状态。
    private static func sql(_ url: URL, _ text: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw Failure(message: "test sqlite open") }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else {
            throw Failure(message: "test SQL: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private static func scalar(_ url: URL, _ text: String) throws -> Int64 {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw Failure(message: "test sqlite open") }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, text, -1, &stmt, nil) == SQLITE_OK else { throw Failure(message: "test prepare") }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw Failure(message: "test row") }
        return sqlite3_column_int64(stmt, 0)
    }

    private static func crossDay(_ url: URL) async throws {
        let db = DatabaseManager(databaseURL: url)
        let t = date("2026-10-20T23:59:58Z")
        _ = try await db.recordCheckpoints([
            sample(up: 100, down: 200, at: t),
            sample(up: 140, down: 280, at: t.addingTimeInterval(4)),
            sample(up: 180, down: 360, at: t.addingTimeInterval(8), closed: true)])
        try check(try scalar(url, "SELECT upload FROM daily_stats WHERE date = '2026-10-20'") == 120, "pre-midnight allocation")
        try check(try scalar(url, "SELECT download FROM daily_stats WHERE date = '2026-10-21'") == 120, "post-midnight allocation")
        try check(db.getSummary(startDate: .distantPast).upload == 180, "cross-day conservation")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let from = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let to = calendar.date(byAdding: .day, value: 1, to: from)!
        let parts = DatabaseManager.splitByDay(upload: 23, download: 47, from: from, to: to, calendar: calendar)
        try check(to.timeIntervalSince(from) == 23 * 3600 && parts.count == 1 && parts[0].down == 47, "DST calendar day")
        print("PASS: cross-day allocation and DST conservation")
    }

    private static func restartDedup(_ url: URL) async throws {
        let t = date("2026-10-21T10:00:00Z")
        let first = sample(up: 100, at: t)
        var db: DatabaseManager? = DatabaseManager(databaseURL: url)
        _ = try await db!.recordCheckpoints([first])
        db = nil
        let reopened = DatabaseManager(databaseURL: url)
        let duplicateChanged = try await reopened.recordCheckpoints([first, first])
        try check(!duplicateChanged, "replay reports no new bytes")
        _ = try await reopened.recordCheckpoints([sample(up: 150, at: t.addingTimeInterval(2)), first])
        try check(reopened.getSummary(startDate: .distantPast).upload == 150, "restart counts delta only; stale sample ignored")
        _ = try await reopened.recordCheckpoints([sample(token: "2026-10-21T11:00:00Z", up: 30, at: t.addingTimeInterval(3601))])
        try check(reopened.getSummary(startDate: .distantPast).upload == 180, "ID reuse with new start is separate identity")
        // 旧版本的两张表保持可读；旧连接 ID 重放不再叠加日统计。
        try sql(url, "INSERT INTO daily_stats VALUES ('2026-10-21','Legacy','old.test','TestProxy',70,0); INSERT INTO conn_history VALUES ('legacy','2026-10-21','Legacy','old.test','','TestProxy',70,0,1792576800,1792576801);")
        _ = try await reopened.recordCheckpoints([sample(id: "legacy", up: 70, at: t.addingTimeInterval(10))])
        try check(reopened.getSummary(startDate: .distantPast).upload == 250, "legacy data and replay compatibility")
        print("PASS: reopen/replay deduplication, ID reuse, legacy compatibility")
    }

    private static func rollback(_ url: URL) async throws {
        let db = DatabaseManager(databaseURL: url)
        let t = date("2026-10-21T10:00:00Z")
        let batch = [sample(id: "good", up: 100, at: t), sample(id: "bad", host: "blocked.test", up: 200, at: t)]
        try sql(url, "CREATE TRIGGER injected_failure BEFORE INSERT ON conn_history WHEN NEW.host='blocked.test' BEGIN SELECT RAISE(ABORT,'injected write failure'); END;")
        var failed = false
        do { _ = try await db.recordCheckpoints(batch) } catch { failed = true }
        try check(failed, "write failure is acknowledged")
        for table in ["daily_stats", "conn_history", "traffic_checkpoints"] {
            try check(try scalar(url, "SELECT COUNT(*) FROM \(table)") == 0, "whole batch rolled back in \(table)")
        }
        try sql(url, "DROP TRIGGER injected_failure;")
        _ = try await db.recordCheckpoints(batch)
        _ = try await db.recordCheckpoints(batch)
        try check(db.getSummary(startDate: .distantPast).upload == 300, "failed batch retry is exactly once")
        print("PASS: injected write failure rolls back all tables; retry is idempotent")
    }

    private static func search51(_ url: URL) async throws {
        let db = DatabaseManager(databaseURL: url)
        let t = date("2026-10-21T10:00:00Z")
        let values = (1...51).map { sample(id: "host\($0)", host: $0 == 51 ? "needle_%.example" : "domain\($0).example", up: Int64(52 - $0), at: t) }
        _ = try await db.recordCheckpoints(values)
        let top = db.getTopDomains(startDate: .distantPast)
        try check(top.count == 50 && !top.contains { $0.host == "needle_%.example" }, "needle is outside original Top50")
        let found = db.getTopDomains(startDate: .distantPast, search: "NEEDLE_%")
        try check(found.count == 1 && found[0].host == "needle_%.example", "database filtering before limit with literal wildcards")
        print("PASS: 51st domain is searchable before LIMIT, case-insensitive literal query")
    }

    private static func latestFilters() async throws {
        let gate = QueryGate()
        let vm = TrafficViewModel(loadStats: gate.load)
        vm.refreshStats()
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(gate.requests.isEmpty, "hidden panel does not query")
        vm.setVisible(true)
        try await eventually { gate.requests.count == 1 }
        vm.selectedTimeRange = .week
        vm.selectedTimeRange = .all
        gate.finish(DashboardStats(summary: (upload: 999, download: 999)))
        try await eventually { gate.requests.count == 2 }
        try check(vm.rangeProxyUpload == 0, "old range result never commits")
        try check(gate.requests[1].0 == Date.distantPast, "latest range was retained")
        gate.finish(DashboardStats(summary: (upload: 42, download: 84)))
        try await eventually { vm.rangeProxyUpload == 42 }
        try check(vm.rangeSummaryLabel == "全部走代理", "card label matches selected data")
        for _ in 0..<5 { vm.update(isConnected: true, proxySpeedDown: 0, proxySpeedUp: 0, activeConns: []) }
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(gate.requests.count == 2, "polls with no data changes do not query")
        vm.domainSearchText = "n"
        vm.domainSearchText = "ne"
        vm.domainSearchText = "needle"
        try await eventually { gate.requests.count == 3 }
        try check(gate.requests[2].1 == "needle", "search debounce uses latest text only")
        vm.setVisible(false)
        gate.finish(DashboardStats(summary: (upload: 777, download: 777)))
        vm.persistenceDidFinish(changed: true, error: nil)
        try await Task.sleep(nanoseconds: 20_000_000)
        try check(gate.requests.count == 3 && vm.rangeProxyUpload == 42, "hidden query result rejected and data change deferred")
        vm.setVisible(true)
        try await eventually { gate.requests.count == 4 }
        gate.finish(DashboardStats(summary: (upload: 43, download: 85)))
        try await eventually { vm.rangeProxyUpload == 43 }
        vm.setVisible(false)
        print("PASS: latest filter wins, debounce, visibility, and change-driven queries")
    }

    private static func endpointReconnect() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let clock = FakeClock(date("2026-10-21T10:00:00Z"))
        let endpoints: [EndpointType] = [9097, 9090].map { .http(baseURL: URL(string: "http://127.0.0.1:\($0)")!, secret: nil) }
        let client = MihomoClient(session: session, candidates: { endpoints }, now: { clock.read() })
        StubProtocol.configure(port: nil)
        do { _ = try await client.fetchConnections(); throw Failure(message: "offline should fail") } catch is Failure { throw Failure(message: "offline should fail") } catch {}
        let offlineRequests = StubProtocol.requests().count
        do { _ = try await client.fetchConnections() } catch {}
        try check(StubProtocol.requests().count == offlineRequests, "backoff suppresses immediate re-probe")
        clock.advance(2)
        StubProtocol.configure(port: 9097)
        _ = try await client.fetchConnections()
        try check(StubProtocol.requests() == [9097], "monitor before proxy recovers")
        StubProtocol.configure(port: 9090)
        do { _ = try await client.fetchConnections() } catch {}
        try check(StubProtocol.requests() == [9097], "cached endpoint failure invalidates cache")
        clock.advance(2)
        _ = try await client.fetchConnections()
        try check(StubProtocol.requests() == [9097, 9097, 9090], "re-probe discovers moved endpoint")
        print("PASS: offline startup, bounded backoff, cached-endpoint invalidation and reconnect")
    }

    /// 代理快照夹具显式提供进程名，测试不会触发旧的端口解析回退。
    private nonisolated static func snapshot(_ up: Int64) throws -> MihomoConnectionsSnapshot {
        let raw = """
        {"uploadTotal":0,"downloadTotal":0,"connections":[{"id":"active","upload":\(up),"download":0,"start":"2026-10-21T10:00:00Z","chains":["TestProxy"],"metadata":{"host":"blocked.test","process":"TestApp"}}]}
        """
        return try JSONDecoder().decode(MihomoConnectionsSnapshot.self, from: Data(raw.utf8))
    }

    private static func trackerShutdown(_ url: URL) async throws {
        let db = DatabaseManager(databaseURL: url)
        let clock = FakeClock(date("2026-10-21T10:00:00Z"))
        let feed = SnapshotFeed([try snapshot(100), nil, try snapshot(200), MihomoConnectionsSnapshot(downloadTotal: 0, uploadTotal: 0, connections: [])])
        let tracker = TrafficTracker(database: db, fetch: { try await feed.next() }, now: { clock.read() })
        await tracker.poll()
        clock.advance(5)
        await tracker.poll()
        clock.advance(5)
        await tracker.poll()
        try check(TrafficViewModel.shared.proxyUploadSpeed == 10, "failed poll does not shorten rate denominator")
        try check(db.getSummary(startDate: .distantPast).upload == 0, "active samples buffered before checkpoint deadline")
        try sql(url, "CREATE TRIGGER tracker_failure BEFORE INSERT ON conn_history BEGIN SELECT RAISE(ABORT,'injected tracker failure'); END;")
        let failedStop = await tracker.stop()
        try check(!failedStop && TrafficViewModel.shared.persistenceError != nil, "failed shutdown acknowledged, buffer retained")
        try sql(url, "DROP TRIGGER tracker_failure;")
        let savedStop = await tracker.stop()
        try check(savedStop && db.getSummary(startDate: .distantPast).upload == 200, "retry saves active connection without needing disappearance")
        let reopenedTracker = TrafficTracker(database: db, fetch: { try snapshot(200) }, now: { clock.read() })
        await reopenedTracker.poll()
        _ = await reopenedTracker.stop()
        try check(db.getSummary(startDate: .distantPast).upload == 200, "tracker restart does not double count active connection")
        // 已关闭连接的批次失败也要保留；重试只更新关闭标志，不再叠加已保存累计量。
        clock.advance(5)
        await tracker.poll()
        try sql(url, "CREATE TRIGGER closed_failure BEFORE INSERT ON conn_history BEGIN SELECT RAISE(ABORT,'closed write failure'); END;")
        let closedFailed = await tracker.flush()
        try check(!closedFailed, "closed connection failure acknowledged")
        try sql(url, "DROP TRIGGER closed_failure;")
        let closedSaved = await tracker.stop()
        try check(closedSaved && db.getSummary(startDate: .distantPast).upload == 200, "closed sample retained and retried without duplicate bytes")
        try check(try scalar(url, "SELECT closed FROM traffic_checkpoints") == 1, "closed state durably acknowledged")
        let timedURL = url.deletingLastPathComponent().appendingPathComponent("timed.db")
        let timedDB = DatabaseManager(databaseURL: timedURL)
        let timedFeed = SnapshotFeed([try snapshot(100), try snapshot(150), try snapshot(200)])
        let timed = TrafficTracker(database: timedDB, fetch: { try await timedFeed.next() }, now: { clock.read() })
        await timed.poll()
        clock.advance(14)
        await timed.poll()
        try check(timedDB.getSummary(startDate: .distantPast).upload == 0, "checkpoint remains buffered before 15 seconds")
        clock.advance(1)
        await timed.poll()
        try check(timedDB.getSummary(startDate: .distantPast).upload == 200, "active checkpoint persisted at 15 seconds")
        _ = await timed.stop()
        print("PASS: recovery speed denominator, buffered active save, failed shutdown retry, tracker restart")
    }
}
