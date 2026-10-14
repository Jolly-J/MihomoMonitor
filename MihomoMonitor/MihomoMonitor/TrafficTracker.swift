//
//  TrafficTracker.swift
//  MihomoMonitor
//
//  Created by Jo lin on 2026/10/14.
//

import Foundation
import Combine

struct TrackedConnectionState {
    let id: String
    let appName: String
    let host: String
    let destinationIP: String
    let proxyNode: String
    let rule: String
    var lastUpload: Int64
    var lastDownload: Int64
    var uploadSpeed: Int64
    var downloadSpeed: Int64
    let startTime: Date
}

final class TrafficTracker: @unchecked Sendable {
    static let shared = TrafficTracker()
    
    private var isRunning = false
    private var timer: Task<Void, Never>?
    
    private var trackedConnections: [String: TrackedConnectionState] = [:]
    private var lastTickTime: Date = Date()
    
    private init() {}
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        print("[TrafficTracker] Service started (Proxy-Only mode).")
        
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            }
        }
    }
    
    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
        print("[TrafficTracker] Service stopped.")
    }
    
    // MARK: - Proxy Filter Rule
    private func isProxyConnection(_ conn: MihomoRawConnection) -> Bool {
        guard let chains = conn.chains, !chains.isEmpty else { return false }
        guard let first = chains.first, first != "DIRECT", first != "REJECT" else { return false }
        if chains.contains("DIRECT") { return false }
        return true
    }
    
    private func poll() async {
        let now = Date()
        let deltaSec = max(0.5, now.timeIntervalSince(lastTickTime))
        lastTickTime = now
        
        do {
            let snapshot = try await MihomoClient.shared.fetchConnections()
            
            // Filter: ONLY track connections going through proxy nodes
            let proxyConnections = snapshot.connections.filter { isProxyConnection($0) }
            
            var currentIds = Set<String>()
            var activeItems: [ActiveConnItem] = []
            var totalProxyDownSpeed: Int64 = 0
            var totalProxyUpSpeed: Int64 = 0
            
            for conn in proxyConnections {
                let id = conn.id
                currentIds.insert(id)
                
                let app = ProcessResolver.shared.resolveProcess(for: conn)
                let host = conn.metadata.host ?? ""
                let destIP = conn.metadata.destinationIP ?? ""
                let node = conn.chains?.first ?? "Proxy"
                let rule = conn.rule ?? ""
                
                if var existing = trackedConnections[id] {
                    let dDown = max(0, conn.download - existing.lastDownload)
                    let dUp = max(0, conn.upload - existing.lastUpload)
                    existing.uploadSpeed = Int64(Double(dUp) / deltaSec)
                    existing.downloadSpeed = Int64(Double(dDown) / deltaSec)
                    existing.lastDownload = conn.download
                    existing.lastUpload = conn.upload
                    trackedConnections[id] = existing
                    
                    totalProxyDownSpeed += existing.downloadSpeed
                    totalProxyUpSpeed += existing.uploadSpeed
                    
                    activeItems.append(ActiveConnItem(
                        id: id,
                        appName: app,
                        host: host,
                        destinationIP: destIP,
                        proxyNode: node,
                        rule: rule,
                        uploadSpeed: existing.uploadSpeed,
                        downloadSpeed: existing.downloadSpeed,
                        uploadTotal: conn.upload,
                        downloadTotal: conn.download,
                        startTime: existing.startTime
                    ))
                } else {
                    let newState = TrackedConnectionState(
                        id: id,
                        appName: app,
                        host: host,
                        destinationIP: destIP,
                        proxyNode: node,
                        rule: rule,
                        lastUpload: conn.upload,
                        lastDownload: conn.download,
                        uploadSpeed: 0,
                        downloadSpeed: 0,
                        startTime: now
                    )
                    trackedConnections[id] = newState
                    
                    activeItems.append(ActiveConnItem(
                        id: id,
                        appName: app,
                        host: host,
                        destinationIP: destIP,
                        proxyNode: node,
                        rule: rule,
                        uploadSpeed: 0,
                        downloadSpeed: 0,
                        uploadTotal: conn.upload,
                        downloadTotal: conn.download,
                        startTime: now
                    ))
                }
            }
            
            // Detect closed connections
            let closedIds = Set(trackedConnections.keys).subtracting(currentIds)
            let todayStr = FormatUtils.todayDateString()
            let nowEpoch = Int64(now.timeIntervalSince1970)
            
            for closedId in closedIds {
                if let closedState = trackedConnections[closedId] {
                    // Record only proxy connections to DB
                    let record = ClosedConnectionRecord(
                        id: closedId,
                        dateStr: todayStr,
                        appName: closedState.appName,
                        host: closedState.host,
                        destinationIP: closedState.destinationIP,
                        proxyNode: closedState.proxyNode,
                        uploadBytes: closedState.lastUpload,
                        downloadBytes: closedState.lastDownload,
                        startTime: Int64(closedState.startTime.timeIntervalSince1970),
                        endTime: nowEpoch
                    )
                    DatabaseManager.shared.recordClosedConnection(record)
                    ProcessResolver.shared.forgetConnection(closedId)
                    trackedConnections.removeValue(forKey: closedId)
                }
            }
            
            // Sort active items by current combined speed descending
            activeItems.sort { ($0.downloadSpeed + $0.uploadSpeed) > ($1.downloadSpeed + $1.uploadSpeed) }
            
            // Update UI State with proxy metrics
            await MainActor.run {
                AppState.shared.update(
                    isConnected: true,
                    proxySpeedDown: totalProxyDownSpeed,
                    proxySpeedUp: totalProxyUpSpeed,
                    activeConns: activeItems
                )
            }
        } catch {
            print("[TrafficTracker] Poll error: \(error)")
            await MainActor.run {
                AppState.shared.update(
                    isConnected: false,
                    proxySpeedDown: 0,
                    proxySpeedUp: 0,
                    activeConns: []
                )
            }
        }
    }
}
