//
//  AppIconProvider.swift
//  MihomoMonitor
//
//  [架构层级] Shared / 资源缓存服务
//  [核心职责] 基于 macOS 系统工作区（NSWorkspace）提取应用原生高精度图标，内置别名映射表与内存图标缓存（NSImage），降低渲染开销。
//  [关键类型] AppIconProvider（单例）
//  [依赖关系] 依赖 AppKit、SwiftUI；供 AppIconBadgeView 与 SystemAppIconBadgeView 共享使用。
//  [并发安全] 内部缓存字典通过 NSLock 实现线程安全保护。
//

import AppKit
import SwiftUI

final class AppIconProvider: @unchecked Sendable {
    static let shared = AppIconProvider()
    
    private let lock = NSLock()
    private var iconCache: [String: NSImage] = [:]
    // 缺失图标缓存一分钟；允许后续安装/启动应用后重新发现，避免永久负缓存。
    private var missingUntil: [String: Date] = [:]
    
    private let knownAliases: [String: [String]] = [
        "VS Code": ["/Applications/Visual Studio Code.app", "Visual Studio Code", "Code"],
        "Microsoft Edge": ["/Applications/Microsoft Edge.app", "Microsoft Edge"],
        "Google Chrome": ["/Applications/Google Chrome.app", "Google Chrome"],
        "DeepSeek": ["/Applications/DeepSeek.app", "DeepSeek"],
        "微信": ["/Applications/WeChat.app", "WeChat"],
        "WPS Office": ["/Applications/wpsoffice.app", "/Applications/WPS Office.app", "wpsoffice", "WPS Office"],
        "Telegram": ["/Applications/Telegram.app", "Telegram"],
        "Safari": ["/Applications/Safari.app", "Safari"],
        "Codex": ["/Applications/Codex.app", "Codex"],
        "Clash Verge": ["/Applications/Clash Verge.app", "Clash Verge"]
    ]
    
    private init() {}
    
    /// 显式路径优先，避免应用名的负缓存挡住后来可用的可执行文件图标。
    func icon(for appName: String, path: String?) -> NSImage? {
        if let path, !path.isEmpty {
            let key = appName + "\u{0}" + path
            lock.lock()
            let cached = iconCache[key]
            let missing = (missingUntil[key] ?? .distantPast) > Date()
            lock.unlock()
            if let cached { return cached }
            if !missing {
                if FileManager.default.fileExists(atPath: path) {
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    saveCache(name: key, icon: icon)
                    return icon
                }
                saveMissing(key)
            }
        }
        return icon(for: appName)
    }

    /// 查询运行应用、别名与 Applications 路径，并缓存缺失结果。
    func icon(for appName: String) -> NSImage? {
        lock.lock()
        if let cached = iconCache[appName] {
            lock.unlock()
            return cached
        }
        if (missingUntil[appName] ?? .distantPast) > Date() {
            lock.unlock()
            return nil
        }
        lock.unlock()

        // 1. Search running applications
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName {
                if name.localizedCaseInsensitiveContains(appName) || appName.localizedCaseInsensitiveContains(name) {
                    if let icon = app.icon {
                        saveCache(name: appName, icon: icon)
                        return icon
                    }
                }
            }
        }
        
        // 2. Check aliases
        if let aliases = knownAliases[appName] {
            for alias in aliases {
                if alias.hasPrefix("/") && FileManager.default.fileExists(atPath: alias) {
                    let icon = NSWorkspace.shared.icon(forFile: alias)
                    saveCache(name: appName, icon: icon)
                    return icon
                }
                for app in NSWorkspace.shared.runningApplications {
                    if let name = app.localizedName, name.localizedCaseInsensitiveContains(alias) {
                        if let icon = app.icon {
                            saveCache(name: appName, icon: icon)
                            return icon
                        }
                    }
                }
            }
        }
        
        // 3. Check /Applications/<appName>.app
        let directPath = "/Applications/\(appName).app"
        if FileManager.default.fileExists(atPath: directPath) {
            let icon = NSWorkspace.shared.icon(forFile: directPath)
            saveCache(name: appName, icon: icon)
            return icon
        }
        
        saveMissing(appName)
        return nil
    }

    /// 有界负缓存，避免历史进程名随长期运行无限累积。
    private func saveMissing(_ key: String) {
        lock.lock()
        if missingUntil.count >= 512 { missingUntil = missingUntil.filter { $0.value > Date() } }
        if missingUntil.count >= 512 { missingUntil.removeAll(keepingCapacity: true) }
        missingUntil[key] = Date().addingTimeInterval(60)
        lock.unlock()
    }

    private func saveCache(name: String, icon: NSImage) {
        lock.lock()
        iconCache[name] = icon
        missingUntil.removeValue(forKey: name)
        lock.unlock()
    }
}
