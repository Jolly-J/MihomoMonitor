//
//  DatabaseManager.swift
//  MihomoMonitor
//
//  [架构层级] Persistence / 持久化存储层
//  [核心职责] 基于 SQLite3 的本地连接日志与流量统计数据访问管理器，处理数据库打开、表迁移、连接历史写入、多维聚合查询与历史数据清理。
//  [关键类型] DatabaseManager（单例）
//  [依赖关系] 依赖 SQLite3 C 库、TrafficModels
//  [并发安全] 拥有专属串行 DispatchQueue 保护所有数据库读写；字符串绑定使用 SQLITE_TRANSIENT；内部私有函数无重入死锁。
//

import Foundation
import SQLite3

nonisolated final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()
    
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.local.MihomoMonitor.DatabaseQueue", qos: .utility)
    
    /// 显式 URL 用于隔离测试；默认路径只在生产单例首次使用时打开。
    init(databaseURL: URL? = nil) {
        queue.sync {
            let url = databaseURL ?? Self.defaultDatabaseURL()
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw databaseError() }
                sqlite3_busy_timeout(db, 1_000)
                try executeChecked("PRAGMA journal_mode = WAL;")
                try executeChecked("PRAGMA synchronous = NORMAL;")
                try createTables()
            } catch {
                print("[DatabaseManager] 初始化失败: \(error.localizedDescription)")
            }
        }
        if databaseURL == nil { cleanOldLogs(retentionDays: 3) }
    }

    deinit { if let db { sqlite3_close(db) } }

    /// 生产数据库路径；测试始终传入临时目录 URL。
    private static func defaultDatabaseURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MihomoMonitor/monitor.db")
    }

    /// 所有 SQLite 失败均携带可展示的错误，禁止将未提交的写入视为成功。
    private func databaseError() -> NSError {
        NSError(domain: "MihomoMonitor.Database", code: Int(sqlite3_errcode(db)),
                userInfo: [NSLocalizedDescriptionKey: db.map { String(cString: sqlite3_errmsg($0)) } ?? "数据库未打开"])
    }

    private func executeChecked(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw databaseError() }
    }

    private func executeRaw(sql: String) -> Bool {
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }
    
    private func createTables() throws {
        let createDailyStats = """
        CREATE TABLE IF NOT EXISTS daily_stats (
            date TEXT NOT NULL,
            app TEXT NOT NULL,
            host TEXT NOT NULL,
            proxy TEXT NOT NULL,
            upload INTEGER NOT NULL DEFAULT 0,
            download INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (date, app, host, proxy)
        );
        """
        
        let createConnHistory = """
        CREATE TABLE IF NOT EXISTS conn_history (
            id TEXT PRIMARY KEY,
            date TEXT NOT NULL,
            app TEXT NOT NULL,
            host TEXT NOT NULL,
            dest_ip TEXT NOT NULL,
            proxy TEXT NOT NULL,
            upload INTEGER NOT NULL DEFAULT 0,
            download INTEGER NOT NULL DEFAULT 0,
            start_time INTEGER NOT NULL,
            end_time INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_conn_date ON conn_history(date);
        CREATE INDEX IF NOT EXISTS idx_conn_app ON conn_history(app);
        """
        
        // 仅增加新表，不重写旧日统计或历史；旧版本的关闭日归属无法事后修复。
        try executeChecked(createDailyStats)
        try executeChecked(createConnHistory)
        try executeChecked("""
        CREATE TABLE IF NOT EXISTS traffic_checkpoints (
            id TEXT PRIMARY KEY,
            upload INTEGER NOT NULL,
            download INTEGER NOT NULL,
            observed_at REAL NOT NULL,
            closed INTEGER NOT NULL DEFAULT 0
        );
        """)
    }

    // MARK: - Atomic checkpoint batches
    /// 一批累计快照共用事务：每日增量、历史行和去重水位全部成功才确认。
    /// 重放、重启和结果不确定后的重试均由持久化水位去重；失败则整批回滚。
    func recordCheckpoints(_ samples: [TrafficCheckpoint]) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.executeChecked("BEGIN IMMEDIATE;")
                    var changed = false
                    do {
                        for sample in samples {
                            if try self.writeCheckpoint(sample) { changed = true }
                        }
                        try self.executeChecked("COMMIT;")
                        continuation.resume(returning: changed)
                    } catch {
                        _ = self.executeRaw(sql: "ROLLBACK;")
                        throw error
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// 检查 prepare / bind / step 的返回值；语句在所有错误分支均 finalize。
    private func run(_ sql: String, texts: [String], integers: [Int64] = [], reals: [Double] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw databaseError() }
        defer { sqlite3_finalize(stmt) }
        var index: Int32 = 1
        for text in texts {
            guard sqlite3_bind_text(stmt, index, text, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw databaseError() }
            index += 1
        }
        for integer in integers {
            guard sqlite3_bind_int64(stmt, index, integer) == SQLITE_OK else { throw databaseError() }
            index += 1
        }
        for real in reals {
            guard sqlite3_bind_double(stmt, index, real) == SQLITE_OK else { throw databaseError() }
            index += 1
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw databaseError() }
    }

    /// 读取新水位；兼容旧历史中已有的连接 ID，避免升级后重放再次加到 daily_stats。
    private func watermark(for sample: TrafficCheckpoint) throws -> (up: Int64, down: Int64, time: Date, closed: Bool)? {
        let sql = """
        SELECT upload, download, observed_at, closed FROM traffic_checkpoints WHERE id = ?
        UNION ALL
        SELECT upload, download, end_time, 1 FROM conn_history WHERE id = ? LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw databaseError() }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_bind_text(stmt, 1, sample.identity, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, sample.connectionID, -1, SQLITE_TRANSIENT) == SQLITE_OK else { throw databaseError() }
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw databaseError() }
        return (sqlite3_column_int64(stmt, 0), sqlite3_column_int64(stmt, 1),
                Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)), sqlite3_column_int(stmt, 3) != 0)
    }

    /// 使用累计最大值抗重复/乱序/计数回退。API start 是稳定身份的一部分。
    private func writeCheckpoint(_ sample: TrafficCheckpoint) throws -> Bool {
        guard sample.proxyNode != "DIRECT", sample.proxyNode != "REJECT", !sample.proxyNode.isEmpty else { return false }
        let previous = try watermark(for: sample)
        if let previous, sample.observedAt < previous.time { return false }
        let up = max(previous?.up ?? 0, max(0, sample.upload))
        let down = max(previous?.down ?? 0, max(0, sample.download))
        let deltaUp = up - (previous?.up ?? 0)
        let deltaDown = down - (previous?.down ?? 0)
        let closed = sample.isClosed || (previous?.closed ?? false)
        if let previous, sample.observedAt == previous.time, deltaUp == 0, deltaDown == 0, closed == previous.closed { return false }

        // 每个采样间隔独立分日；跨午夜按时长估算，整数余数留在最后一天以严格守恒。
        let from = min(previous?.time ?? sample.startedAt, sample.observedAt)
        for part in Self.splitByDay(upload: deltaUp, download: deltaDown, from: from, to: sample.observedAt) {
            try run("""
            INSERT INTO daily_stats (date, app, host, proxy, upload, download) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(date, app, host, proxy) DO UPDATE SET
                upload = upload + excluded.upload, download = download + excluded.download;
            """, texts: [part.date, sample.appName, sample.host, sample.proxyNode], integers: [part.up, part.down])
        }
        // 历史累计值与水位同事务更新；活跃连接也保存，退出不再依赖“连接消失”。
        try run("""
        INSERT INTO conn_history (id, date, app, host, dest_ip, proxy, upload, download, start_time, end_time)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET date = excluded.date, upload = excluded.upload,
            download = excluded.download, end_time = excluded.end_time;
        """, texts: [sample.identity, Self.dayString(sample.observedAt), sample.appName, sample.host, sample.destinationIP, sample.proxyNode],
            integers: [up, down, Int64(sample.startedAt.timeIntervalSince1970), Int64(sample.observedAt.timeIntervalSince1970)])
        try run("""
        INSERT INTO traffic_checkpoints (id, upload, download, closed, observed_at) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET upload = excluded.upload, download = excluded.download,
            closed = excluded.closed, observed_at = excluded.observed_at;
        """, texts: [sample.identity], integers: [up, down, closed ? 1 : 0], reals: [sample.observedAt.timeIntervalSince1970])
        return deltaUp > 0 || deltaDown > 0
    }

    /// 按本地日历拆分（含夏令时的 23/25 小时日），不假设一天总是 86400 秒。
    static func splitByDay(upload: Int64, download: Int64, from: Date, to: Date,
                           calendar: Calendar = .current) -> [(date: String, up: Int64, down: Int64)] {
        guard upload > 0 || download > 0 else { return [] }
        var cursor = from
        var remainingUp = upload
        var remainingDown = download
        var parts: [(String, Int64, Int64)] = []
        while cursor < to {
            let boundary = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? to
            let end = min(boundary, to)
            let fraction = end.timeIntervalSince(cursor) / to.timeIntervalSince(cursor)
            let up = end == to ? remainingUp : Int64(Double(remainingUp) * fraction)
            let down = end == to ? remainingDown : Int64(Double(remainingDown) * fraction)
            parts.append((dayString(cursor, calendar: calendar), up, down))
            remainingUp -= up
            remainingDown -= down
            cursor = end
        }
        if parts.isEmpty { parts.append((dayString(to, calendar: calendar), upload, download)) }
        return parts
    }

    /// 固定公历与数字格式，保持旧表 yyyy-MM-dd 键兼容。
    private static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Query Top Apps (Proxy Only)
    func getTopApps(startDate: Date, limit: Int = 50) -> [AppTrafficStat] {
        return queue.sync {
            queryTopApps(startDate: startDate, limit: limit)
        }
    }
    
    private func queryTopApps(startDate: Date, limit: Int = 50) -> [AppTrafficStat] {
        guard let db = db else { return [] }
        let startStr = startDate == Date.distantPast ? "0000-01-01" : Self.dayString(startDate)
        
        let sql = """
        SELECT app, SUM(upload) as total_up, SUM(download) as total_down, (SUM(upload) + SUM(download)) as total_bytes
        FROM daily_stats
        WHERE date >= ? AND proxy != 'DIRECT' AND proxy != ''
        GROUP BY app
        HAVING total_bytes > 0
        ORDER BY total_bytes DESC
        LIMIT ?;
        """
        
        var stmt: OpaquePointer?
        var grandTotal: Int64 = 0
        
        struct TempRow {
            let app: String
            let up: Int64
            let down: Int64
            let total: Int64
        }
        var tempRows: [TempRow] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (startStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let app = String(cString: sqlite3_column_text(stmt, 0))
                let up = sqlite3_column_int64(stmt, 1)
                let down = sqlite3_column_int64(stmt, 2)
                let total = sqlite3_column_int64(stmt, 3)
                tempRows.append(TempRow(app: app, up: up, down: down, total: total))
                grandTotal += total
            }
            sqlite3_finalize(stmt)
        }
        
        return tempRows.map { row in
            let pct = grandTotal > 0 ? Double(row.total) / Double(grandTotal) : 0.0
            return AppTrafficStat(
                appName: row.app,
                uploadBytes: row.up,
                downloadBytes: row.down,
                totalBytes: row.total,
                percentage: pct
            )
        }
    }
    
    // MARK: - Query Top Domains (Proxy Only)
    func getTopDomains(startDate: Date, limit: Int = 50, search: String = "") -> [DomainTrafficStat] {
        return queue.sync {
            queryTopDomains(startDate: startDate, limit: limit, search: search)
        }
    }
    
    private func queryTopDomains(startDate: Date, limit: Int = 50, search: String = "") -> [DomainTrafficStat] {
        guard let db = db else { return [] }
        let startStr = startDate == Date.distantPast ? "0000-01-01" : Self.dayString(startDate)
        
        let sql = """
        SELECT host, SUM(upload) as total_up, SUM(download) as total_down, (SUM(upload) + SUM(download)) as total_bytes
        FROM daily_stats
        WHERE date >= ? AND host != '' AND proxy != 'DIRECT' AND proxy != ''
          AND instr(lower(host), lower(?)) > 0
        GROUP BY host
        HAVING total_bytes > 0
        ORDER BY total_bytes DESC
        LIMIT ?;
        """
        
        var stmt: OpaquePointer?
        var grandTotal: Int64 = 0
        struct TempRow {
            let host: String
            let up: Int64
            let down: Int64
            let total: Int64
        }
        var tempRows: [TempRow] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (startStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, search.trimmingCharacters(in: .whitespacesAndNewlines), -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let host = String(cString: sqlite3_column_text(stmt, 0))
                let up = sqlite3_column_int64(stmt, 1)
                let down = sqlite3_column_int64(stmt, 2)
                let total = sqlite3_column_int64(stmt, 3)
                tempRows.append(TempRow(host: host, up: up, down: down, total: total))
                grandTotal += total
            }
            sqlite3_finalize(stmt)
        }
        
        return tempRows.map { row in
            let pct = grandTotal > 0 ? Double(row.total) / Double(grandTotal) : 0.0
            return DomainTrafficStat(
                host: row.host,
                uploadBytes: row.up,
                downloadBytes: row.down,
                totalBytes: row.total,
                percentage: pct
            )
        }
    }
    
    // MARK: - Query Top Proxies (Excludes DIRECT)
    func getTopProxies(startDate: Date, limit: Int = 50) -> [ProxyTrafficStat] {
        return queue.sync {
            queryTopProxies(startDate: startDate, limit: limit)
        }
    }
    
    private func queryTopProxies(startDate: Date, limit: Int = 50) -> [ProxyTrafficStat] {
        guard let db = db else { return [] }
        let startStr = startDate == Date.distantPast ? "0000-01-01" : Self.dayString(startDate)
        
        let sql = """
        SELECT proxy, SUM(upload) as total_up, SUM(download) as total_down, (SUM(upload) + SUM(download)) as total_bytes
        FROM daily_stats
        WHERE date >= ? AND proxy != '' AND proxy != 'DIRECT'
        GROUP BY proxy
        HAVING total_bytes > 0
        ORDER BY total_bytes DESC
        LIMIT ?;
        """
        
        var stmt: OpaquePointer?
        var grandTotal: Int64 = 0
        struct TempRow {
            let proxy: String
            let up: Int64
            let down: Int64
            let total: Int64
        }
        var tempRows: [TempRow] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (startStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let proxy = String(cString: sqlite3_column_text(stmt, 0))
                let up = sqlite3_column_int64(stmt, 1)
                let down = sqlite3_column_int64(stmt, 2)
                let total = sqlite3_column_int64(stmt, 3)
                tempRows.append(TempRow(proxy: proxy, up: up, down: down, total: total))
                grandTotal += total
            }
            sqlite3_finalize(stmt)
        }
        
        return tempRows.map { row in
            let pct = grandTotal > 0 ? Double(row.total) / Double(grandTotal) : 0.0
            return ProxyTrafficStat(
                nodeName: row.proxy,
                uploadBytes: row.up,
                downloadBytes: row.down,
                totalBytes: row.total,
                percentage: pct
            )
        }
    }
    
    // MARK: - Query Summary (Proxy Only)
    func getSummary(startDate: Date) -> (upload: Int64, download: Int64) {
        return queue.sync {
            querySummary(startDate: startDate)
        }
    }
    
    private func querySummary(startDate: Date) -> (upload: Int64, download: Int64) {
        guard let db = db else { return (0, 0) }
        let startStr = startDate == Date.distantPast ? "0000-01-01" : Self.dayString(startDate)
        
        let sql = """
        SELECT COALESCE(SUM(upload), 0), COALESCE(SUM(download), 0)
        FROM daily_stats
        WHERE date >= ? AND proxy != 'DIRECT' AND proxy != '';
        """
        
        var stmt: OpaquePointer?
        var up: Int64 = 0
        var down: Int64 = 0
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (startStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                up = sqlite3_column_int64(stmt, 0)
                down = sqlite3_column_int64(stmt, 1)
            }
            sqlite3_finalize(stmt)
        }
        return (up, down)
    }
    
    // MARK: - Cleanup
    func cleanOldLogs(retentionDays: Int = 3) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let cutoffStr = formatter.string(from: cutoffDate)
            
            let sql = "DELETE FROM conn_history WHERE date < ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (cutoffStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }
    
    // MARK: - Async Query API (Non-blocking UI, Deadlock-free)
    /// 后台一次读取仪表盘；域名条件先应用到数据库，再截取 Top 50。
    func fetchDashboardStats(startDate: Date, domainSearch: String = "") async -> DashboardStats {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: DashboardStats(
                    apps: self.queryTopApps(startDate: startDate, limit: 50),
                    domains: self.queryTopDomains(startDate: startDate, limit: 50, search: domainSearch),
                    proxies: self.queryTopProxies(startDate: startDate, limit: 50),
                    summary: self.querySummary(startDate: startDate),
                    allTimeSummary: self.querySummary(startDate: Date.distantPast)))
            }
        }
    }
}
