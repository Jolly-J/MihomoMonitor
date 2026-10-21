//
//  SystemNavigationView.swift
//  MihomoMonitor
//
//  [架构层级] Feature / SystemMonitor / Views
//  [核心职责] 系统性能监控模块的子维度导航切换栏，支持在“处理器 CPU”与“内存占用”之间平滑切换。
//  [关键类型] SystemNavigationView
//  [依赖关系] 双向绑定 selectedSubTab，使用 matchedGeometryEffect 提供指示器滑移动效。
//  [并发安全] SwiftUI 视图，主线程渲染。
//

import SwiftUI

struct SystemNavigationView: View {
    @Binding var selectedSubTab: SystemSubTab
    var subTabAnimation: Namespace.ID
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(SystemSubTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                            selectedSubTab = tab
                        }
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 9.5))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: selectedSubTab == tab ? .semibold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .frame(maxHeight: .infinity)
                        .background {
                            if selectedSubTab == tab {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "systemSubTabPill", in: subTabAnimation)
                                    .shadow(color: Color.accentColor.opacity(0.3), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                        .foregroundStyle(selectedSubTab == tab ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2.5)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
            
            Spacer()
            
            Text(selectedSubTab == .cpu ? "按整机绝对算力排序" : "按物理内存大小排序")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }
}
