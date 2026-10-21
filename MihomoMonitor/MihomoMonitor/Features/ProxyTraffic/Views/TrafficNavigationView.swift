//
//  TrafficNavigationView.swift
//  MihomoMonitor
//
//  [架构层级] Feature / ProxyTraffic / Views
//  [核心职责] 代理流量模块的导航选择器组件，提供应用/域名/代理/连接明细切换标签与时间范围（今天/近7天/全部）单行紧凑切换栏。
//  [关键类型] TrafficNavigationView
//  [依赖关系] 双向绑定 selectedTab、selectedTimeRange、domainSearchText；使用 matchedGeometryEffect 提供指示器滑移动画。
//  [并发安全] SwiftUI 视图，运行于主线程环境。
//

import SwiftUI

struct TrafficNavigationView: View {
    @Binding var selectedTab: MonitorTab
    @Binding var selectedTimeRange: TimeRange
    @Binding var domainSearchText: String
    var tabAnimation: Namespace.ID
    var rangeAnimation: Namespace.ID
    
    var body: some View {
        VStack(spacing: 6) {
            // One Single Row for Both Switchers with Exactly Matching 28pt Heights
            HStack(alignment: .center, spacing: 8) {
                // Left: Compact Tabs (Height: 28pt)
                HStack(spacing: 2) {
                    ForEach(MonitorTab.allCases) { tab in
                        Button {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 3.5) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 9.5))
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                            }
                            .padding(.horizontal, 8)
                            .frame(maxHeight: .infinity)
                            .background {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.accentColor)
                                        .matchedGeometryEffect(id: "mainTabPill", in: tabAnimation)
                                        .shadow(color: Color.accentColor.opacity(0.3), radius: 3, y: 1)
                                }
                            }
                            .contentShape(Rectangle())
                            .foregroundStyle(selectedTab == tab ? .white : .secondary)
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
                
                // Right: Compact Time Filter Pills (Height: Exactly 28pt)
                if selectedTab != .active {
                    HStack(spacing: 2) {
                        ForEach(TimeRange.allCases) { range in
                            Button {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    selectedTimeRange = range
                                }
                            } label: {
                                Text(range.rawValue)
                                    .font(.system(size: 10.5, weight: selectedTimeRange == range ? .semibold : .regular))
                                    .padding(.horizontal, 7)
                                    .frame(maxHeight: .infinity)
                                    .background {
                                        if selectedTimeRange == range {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.accentColor.opacity(0.18))
                                                .matchedGeometryEffect(id: "timePill", in: rangeAnimation)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .foregroundStyle(selectedTimeRange == range ? Color.accentColor : .secondary)
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
                }
            }
            
            // Domain search bar (only on domains tab)
            if selectedTab == .domains {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    TextField("搜索域名...", text: $domainSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !domainSearchText.isEmpty {
                        Button {
                            domainSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )
            }
        }
    }
}
