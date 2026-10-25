//
//  AppTrafficRow.swift
//  MihomoMonitor
//
//  [架构层级] Feature / ProxyTraffic / Views
//  [核心职责] 单个应用程序流量排行项视图，展示 App 原生图标、名称、上下行流量明细及总用量动态占比进度条。
//  [关键类型] AppTrafficRow
//  [依赖关系] 依赖 AppTrafficStat 模型、AppIconBadgeView、FormatUtils
//  [并发安全] SwiftUI 视图，主线程渲染。
//

import SwiftUI

struct AppTrafficRow: View {
    let item: AppTrafficStat
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 11) {
            AppIconBadgeView(appName: item.appName, size: 28)
            
            VStack(alignment: .leading, spacing: 4.5) {
                HStack {
                    Text(item.appName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text(FormatUtils.formatBytes(item.totalBytes))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                
                // Progress Bar with Contrast Track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4.5)
                        
                        Capsule()
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4.5, geo.size.width * CGFloat(item.percentage)), height: 4.5)
                            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: item.percentage)
                    }
                }
                .frame(height: 4.5)
                
                HStack {
                    Text("占比 \(Int(item.percentage * 100))%")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("↓ \(FormatUtils.formatBytes(item.downloadBytes))  ↑ \(FormatUtils.formatBytes(item.uploadBytes))")
                        .font(.system(size: 9.5, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
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
