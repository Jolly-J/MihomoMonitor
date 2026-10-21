//
//  AppIconBadgeView.swift
//  MihomoMonitor
//
//  [架构层级] Shared / Components / UI 组件
//  [核心职责] 代理流量模块通用的应用图标渲染组件，支持传入应用名称自动检索原生图标，无图标时优雅降级为 SF Symbols 符号徽章。
//  [关键类型] AppIconBadgeView
//  [依赖关系] 依赖 SwiftUI、AppKit、AppIconProvider
//  [并发安全] SwiftUI 视图，主线程渲染。
//

import SwiftUI
import AppKit

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
