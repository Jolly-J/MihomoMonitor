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

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()
    
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.local.MihomoMonitor.DatabaseQueue", qos: .utility)
    
    private init() {
        openDatabase()
        createTables()
        cleanOldLogs(retentionDays: 3)
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    private func getDatabaseURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MihomoMonitor", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("monitor.db")
    }
    
    private func openDatabase() {
        let dbURL = getDatabaseURL()
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("Failed to open SQLite database at \(dbURL.path)")
        } else {
            _ = executeRaw(sql: "PRAGMA journal_mode = WAL;")
            _ = executeRaw(sql: "PRAGMA synchronous = NORMAL;")
        }
    }
    
    private func executeRaw(sql: String) -> Bool {
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }
    
    private func createTables() {
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
        
        _ = executeRaw(sql: createDailyStats)
        _ = executeRaw(sql: createConnHistory)
        
        // Clean any accidental DIRECT entries
        _ = executeRaw(sql: "DELETE FROM daily_stats WHERE proxy = 'DIRECT';")
        _ = executeRaw(sql: "DELETE FROM conn_history WHERE proxy = 'DIRECT';")
    }
    
    // MARK: - Write Operations (Only Proxy Traffic)
    func recordClosedConnection(_ record: ClosedConnectionRecord) {
        // Enforce proxy-only filter
        guard record.proxyNode != "DIRECT" && !record.proxyNode.isEmpty else {
            return
        }
        
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            
            // 1. Upsert into daily_stats
            let upsertSQL = """
            INSERT INTO daily_stats (date, app, host, proxy, upload, download)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(date, app, host, proxy) DO UPDATE SET
                upload = upload + excluded.upload,
                download = download + excluded.download;
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (record.dateStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, (record.appName as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, (record.host as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, (record.proxyNode as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 5, record.uploadBytes)
                sqlite3_bind_int64(stmt, 6, record.downloadBytes)
                
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            
            // 2. Insert into conn_history
            let insertConnSQL = """
            INSERT OR REPLACE INTO conn_history (id, date, app, host, dest_ip, proxy, upload, download, start_time, end_time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            
            if sqlite3_prepare_v2(db, insertConnSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (record.id as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, (record.dateStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, (record.appName as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, (record.host as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, (record.destinationIP as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 6, (record.proxyNode as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 7, record.uploadBytes)
                sqlite3_bind_int64(stmt, 8, record.downloadBytes)
                sqlite3_bind_int64(stmt, 9, record.startTime)
                sqlite3_bind_int64(stmt, 10, record.endTime)
                
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }
    
    // MARK: - Query Top Apps (Proxy Only)
    func getTopApps(startDate: Date, limit: Int = 50) -> [AppTrafficStat] {
        return queue.sync {
            queryTopApps(startDate: startDate, limit: limit)
        }
    }
    
    private func queryTopApps(startDate: Date, limit: Int = 50) -> [AppTrafficStat] {
        guard let db = db else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startStr = formatter.string(from: startDate)
        
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
    func getTopDomains(startDate: Date, limit: Int = 50) -> [DomainTrafficStat] {
        return queue.sync {
            queryTopDomains(startDate: startDate, limit: limit)
        }
    }
    
    private func queryTopDomains(startDate: Date, limit: Int = 50) -> [DomainTrafficStat] {
        guard let db = db else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startStr = formatter.string(from: startDate)
        
        let sql = """
        SELECT host, SUM(upload) as total_up, SUM(download) as total_down, (SUM(upload) + SUM(download)) as total_bytes
        FROM daily_stats
        WHERE date >= ? AND host != '' AND proxy != 'DIRECT' AND proxy != ''
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
            sqlite3_bind_int(stmt, 2, Int32(limit))
            
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startStr = formatter.string(from: startDate)
        
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startStr = formatter.string(from: startDate)
        
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
    func fetchDashboardStats(startDate: Date) async -> (
        apps: [AppTrafficStat],
        domains: [DomainTrafficStat],
        proxies: [ProxyTrafficStat],
        summary: (upload: Int64, download: Int64),
        allTimeSummary: (upload: Int64, download: Int64)
    ) {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: ([], [], [], (0, 0), (0, 0)))
                    return
                }
                // Call private query functions directly WITHOUT queue.sync to avoid deadlocks
                let apps = self.queryTopApps(startDate: startDate, limit: 50)
                let domains = self.queryTopDomains(startDate: startDate, limit: 50)
                let proxies = self.queryTopProxies(startDate: startDate, limit: 50)
                let summary = self.querySummary(startDate: startDate)
                let allTime = self.querySummary(startDate: Date.distantPast)
                continuation.resume(returning: (apps, domains, proxies, summary, allTime))
            }
        }
    }
}
