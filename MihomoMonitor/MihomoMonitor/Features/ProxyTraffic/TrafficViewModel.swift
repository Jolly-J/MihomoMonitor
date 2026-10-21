//
//  TrafficViewModel.swift
//  MihomoMonitor
//
//  [架构层级] Feature / ProxyTraffic / 业务状态机
//  [核心职责] 管理展示状态；按可见性、数据变更和筛选变化合并后台查询，拒绝过时结果。
//  [关键类型] TrafficViewModel
//  [依赖关系] DatabaseManager、TrafficModels；供代理流量视图使用。
//  [并发安全] @MainActor；同一时间只有一个查询，使用请求代次确认结果。
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class TrafficViewModel: ObservableObject {
    static let shared = TrafficViewModel()

    @Published var isConnected = false
    @Published var proxyDownloadSpeed: Int64 = 0
    @Published var proxyUploadSpeed: Int64 = 0
    // 网络和落盘错误分开保留，避免网络恢复掩盖保存失败。
    @Published private(set) var connectionError: String?
    @Published private(set) var persistenceError: String?
    @Published private(set) var rangeProxyDownload: Int64 = 0
    @Published private(set) var rangeProxyUpload: Int64 = 0
    @Published private(set) var allTimeProxyDownload: Int64 = 0
    @Published private(set) var allTimeProxyUpload: Int64 = 0
    @Published private(set) var topApps: [AppTrafficStat] = []
    @Published private(set) var topDomains: [DomainTrafficStat] = []
    @Published private(set) var topProxies: [ProxyTrafficStat] = []
    @Published var activeConnections: [ActiveConnItem] = []
    @Published var selectedTab: MonitorTab = .apps
    @Published var selectedTimeRange: TimeRange = .today {
        didSet { if oldValue != selectedTimeRange { invalidateFilters() } }
    }
    // 搜索先使旧结果失效，等待 250ms 稳定输入后才发起数据库查询。
    @Published var domainSearchText = "" {
        didSet {
            guard oldValue != domainSearchText else { return }
            generation += 1
            dirty = true
            topDomains = []
            searchDebounce?.cancel()
            searchDebounce = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self else { return }
                self.searchDebounce = nil
                self.startRefreshIfNeeded()
            }
        }
    }

    // 标签和数字一起清空/提交，筛选切换期间不会用新标签显示旧范围数字。
    var rangeSummaryLabel: String { "\(selectedTimeRange.rawValue)走代理" }
    var statusDetail: String { persistenceError.map { "保存失败：\($0)" } ?? connectionError ?? "已连接 Mihomo" }

    private let loadStats: (Date, String) async -> DashboardStats
    private var isVisible = false
    private var dirty = true
    private var generation: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var searchDebounce: Task<Void, Never>?
    private var displayedDay = Calendar.current.startOfDay(for: Date())

    /// 注入查询闭包可使用受控延迟验证快速切换，无需真实流量文件。
    init(loadStats: @escaping (Date, String) async -> DashboardStats = {
        await DatabaseManager.shared.fetchDashboardStats(startDate: $0, domainSearch: $1)
    }) {
        self.loadStats = loadStats
    }

    /// 展示查询只在代理面板实际可见时执行，后台采集不受影响。
    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        generation += 1
        if visible {
            dirty = true
            startRefreshIfNeeded()
        }
    }

    /// 采样仅更新实时数据；午夜即使没有新流量也要使“今天”范围过期。
    func update(isConnected: Bool, proxySpeedDown: Int64, proxySpeedUp: Int64,
                activeConns: [ActiveConnItem], connectionError: String? = nil) {
        self.isConnected = isConnected
        self.connectionError = connectionError
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            proxyDownloadSpeed = proxySpeedDown
            proxyUploadSpeed = proxySpeedUp
        }
        activeConnections = activeConns
        let day = Calendar.current.startOfDay(for: Date())
        if day != displayedDay {
            displayedDay = day
            invalidateFilters()
        }
    }

    /// 仅成功产生新字节时触发报表刷新；写入错误仍立即展示。
    func persistenceDidFinish(changed: Bool, error: String?) {
        persistenceError = error
        if changed { refreshStats() }
    }

    /// 手动刷新、持久化变更均合并到最新待执行请求。
    func refreshStats() {
        generation += 1
        dirty = true
        startRefreshIfNeeded()
    }

    /// 清除属于旧范围的列表和卡片，保持筛选与展示语义一致。
    private func invalidateFilters() {
        topApps = []
        topDomains = []
        topProxies = []
        rangeProxyUpload = 0
        rangeProxyDownload = 0
        refreshStats()
    }

    /// 同一查询执行期间的新请求留下 dirty 标记；旧结果不得覆盖最新筛选。
    private func startRefreshIfNeeded() {
        guard isVisible, dirty, refreshTask == nil, searchDebounce == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while self.isVisible && self.dirty && self.searchDebounce == nil {
                self.dirty = false
                let requestGeneration = self.generation
                let range = self.selectedTimeRange
                let search = self.domainSearchText
                let stats = await self.loadStats(range.startDate, search)
                guard self.isVisible, requestGeneration == self.generation else { continue }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    self.topApps = stats.apps
                    self.topDomains = stats.domains
                    self.topProxies = stats.proxies
                    self.rangeProxyUpload = stats.summary.upload
                    self.rangeProxyDownload = stats.summary.download
                    self.allTimeProxyUpload = stats.allTimeSummary.upload
                    self.allTimeProxyDownload = stats.allTimeSummary.download
                }
            }
            self.refreshTask = nil
            self.startRefreshIfNeeded()
        }
    }
}
