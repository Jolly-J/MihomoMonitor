//
//  AppState.swift
//  MihomoMonitor
//
//  Created by Jo lin on 2026/10/14.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
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
    
    func refreshStats() {
        let start = selectedTimeRange.startDate
        let apps = DatabaseManager.shared.getTopApps(startDate: start, limit: 50)
        let domains = DatabaseManager.shared.getTopDomains(startDate: start, limit: 50)
        let proxies = DatabaseManager.shared.getTopProxies(startDate: start, limit: 50)
        let todaySummary = DatabaseManager.shared.getSummary(startDate: TimeRange.today.startDate)
        let allTimeSummary = DatabaseManager.shared.getSummary(startDate: TimeRange.all.startDate)
        
        self.topApps = apps
        self.topDomains = domains
        self.topProxies = proxies
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.todayProxyUpload = todaySummary.upload
            self.todayProxyDownload = todaySummary.download
            self.allTimeProxyUpload = allTimeSummary.upload
            self.allTimeProxyDownload = allTimeSummary.download
        }
    }
}
