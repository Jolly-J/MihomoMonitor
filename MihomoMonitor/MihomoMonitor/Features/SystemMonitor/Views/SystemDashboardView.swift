//
//  SystemDashboardView.swift
//  MihomoMonitor
//
//  [架构层级] Feature / SystemMonitor / Views
//  [核心职责] 系统性能监控主仪表盘视图，负责展示全局 CPU 绝对算力利用率、真实物理内存用量卡片、电池状态与活跃进程统计。
//  [关键类型] SystemDashboardView
//  [依赖关系] 接收 SystemGlobalMetrics 模型，依赖 FormatUtils 提供数据格式化。
//  [并发安全] SwiftUI 视图，主线程渲染。
//

import SwiftUI

struct SystemDashboardView: View {
    let metrics: SystemGlobalMetrics
    
    var body: some View {
        VStack(spacing: 11) {
            // Status Row
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: Color.green.opacity(0.5), radius: 2)
                    
                    Text("系统资源监控中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 3) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("\(metrics.cpuCores) 核")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.quaternary)
                    Image(systemName: "memorychip")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(FormatUtils.formatMemoryMBorGB(metrics.totalMemoryBytes))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.secondary)
            }
            
            // Dual Metric Cards (CPU & RAM)
            HStack(spacing: 8) {
                // CPU Load Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4.5) {
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("CPU 总负载")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2.5) {
                        Text(String(format: "%.1f", metrics.totalCpuUsage))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)
                        
                        Text("%")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 2.5) {
                        Text("全核绝对算力 ·")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                        Text(metrics.totalCpuUsage > 75.0 ? "高负荷" : "平稳")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(metrics.totalCpuUsage > 75.0 ? .orange : .blue)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9.5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.blue.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.blue.opacity(0.22), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                )
                
                // Memory Usage Card
                let memSplit = FormatUtils.splitMemoryMBorGB(metrics.usedMemoryBytes)
                let usedPercent = Int(Double(metrics.usedMemoryBytes) / Double(max(1, metrics.totalMemoryBytes)) * 100)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4.5) {
                        Image(systemName: "memorychip.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                        Text("物理内存已用")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2.5) {
                        Text(memSplit.value)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)
                        
                        Text(memSplit.unit)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 2.5) {
                        Text("总量 \(FormatUtils.formatMemoryMBorGB(metrics.totalMemoryBytes)) ·")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                        Text("已用 \(usedPercent)%")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(usedPercent > 85 ? .orange : .green)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9.5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.green.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.green.opacity(0.22), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                )
            }
        }
    }
}
