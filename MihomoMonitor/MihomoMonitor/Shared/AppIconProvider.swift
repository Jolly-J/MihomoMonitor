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
    
    func icon(for appName: String, path: String? = nil) -> NSImage? {
        lock.lock()
        if let cached = iconCache[appName] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        if let path = path, !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            saveCache(name: appName, icon: icon)
            return icon
        }
        
        return icon(for: appName)
    }
    
    func icon(for appName: String) -> NSImage? {
        lock.lock()
        if let cached = iconCache[appName] {
            lock.unlock()
            return cached
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
        
        return nil
    }
    
    private func saveCache(name: String, icon: NSImage) {
        lock.lock()
        iconCache[name] = icon
        lock.unlock()
    }
}
