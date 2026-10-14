//
//  AppIconProvider.swift
//  MihomoMonitor
//
//  Created by Jo lin on 2026/10/14.
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

// MARK: - SwiftUI App Icon View
struct AppIconBadgeView: View {
    let appName: String
    let size: CGFloat
    
    init(appName: String, size: CGFloat = 26) {
        self.appName = appName
        self.size = size
    }
    
    var body: some View {
        if let nsImage = AppIconProvider.shared.icon(for: appName) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .cornerRadius(5)
        } else {
            // Elegant SF Symbol fallback - NO letters!
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(fallbackBackgroundColor)
                    .frame(width: size, height: size)
                Image(systemName: fallbackSymbolName)
                    .font(.system(size: size * 0.52, weight: .medium))
                    .foregroundColor(fallbackForegroundColor)
            }
        }
    }
    
    private var isCommandLine: Bool {
        let lower = appName.lowercased()
        return lower == "curl" || lower == "git" || lower == "python" || lower == "python3" ||
               lower == "node" || lower == "zsh" || lower == "bash" || lower == "ssh" ||
               lower == "brew" || lower.contains("language_server") || lower.contains("helper")
    }
    
    private var fallbackSymbolName: String {
        if isCommandLine {
            return "terminal.fill"
        } else if appName == "系统/其他" {
            return "network"
        } else {
            return "app.fill"
        }
    }
    
    private var fallbackBackgroundColor: Color {
        if isCommandLine {
            return Color.black.opacity(0.12)
        } else if appName == "系统/其他" {
            return Color.blue.opacity(0.12)
        } else {
            return Color.secondary.opacity(0.15)
        }
    }
    
    private var fallbackForegroundColor: Color {
        if isCommandLine {
            return Color.primary.opacity(0.7)
        } else if appName == "系统/其他" {
            return Color.blue
        } else {
            return Color.secondary
        }
    }
}
