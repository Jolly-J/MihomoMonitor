//
//  ActiveConnectionRow.swift
//  MihomoMonitor
//
//  [架构层级] Feature / ProxyTraffic / Views
//  [核心职责] 单个实时活动连接项视图，展示发起进程、目标地址、代理链节点路由、实时传输速度及已传输字节量。
//  [关键类型] ActiveConnectionRow
//  [依赖关系] 依赖 ActiveConnItem、AppIconBadgeView、FormatUtils
//  [并发安全] SwiftUI 视图，主线程渲染。
//

import SwiftUI

struct ActiveConnectionRow: View {
    let item: ActiveConnItem
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 9) {
            AppIconBadgeView(appName: item.appName, size: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.appName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("→ \(item.host)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 6) {
                    Text(item.proxyNode)
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.12))
                        .foregroundStyle(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    
                    Text("已传输: ↓ \(FormatUtils.formatBytes(item.downloadTotal))  ↑ \(FormatUtils.formatBytes(item.uploadTotal))")
                        .font(.system(size: 9.5, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if item.downloadSpeed > 0 {
                    Text("↓ \(FormatUtils.formatSpeed(item.downloadSpeed))")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                }
                if item.uploadSpeed > 0 {
                    Text("↑ \(FormatUtils.formatSpeed(item.uploadSpeed))")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }
                if item.downloadSpeed == 0 && item.uploadSpeed == 0 {
                    Text("空闲")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(7.5)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 3 : 1.5, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
