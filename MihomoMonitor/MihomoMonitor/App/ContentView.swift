//
//  ContentView.swift
//  MihomoMonitor
//
//  [架构层级] App / 主面板容器视图
//  [核心职责] 应用主窗口顶级容器，渲染顶部模式切换器（代理流量 / 系统监控），承载各 Feature 侧边栏与仪表盘，以及底部状态栏与退出控制。
//  [关键类型] ContentView
//  [依赖关系] 依赖 AppState、TrafficViewModel、SystemMonitorViewModel、TrafficDashboardView、SystemDashboardView
//  [并发安全] SwiftUI 视图运行于主线程环境。
//

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var trafficVM = TrafficViewModel.shared
    @ObservedObject var systemVM = SystemMonitorViewModel.shared
    
    @Namespace private var modeAnimation
    @Namespace private var trafficTabAnimation
    @Namespace private var trafficRangeAnimation
    @Namespace private var systemSubTabAnimation
    
    var body: some View {
        VStack(spacing: 0) {
            // 0. Top Mode Switcher (Proxy Traffic vs System Monitor)
            modeSwitchSection
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            
            if appState.mainMode == .proxy {
                // 1. Proxy Traffic Feature
                TrafficDashboardView(
                    isConnected: trafficVM.isConnected,
                    allTimeDownload: trafficVM.allTimeProxyDownload,
                    allTimeUpload: trafficVM.allTimeProxyUpload,
                    downloadSpeed: trafficVM.proxyDownloadSpeed,
                    uploadSpeed: trafficVM.proxyUploadSpeed,
                    todayDownload: trafficVM.todayProxyDownload,
                    todayUpload: trafficVM.todayProxyUpload
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                TrafficNavigationView(
                    selectedTab: $trafficVM.selectedTab,
                    selectedTimeRange: $trafficVM.selectedTimeRange,
                    domainSearchText: $trafficVM.domainSearchText,
                    tabAnimation: trafficTabAnimation,
                    rangeAnimation: trafficRangeAnimation
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                
                proxyContentSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 2. System Monitor Feature
                SystemDashboardView(metrics: systemVM.systemMetrics)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                SystemNavigationView(
                    selectedSubTab: $systemVM.selectedSubTab,
                    subTabAnimation: systemSubTabAnimation
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                
                systemContentSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
                .opacity(0.5)
            
            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 440, height: 570)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if appState.mainMode == .system {
                systemVM.start()
            }
        }
        .onDisappear {
            systemVM.stop()
        }
    }
    
    // MARK: - 0. Top Mode Switcher
    private var modeSwitchSection: some View {
        HStack(spacing: 4) {
            ForEach(MainViewMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                        appState.mainMode = mode
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 11, weight: .medium))
                        Text(mode.rawValue)
                            .font(.system(size: 11.5, weight: appState.mainMode == mode ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if appState.mainMode == mode {
                            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                .fill(Color.accentColor)
                                .matchedGeometryEffect(id: "mainModePill", in: modeAnimation)
                                .shadow(color: Color.accentColor.opacity(0.28), radius: 3, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                    .foregroundStyle(appState.mainMode == mode ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .frame(height: 33)
        .background(
            RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - 1. Proxy Content Section
    @ViewBuilder
    private var proxyContentSection: some View {
        switch trafficVM.selectedTab {
        case .apps:
            if trafficVM.topApps.isEmpty {
                emptyState(title: "暂无代理流量", subtitle: "开启科学上网或有软件走代理时自动记录")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(trafficVM.topApps) { item in
                            AppTrafficRow(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        case .domains:
            let list = trafficVM.filteredDomains
            if list.isEmpty {
                emptyState(title: "无匹配域名记录", subtitle: "通过代理访问的网站将自动聚合在此")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(list) { item in
                            DomainTrafficRow(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        case .proxies:
            if trafficVM.topProxies.isEmpty {
                emptyState(title: "暂无节点数据", subtitle: "经由机场节点的流量将在此汇系统计")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(trafficVM.topProxies) { item in
                            ProxyTrafficRow(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        case .active:
            if trafficVM.activeConnections.isEmpty {
                emptyState(title: "暂无活跃代理连接", subtitle: "当前没有通过代理节点传输的活跃长连接")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(trafficVM.activeConnections) { item in
                            ActiveConnectionRow(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - 2. System Content Section
    @ViewBuilder
    private var systemContentSection: some View {
        let list = systemVM.currentList
        
        Group {
            if list.isEmpty {
                emptyState(title: "正在采集系统指标...", subtitle: "正在通过 Darwin 内核轻量读取各应用数据")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(list) { item in
                            SystemProcessRow(
                                item: item,
                                mode: systemVM.selectedSubTab,
                                totalMemory: systemVM.systemMetrics.totalMemoryBytes
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: list.map(\.id))
                }
            }
        }
    }
    
    // MARK: - 3. Clean Empty View
    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 4. Minimal Footer
    private var footerSection: some View {
        HStack(spacing: 8) {
            if appState.mainMode == .proxy {
                Button {
                    trafficVM.refreshStats()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("刷新统计")
                
                Text("仅统计代理流量 · 本地 SQLite 持久化")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text(FormatUtils.formatBatteryStatus(
                    isACPower: systemVM.systemMetrics.isACPower,
                    isCharging: systemVM.systemMetrics.isCharging,
                    batteryPercentage: systemVM.systemMetrics.batteryPercentage,
                    timeRemainingMinutes: systemVM.systemMetrics.timeRemainingMinutes
                ))
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("退出应用") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}
