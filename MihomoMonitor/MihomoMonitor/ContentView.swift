//
//  ContentView.swift
//  MihomoMonitor
//
//  Created by Jo lin on 2026/10/14.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var appState = AppState.shared
    @Namespace private var tabAnimation
    @Namespace private var rangeAnimation
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 16)
                .padding(.top, 14)
            
            navigationSection
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
            
            // Main List Content (Direct Scroll on solid window base)
            contentSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
                .opacity(0.5)
            
            footerSection
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 440, height: 570)
        // 100% Solid macOS Window Base: Completely blocks dark/light backgrounds behind the popover
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - 1. Top Dashboard (Solid Grounded Cards, Zero Background Bleed)
    private var headerSection: some View {
        VStack(spacing: 11) {
            // Status Row
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isConnected ? Color.green : Color.red)
                        .frame(width: 7.5, height: 7.5)
                        .shadow(color: appState.isConnected ? Color.green.opacity(0.5) : Color.red.opacity(0.3), radius: 2)
                    
                    Text(appState.isConnected ? "Mihomo 代理已连接" : "Mihomo 未连接")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                // Fixed-Position Cumulative Proxy Stats (No horizontal jitter, Strictly single-line)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    
                    Text("累计:")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    
                    // Fixed-width download section
                    HStack(spacing: 2) {
                        Text("↓")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.blue.opacity(0.85))
                        Text(FormatUtils.formatBytes(appState.allTimeProxyDownload))
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
                    
                    // Fixed-width upload section
                    HStack(spacing: 2) {
                        Text("↑")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.green.opacity(0.85))
                        Text(FormatUtils.formatBytes(appState.allTimeProxyUpload))
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
            
            // Solid Grounded Metric Cards with Apple Native Rolling Digits
            HStack(spacing: 10) {
                // Download Speed Card
                let downSpeed = FormatUtils.splitSpeed(appState.proxyDownloadSpeed)
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
                        Text("今日走代理")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("↓ \(FormatUtils.formatBytes(appState.todayProxyDownload))")
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
                let upSpeed = FormatUtils.splitSpeed(appState.proxyUploadSpeed)
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
                        Text("今日走代理")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("↑ \(FormatUtils.formatBytes(appState.todayProxyUpload))")
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
    
    // MARK: - 2. Compact Single-Row Navigation Switchers (Identical 28pt Height)
    private var navigationSection: some View {
        VStack(spacing: 6) {
            // One Single Row for Both Switchers with Exactly Matching 28pt Heights
            HStack(alignment: .center, spacing: 8) {
                // Left: Compact Tabs (Height: 28pt)
                HStack(spacing: 2) {
                    ForEach(MonitorTab.allCases) { tab in
                        Button {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                                appState.selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 3.5) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 9.5))
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: appState.selectedTab == tab ? .semibold : .medium))
                            }
                            .padding(.horizontal, 8)
                            .frame(maxHeight: .infinity)
                            .background {
                                if appState.selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.accentColor)
                                        .matchedGeometryEffect(id: "mainTabPill", in: tabAnimation)
                                        .shadow(color: Color.accentColor.opacity(0.3), radius: 3, y: 1)
                                }
                            }
                            .foregroundStyle(appState.selectedTab == tab ? .white : .secondary)
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
                if appState.selectedTab != .active {
                    HStack(spacing: 2) {
                        ForEach(TimeRange.allCases) { range in
                            Button {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    appState.selectedTimeRange = range
                                }
                            } label: {
                                Text(range.rawValue)
                                    .font(.system(size: 10.5, weight: appState.selectedTimeRange == range ? .semibold : .regular))
                                    .padding(.horizontal, 7)
                                    .frame(maxHeight: .infinity)
                                    .background {
                                        if appState.selectedTimeRange == range {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.accentColor.opacity(0.18))
                                                .matchedGeometryEffect(id: "timePill", in: rangeAnimation)
                                        }
                                    }
                                    .foregroundStyle(appState.selectedTimeRange == range ? Color.accentColor : .secondary)
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
            if appState.selectedTab == .domains {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    TextField("搜索域名...", text: $appState.domainSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !appState.domainSearchText.isEmpty {
                        Button {
                            appState.domainSearchText = ""
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
    
    // MARK: - 3. Content Section (Direct Clean Scroll)
    @ViewBuilder
    private var contentSection: some View {
        switch appState.selectedTab {
        case .apps:
            appsListView
        case .domains:
            domainsListView
        case .proxies:
            proxiesListView
        case .active:
            activeConnsListView
        }
    }
    
    // MARK: - 3.1 Apps List View
    private var appsListView: some View {
        Group {
            if appState.topApps.isEmpty {
                emptyView(title: "暂无代理流量", subtitle: "开启科学上网或有软件走代理时自动记录")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(appState.topApps) { item in
                            ModernAppRow(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - 3.2 Domains List View
    private var domainsListView: some View {
        Group {
            let list = appState.filteredDomains
            if list.isEmpty {
                emptyView(title: "无匹配域名记录", subtitle: "通过代理访问的网站将自动聚合在此")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(list) { item in
                            ModernDomainRow(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - 3.3 Proxies List View
    private var proxiesListView: some View {
        Group {
            if appState.topProxies.isEmpty {
                emptyView(title: "暂无节点数据", subtitle: "经由机场节点的流量将在此汇系统计")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(appState.topProxies) { item in
                            ModernProxyRow(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - 3.4 Active Connections View
    private var activeConnsListView: some View {
        Group {
            if appState.activeConnections.isEmpty {
                emptyView(title: "暂无活跃代理连接", subtitle: "当前没有通过代理节点传输的活跃长连接")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(appState.activeConnections) { item in
                            ModernActiveRow(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - Modern Empty State
    private func emptyView(title: String, subtitle: String) -> some View {
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
    
    // MARK: - 4. Minimal Clean Footer
    private var footerSection: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation { appState.refreshStats() }
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

// MARK: - Native Solid macOS App Row Card
struct ModernAppRow: View {
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
                    }
                }
                .frame(height: 4.5)
                
                HStack {
                    Text("占比 \(Int(item.percentage * 100))%")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("↓ \(FormatUtils.formatBytes(item.downloadBytes))   ↑ \(FormatUtils.formatBytes(item.uploadBytes))")
                        .font(.system(size: 9.5, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 3 : 1.5, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Native Solid Domain Row
struct ModernDomainRow: View {
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
            
            if isHovered {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.host, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 10.5))
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
            
            Text(FormatUtils.formatBytes(item.totalBytes))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
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

// MARK: - Native Solid Proxy Node Row
struct ModernProxyRow: View {
    let item: ProxyTrafficStat
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "paperplane.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 16))
                .foregroundStyle(.orange)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 2.5) {
                Text(item.nodeName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                Text("分流占比 \(Int(item.percentage * 100))%  ·  ↓ \(FormatUtils.formatBytes(item.downloadBytes))  ↑ \(FormatUtils.formatBytes(item.uploadBytes))")
                    .font(.system(size: 9.5, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(FormatUtils.formatBytes(item.totalBytes))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
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

// MARK: - Native Solid Active Row
struct ModernActiveRow: View {
    let item: ActiveConnItem
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 9) {
            AppIconBadgeView(appName: item.appName, size: 22)
            
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 6) {
                    Text(item.appName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text(item.host.isEmpty ? item.destinationIP : item.host)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 5) {
                    Text(item.proxyNode)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.orange)
                    Text("·")
                        .foregroundStyle(.tertiary)
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
