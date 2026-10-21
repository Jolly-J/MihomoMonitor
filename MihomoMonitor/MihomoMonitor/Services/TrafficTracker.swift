//
//  TrafficTracker.swift
//  MihomoMonitor
//
//  [架构层级] Services / 流量监控采集编排
//  [核心职责] 轮询代理快照、缓存分时累计样本、批量确认检查点并在正常退出时排空待写数据。
//  [关键类型] TrafficTracker, TrackedConnectionState
//  [依赖关系] MihomoClient、ProcessResolver、DatabaseManager、AppState
//  [并发安全] actor 串行隔离采样字典与待写批次；退出先等待轮询任务结束，再排空数据。
//

import Foundation

/// 保留最新已观察累计量；已关闭状态直到对应批次提交成功才清理。
private struct TrackedConnectionState {
    var checkpoint: TrafficCheckpoint
    var isClosed: Bool
}

actor TrafficTracker {
    static let shared = TrafficTracker()

    // 采样保持 1.5 秒，磁盘事务约每 15 秒一次；午夜边界和退出也会触发保存。
    private let database: DatabaseManager
    private let fetch: @Sendable () async throws -> MihomoConnectionsSnapshot
    private let now: @Sendable () -> Date
    private var timer: Task<Void, Never>?
    private var isRunning = false
    private var trackedConnections: [String: TrackedConnectionState] = [:]
    private var pending: [TrafficCheckpoint] = []
    private var lastSuccessfulTick: Date?
    private var lastFlushTime: Date?
    private var flushInProgress = false

    /// 允许注入临时数据库、时钟和快照源；测试不会访问真实代理或流量文件。
    init(database: DatabaseManager = .shared,
         fetch: @escaping @Sendable () async throws -> MihomoConnectionsSnapshot = { try await MihomoClient.shared.fetchConnections() },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.fetch = fetch
        self.now = now
    }

    /// 启动唯一轮询任务。
    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { break }
            }
        }
    }

    /// 正常退出先取消并等待在途轮询，再重试保存；失败返回 false，宿主应取消退出。
    func stop() async -> Bool {
        isRunning = false
        let runningTask = timer
        timer = nil
        runningTask?.cancel()
        await runningTask?.value
        for attempt in 0..<3 {
            if await flush() { return true }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 250_000_000) }
        }
        return false
    }

    /// 只有成功快照才推进速率分母；失败期间保留上次成功观察点。
    func poll() async {
        do {
            let snapshot = try await fetch()
            guard !Task.isCancelled else { return }
            let timestamp = now()
            let items = consume(snapshot, at: timestamp)
            if lastFlushTime == nil { lastFlushTime = timestamp }
            let crossedDay = lastSuccessfulTick.map { !Calendar.current.isDate($0, inSameDayAs: timestamp) } ?? false
            lastSuccessfulTick = timestamp
            if crossedDay || timestamp.timeIntervalSince(lastFlushTime!) >= 15 { _ = await flush() }
            await MainActor.run {
                AppState.shared.update(isConnected: true,
                    proxySpeedDown: items.reduce(0) { $0 + $1.downloadSpeed },
                    proxySpeedUp: items.reduce(0) { $0 + $1.uploadSpeed }, activeConns: items)
            }
        } catch {
            // 即使代理离线，之前观察到但尚未确认的字节仍按节流周期重试保存。
            if !pending.isEmpty, now().timeIntervalSince(lastFlushTime ?? .distantPast) >= 15 { _ = await flush() }
            await MainActor.run {
                AppState.shared.update(isConnected: false, proxySpeedDown: 0, proxySpeedUp: 0,
                                       activeConns: [], connectionError: error.localizedDescription)
            }
        }
    }

    /// 生成可幂等重放的累计样本。跨日分配由 Persistence 按相邻观察时间处理。
    private func consume(_ snapshot: MihomoConnectionsSnapshot, at timestamp: Date) -> [ActiveConnItem] {
        var currentIDs = Set<String>()
        var items: [ActiveConnItem] = []
        let elapsed = max(0.5, timestamp.timeIntervalSince(lastSuccessfulTick ?? timestamp))
        for conn in snapshot.connections {
            guard let node = conn.chains?.first, node != "DIRECT", node != "REJECT",
                  !(conn.chains?.contains("DIRECT") ?? true) else { continue }
            let sample = TrafficCheckpoint(connectionID: conn.id, startToken: conn.start,
                appName: ProcessResolver.shared.resolveProcess(for: conn), host: conn.metadata.host ?? "",
                destinationIP: conn.metadata.destinationIP ?? "", proxyNode: node,
                upload: max(0, conn.upload), download: max(0, conn.download),
                startedAt: Self.parseStart(conn.start) ?? timestamp, observedAt: timestamp, isClosed: false)
            let key = sample.identity
            currentIDs.insert(key)
            let previous = trackedConnections[key]?.checkpoint
            let upSpeed = previous.map { Int64(Double(max(0, sample.upload - $0.upload)) / elapsed) } ?? 0
            let downSpeed = previous.map { Int64(Double(max(0, sample.download - $0.download)) / elapsed) } ?? 0
            trackedConnections[key] = TrackedConnectionState(checkpoint: sample, isClosed: false)
            pending.append(sample)
            items.append(ActiveConnItem(id: key, appName: sample.appName, host: sample.host,
                destinationIP: sample.destinationIP, proxyNode: node, rule: conn.rule ?? "",
                uploadSpeed: upSpeed, downloadSpeed: downSpeed, uploadTotal: sample.upload,
                downloadTotal: sample.download, startTime: sample.startedAt))
        }
        for key in Array(trackedConnections.keys) where !currentIDs.contains(key) {
            guard var state = trackedConnections[key], !state.isClosed else { continue }
            let old = state.checkpoint
            // 消失时没有最终累计值，不能把不可见尾流量伪造为已计量。
            let closed = TrafficCheckpoint(connectionID: old.connectionID, startToken: old.startToken,
                appName: old.appName, host: old.host, destinationIP: old.destinationIP, proxyNode: old.proxyNode,
                upload: old.upload, download: old.download, startedAt: old.startedAt,
                observedAt: timestamp, isClosed: true)
            state.checkpoint = closed
            state.isClosed = true
            trackedConnections[key] = state
            pending.append(closed)
        }
        return items.sorted { $0.downloadSpeed + $0.uploadSpeed > $1.downloadSpeed + $1.uploadSpeed }
    }

    /// 成功确认后仅移除本批次样本；await 期间追加的样本不会被误删。
    @discardableResult
    func flush() async -> Bool {
        guard !flushInProgress else { return false }
        guard !pending.isEmpty else { return true }
        flushInProgress = true
        defer { flushInProgress = false }
        let batch = pending
        do {
            let changed = try await database.recordCheckpoints(batch)
            pending.removeFirst(batch.count)
            lastFlushTime = now()
            let pendingIDs = Set(pending.map(\.identity))
            for (key, state) in trackedConnections where state.isClosed && !pendingIDs.contains(key) {
                ProcessResolver.shared.forgetConnection(state.checkpoint.connectionID)
                trackedConnections.removeValue(forKey: key)
            }
            await MainActor.run { TrafficViewModel.shared.persistenceDidFinish(changed: changed, error: nil) }
            return true
        } catch {
            lastFlushTime = now()
            compactPendingSamples()
            await MainActor.run { TrafficViewModel.shared.persistenceDidFinish(changed: false, error: error.localizedDescription) }
            return false
        }
    }

    /// 持久化长期失败时，按连接/日仅保留首尾样本；午夜两侧仍保留原始采样边界。
    /// 不丢弃任何连接的累计字节，但数据库一直不可写时，未确认连接数仍可能增长。
    private func compactPendingSamples() {
        var edges: [String: (first: Int, last: Int)] = [:]
        for (index, sample) in pending.enumerated() {
            let day = Calendar.current.startOfDay(for: sample.observedAt).timeIntervalSince1970
            let key = sample.identity + "|" + String(day)
            edges[key] = (edges[key]?.first ?? index, index)
        }
        let indexes = Set(edges.values.flatMap { [$0.first, $0.last] })
        pending = pending.enumerated().compactMap { indexes.contains($0.offset) ? $0.element : nil }
    }

    /// Mihomo start 为 RFC3339；同时兼容带小数秒与整秒的返回格式。
    private static func parseStart(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
