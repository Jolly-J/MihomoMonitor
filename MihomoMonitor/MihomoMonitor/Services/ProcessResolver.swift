//
//  ProcessResolver.swift
//  MihomoMonitor
//
//  [架构层级] Services / 进程标识解析器
//  [核心职责] 将网络连接的进程源信息或 PID / 路径解析为 macOS 友好应用展示名称与 Bundle ID，内置锁保护的内存缓存加速解析。
//  [关键类型] ProcessResolver（单例）
//  [依赖关系] 依赖 Foundation、AppKit
//  [并发安全] 内部状态受 NSLock 互斥锁保护，保证跨线程并发访问安全。
//

import Foundation
import AppKit

nonisolated final class ProcessResolver: @unchecked Sendable {
    static let shared = ProcessResolver()
    
    private let lock = NSLock()
    private var connectionProcessCache: [String: String] = [:]
    private var portToProcessMap: [String: String] = [:]
    private var lastLsofTime: Date = Date.distantPast
    
    private init() {}
    
    func resolveProcess(for conn: MihomoRawConnection) -> String {
        let connId = conn.id
        
        lock.lock()
        if let cached = connectionProcessCache[connId] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        // 1. Check if Mihomo itself supplied process or processPath
        if let proc = conn.metadata.process, !proc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clean = cleanProcessName(proc)
            lock.lock()
            connectionProcessCache[connId] = clean
            lock.unlock()
            return clean
        }
        
        if let path = conn.metadata.processPath, !path.isEmpty {
            let name = (path as NSString).lastPathComponent
            let clean = cleanProcessName(name)
            lock.lock()
            connectionProcessCache[connId] = clean
            lock.unlock()
            return clean
        }
        
        // 2. Fallback: match via local sourcePort (System Proxy mode)
        if let sourcePort = conn.metadata.sourcePort, !sourcePort.isEmpty {
            lock.lock()
            if let matched = portToProcessMap[sourcePort] {
                connectionProcessCache[connId] = matched
                lock.unlock()
                return matched
            }
            let shouldRefresh = Date().timeIntervalSince(lastLsofTime) > 2.0
            lock.unlock()
            
            if shouldRefresh {
                refreshPortMap()
                lock.lock()
                if let matched = portToProcessMap[sourcePort] {
                    connectionProcessCache[connId] = matched
                    lock.unlock()
                    return matched
                }
                lock.unlock()
            }
        }
        
        // Default fallback if undetermined
        let fallback = "系统/其他"
        lock.lock()
        connectionProcessCache[connId] = fallback
        lock.unlock()
        return fallback
    }
    
    func forgetConnection(_ connId: String) {
        lock.lock()
        connectionProcessCache.removeValue(forKey: connId)
        lock.unlock()
    }
    
    private func refreshPortMap() {
        lock.lock()
        lastLsofTime = Date()
        lock.unlock()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP:7897", "-sTCP:ESTABLISHED", "-F", "p", "-F", "c", "-F", "n", "-n", "-P"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if let output = String(data: data, encoding: .utf8) {
                parseLsofOutput(output)
            }
        } catch {
            // Silently fallback if lsof fails
        }
    }
    
    private func parseLsofOutput(_ output: String) {
        var currentCommand = ""
        var newPortMap: [String: String] = [:]
        
        for line in output.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            let prefix = line.first!
            let value = String(line.dropFirst())
            
            switch prefix {
            case "c":
                currentCommand = cleanProcessName(value)
            case "n":
                // Format: 127.0.0.1:59666->127.0.0.1:7897
                if let arrowIndex = value.range(of: "->") {
                    let localPart = String(value[..<arrowIndex.lowerBound])
                    if let colonIndex = localPart.lastIndex(of: ":") {
                        let port = String(localPart[localPart.index(after: colonIndex)...])
                        if !currentCommand.isEmpty {
                            newPortMap[port] = currentCommand
                        }
                    }
                }
            default:
                break
            }
        }
        
        lock.lock()
        for (k, v) in newPortMap {
            self.portToProcessMap[k] = v
        }
        lock.unlock()
    }
    
    func cleanProcessName(_ raw: String) -> String {
        var name = raw
        if name.hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        
        // Clean common helper suffixes
        if name.contains("Microsoft Edge") { return "Microsoft Edge" }
        if name.contains("Google Chrome") { return "Google Chrome" }
        if name.contains("Code Helper") || name == "Code" { return "VS Code" }
        if name.contains("DeepSeek") { return "DeepSeek" }
        if name.contains("Telegram") { return "Telegram" }
        if name.contains("WeChat") || name.contains("微信") { return "微信" }
        if name.contains("Safari") { return "Safari" }
        if name.contains("wps") || name.contains("WPS") { return "WPS Office" }
        if name.contains("codex") { return "Codex" }
        if name.contains("language_server") { return "Language Server" }
        if name.contains("VideoFusion") { return "VideoFusion" }
        if name.contains("clash-verge") { return "Clash Verge" }
        if name.contains("curl") { return "curl" }
        if name.contains("git") { return "git" }
        
        return name
    }
}
