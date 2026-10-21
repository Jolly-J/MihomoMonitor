//
//  DomainTrafficRow.swift
//  MihomoMonitor
//
//  [架构层级] Feature / ProxyTraffic / Views
//  [核心职责] 单个目标域名流量排行项视图，展示域名地址、上下行流量、请求总连接次数，并支持悬浮与一键复制域名。
//  [关键类型] DomainTrafficRow
//  [依赖关系] 依赖 DomainTrafficStat、FormatUtils
//  [并发安全] SwiftUI 视图，主线程渲染。
//

import SwiftUI
import AppKit

struct DomainTrafficRow: View {
    let item: DomainTrafficStat
    @State private var isHovered = false
    @State private var copied = false
    
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "globe.asia.australia.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15))
                .foregroundStyle(.blue)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 2.5) {
                Text(item.host)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                Text("↓ \(FormatUtils.formatBytes(item.downloadBytes))   ↑ \(FormatUtils.formatBytes(item.uploadBytes))")
                    .font(.system(size: 9.5, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Text(FormatUtils.formatBytes(item.totalBytes))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.host, forType: .string)
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("复制域名")
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
