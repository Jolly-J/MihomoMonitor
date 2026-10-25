//
//  SystemProcessRow.swift
//  MihomoMonitor
//
//  [架构层级] Feature / SystemMonitor / Views
//  [核心职责] 单个进程系统资源消耗行视图，支持在 CPU 模式下显示绝对算力占比或在内存模式下显示物理内存占用量，并配有动态进度条。
//  [关键类型] SystemProcessRow
//  [依赖关系] 依赖 SystemProcessItem、SystemSubTab、SystemAppIconBadgeView、FormatUtils
//  [并发安全] SwiftUI 视图，主线程渲染。
//

import SwiftUI

struct SystemProcessRow: View {
    let item: SystemProcessItem
    let mode: SystemSubTab
    let totalMemory: Int64
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 11) {
            SystemAppIconBadgeView(name: item.name, path: item.appPath, size: 28)
            
            VStack(alignment: .leading, spacing: 4.5) {
                HStack {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    if mode == .cpu {
                        Text(FormatUtils.formatCpuPercent(item.cpuPercent))
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)
                    } else {
                        // 满足用户要求：直接展示 MB 或 GB
                        Text(FormatUtils.formatMemoryMBorGB(item.memoryBytes))
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)
                    }
                }
                
                // Progress Bar with Contrast Track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4.5)
                        
                        let ratio: CGFloat = {
                            if mode == .cpu {
                                return min(1.0, max(0.0, CGFloat(item.cpuPercent / 100.0)))
                            } else {
                                return min(1.0, max(0.0, CGFloat(Double(item.memoryBytes) / Double(max(1, totalMemory)))))
                            }
                        }()
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: mode == .cpu ? [.blue, .cyan] : [.green, .mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4.5, geo.size.width * ratio), height: 4.5)
                            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: ratio)
                    }
                }
                .frame(height: 4.5)
                
                // Sub-info Row
                HStack {
                    Text("\(item.processCount) 个进程")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if mode == .cpu {
                        Text("常驻内存 \(FormatUtils.formatMemoryMBorGB(item.memoryBytes))")
                            .font(.system(size: 9.5, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("CPU \(FormatUtils.formatCpuPercent(item.cpuPercent))")
                            .font(.system(size: 9.5, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
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
