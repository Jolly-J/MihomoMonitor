//
//  TrafficViewModel.swift
//  MihomoMonitor
//
//  [架构层级] Feature / ProxyTraffic / 业务状态机
//  [核心职责] 管理代理流量界面的所有响应式状态（连接状态、上下行网速、多维排行、时间区间与选中的导航 Tab），协调 DatabaseManager 异步拉取报表。
//  [关键类型] TrafficViewModel（ObservableObject 单例）
//  [依赖关系] 依赖 DatabaseManager、TrafficModels；被 TrafficNavigationView、TrafficDashboardView 引用。
//  [并发安全] 标记为 @MainActor，所有状态变更与 UI 响应均在主线程调度，数据库操作使用后台异步线程。
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class TrafficViewModel: ObservableObject {
    static let shared = TrafficViewModel()
    
    @Published var isConnected: Bool = false
    @Published var proxyDownloadSpeed: Int64 = 0
    @Published var proxyUploadSpeed: Int64 = 0
    
    @Published var todayProxyDownload: Int64 = 0
    @Published var todayProxyUpload: Int64 = 0
    @Published var allTimeProxyDownload: Int64 = 0
    @Published var allTimeProxyUpload: Int64 = 0
    
    @Published var topApps: [AppTrafficStat] = []
    @Published var topDomains: [DomainTrafficStat] = []
    @Published var topProxies: [ProxyTrafficStat] = []
    @Published var activeConnections: [ActiveConnItem] = []
    
    @Published var selectedTab: MonitorTab = .apps
    @Published var selectedTimeRange: TimeRange = .today {
        didSet {
            refreshStats()
        }
    }
    
    @Published var domainSearchText: String = ""
    
    var filteredDomains: [DomainTrafficStat] {
        if domainSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return topDomains
        }
        return topDomains.filter { $0.host.localizedCaseInsensitiveContains(domainSearchText) }
    }
    
    private var statsRefreshCounter = 0
    private var isRefreshing = false
    
    private init() {
        refreshStats()
    }
    
    func update(
        isConnected: Bool,
        proxySpeedDown: Int64,
        proxySpeedUp: Int64,
        activeConns: [ActiveConnItem]
    ) {
        self.isConnected = isConnected
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.proxyDownloadSpeed = proxySpeedDown
            self.proxyUploadSpeed = proxySpeedUp
        }
        self.activeConnections = activeConns
        
        statsRefreshCounter += 1
        if statsRefreshCounter % 2 == 0 {
            refreshStats()
        }
    }
    
    // MARK: - Non-blocking Async Database Refresh
    func refreshStats() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let start = selectedTimeRange.startDate
        
        Task {
            let stats = await DatabaseManager.shared.fetchDashboardStats(startDate: start)
            
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                self.topApps = stats.apps
                self.topDomains = stats.domains
                self.topProxies = stats.proxies
                self.todayProxyUpload = stats.summary.upload
                self.todayProxyDownload = stats.summary.download
                self.allTimeProxyUpload = stats.allTimeSummary.upload
                self.allTimeProxyDownload = stats.allTimeSummary.download
                self.isRefreshing = false
            }
        }
    }
}
