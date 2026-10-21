//
//  ProxyTrafficRow.swift
//  MihomoMonitor
//
//  [架构层级] Feature / ProxyTraffic / Views
//  [核心职责] 单个代理出站节点排行项视图，展示节点名称（或 Direct 策略）、出站流量消耗及动态占比条。
//  [关键类型] ProxyTrafficRow
//  [依赖关系] 依赖 ProxyTrafficStat、FormatUtils
//  [并发安全] SwiftUI 视图，主线程渲染。
//

import SwiftUI

struct ProxyTrafficRow: View {
    let item: ProxyTrafficStat
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14))
                .foregroundStyle(.purple)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.nodeName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text(FormatUtils.formatBytes(item.totalBytes))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                
                // Progress Bar with Contrast Track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * CGFloat(item.percentage)), height: 4)
                            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: item.percentage)
                    }
                }
                .frame(height: 4)
                
                Text("分流占比 \(Int(item.percentage * 100))%  ·  ↓ \(FormatUtils.formatBytes(item.downloadBytes))  ↑ \(FormatUtils.formatBytes(item.uploadBytes))")
                    .font(.system(size: 9.5, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8.5)
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
