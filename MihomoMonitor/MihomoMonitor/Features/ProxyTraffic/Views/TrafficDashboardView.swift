//
//  TrafficDashboardView.swift
//  MihomoMonitor
//
//  [架构层级] Feature / ProxyTraffic / Views
//  [核心职责] 代理流量模块的核心仪表盘视图，负责展示内核连接状态、实时上下行速率卡片及今日/累计总流量指标。
//  [关键类型] TrafficDashboardView
//  [依赖关系] 纯入参驱动受控视图，依赖 FormatUtils 提供速率与流量格式化。
//  [并发安全] SwiftUI 视图，主线程渲染。
//

import SwiftUI

@MainActor
struct TrafficDashboardView: View {
    let isConnected: Bool
    let allTimeDownload: Int64
    let allTimeUpload: Int64
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let rangeDownload: Int64
    let rangeUpload: Int64
    // 与筛选范围一致的累计标签，以及可悬停查看的连接/落盘错误。
    let rangeLabel: String
    let statusDetail: String
    
    var body: some View {
        VStack(spacing: 11) {
            // Status Row
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 7.5, height: 7.5)
                        .shadow(color: isConnected ? Color.green.opacity(0.5) : Color.red.opacity(0.3), radius: 2)
                    
                    Text(isConnected ? "Mihomo 代理已连接" : "Mihomo 未连接")
                        .help(statusDetail)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                // Fixed-Position Cumulative Proxy Stats
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    
                    Text("累计:")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    
                    HStack(spacing: 2) {
                        Text("↓")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.blue.opacity(0.85))
                        Text(FormatUtils.formatBytes(allTimeDownload))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                    .frame(width: 74, alignment: .leading)
                    
                    Text("·")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.quaternary)
                        .lineLimit(1)
                    
                    HStack(spacing: 2) {
                        Text("↑")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.green.opacity(0.85))
                        Text(FormatUtils.formatBytes(allTimeUpload))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                    .frame(width: 74, alignment: .leading)
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.secondary)
            }
            
            // Speed Cards
            HStack(spacing: 10) {
                // Download Speed Card
                let downSpeed = FormatUtils.splitSpeed(downloadSpeed)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("代理实时下载")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(downSpeed.value)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)
                        
                        Text(downSpeed.unit)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 3) {
                        Text(rangeLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("↓ \(FormatUtils.formatBytes(rangeDownload))")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.blue.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.blue.opacity(0.22), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                )
                
                // Upload Speed Card
                let upSpeed = FormatUtils.splitSpeed(uploadSpeed)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.green)
                        Text("代理实时上传")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(upSpeed.value)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)
                        
                        Text(upSpeed.unit)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 3) {
                        Text(rangeLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("↑ \(FormatUtils.formatBytes(rangeUpload))")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.green.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.green.opacity(0.22), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                )
            }
        }
    }
}
