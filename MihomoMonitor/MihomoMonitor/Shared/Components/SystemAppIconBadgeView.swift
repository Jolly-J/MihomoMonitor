//
//  SystemAppIconBadgeView.swift
//  MihomoMonitor
//
//  [架构层级] Shared / Components / UI 组件
//  [核心职责] 系统性能监控专用的进程图标展示视图，结合进程名与可执行文件完整路径检索 macOS 原生应用图标并提供一致的占位底色。
//  [关键类型] SystemAppIconBadgeView
//  [依赖关系] 依赖 SwiftUI、AppKit、AppIconProvider
//  [并发安全] SwiftUI 视图，主线程渲染。
//

import SwiftUI
import AppKit

struct SystemAppIconBadgeView: View {
    let name: String
    let path: String?
    let size: CGFloat
    
    var body: some View {
        Group {
            if let nsImage = AppIconProvider.shared.icon(for: name, path: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                    Image(systemName: "app.fill")
                        .font(.system(size: size * 0.55))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
