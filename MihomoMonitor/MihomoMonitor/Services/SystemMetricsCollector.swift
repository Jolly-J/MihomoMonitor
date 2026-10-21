//
//  SystemMetricsCollector.swift
//  MihomoMonitor
//
//  [架构层级] Services / 系统底层资源采集
//  [核心职责] 基于纯原生 Darwin C API（host_statistics64、libproc、mach_absolute_time、IOKit.ps）周期性采集全核 CPU 负载、物理内存分布、电池状态与 Top 进程算力/内存消耗，零外部子进程开销。
//  [关键类型] SystemMetricsCollector（单例）
//  [依赖关系] 依赖 Darwin、IOKit、AppKit、ProcessResolver、SystemModels
//  [并发安全] 拥有专属 DispatchSourceTimer 与 utility 串行采集队列，采集完成后通过 MainActor 分发更新。
//

import Foundation
import Darwin
import IOKit.ps
import AppKit

final class SystemMetricsCollector: @unchecked Sendable {
    static let shared = SystemMetricsCollector()
    
    private let queue = DispatchQueue(label: "com.mihomomonitor.systemmetrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isRunning = false
    
    // Hardware specs
    private let cpuCores: Int
    private let totalMemoryBytes: Int64
    
    // CPU usage delta tracking (Host level)
    private var previousCpuLoad: host_cpu_load_info?
    
    // CPU usage delta tracking (Process level)
    // pid -> (total_ticks, mach_absolute_time)
    private var previousProcTimes: [pid_t: (ticks: UInt64, machTime: UInt64)] = [:]
    
    private init() {
        // Query CPU cores
        var cores: Int32 = 1
        var coresLen = MemoryLayout<Int32>.size
        if sysctlbyname("hw.ncpu", &cores, &coresLen, nil, 0) != 0 || cores < 1 {
            cores = 1
        }
        self.cpuCores = Int(cores)
        
        // Query Total Physical Memory
        var mem: Int64 = 0
        var memLen = MemoryLayout<Int64>.size
        if sysctlbyname("hw.memsize", &mem, &memLen, nil, 0) != 0 || mem <= 0 {
            mem = 16 * 1024 * 1024 * 1024 // Fallback 16GB
        }
        self.totalMemoryBytes = mem
    }
    
    // MARK: - Lifecycle (Lazy Polling: 0.00% CPU when stopped)
    
    func start() {
        queue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.isRunning = true
            
            // Execute immediate first sample to establish baseline
            self.sampleMetrics()
            
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 1.5, repeating: 1.5)
            t.setEventHandler { [weak self] in
                self?.sampleMetrics()
            }
            t.resume()
            self.timer = t
        }
    }
    
    func stop() {
        queue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.isRunning = false
            self.timer?.cancel()
            self.timer = nil
            self.previousCpuLoad = nil
            self.previousProcTimes.removeAll(keepingCapacity: true)
        }
    }
    
    // MARK: - Sampling Pipeline
    
    private func sampleMetrics() {
        let currentMachTime = mach_absolute_time()
        
        // 1. Host CPU Load
        let totalCpuPercent = sampleHostCpuPercent()
        
        // 2. Host Physical Memory
        let usedMemoryBytes = sampleHostMemoryUsed()
        
        // 3. Battery / Power State
        let powerSnapshot = samplePowerState()
        
        // 4. Running Applications mapping (PID -> NSRunningApplication)
        let runningApps = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, NSRunningApplication)? in
            return (app.processIdentifier, app)
        })
        
        // 5. Query All System PIDs
        let pidsCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard pidsCount > 0 else { return }
        
        var pids = [pid_t](repeating: 0, count: Int(pidsCount))
        let actualBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, pidsCount)
        let count = Int(actualBytes) / MemoryLayout<pid_t>.size
        
        // Temporary per-app aggregation dictionary
        // Key: App identifier or clean display name
        struct AggregatedProcess {
            var name: String
            var appPath: String?
            var cpuPercent: Double
            var memoryBytes: Int64
            var count: Int
        }
        var appMap: [String: AggregatedProcess] = [:]
        
        var currentProcTimes: [pid_t: (ticks: UInt64, machTime: UInt64)] = [:]
        currentProcTimes.reserveCapacity(count)
        
        let cpuCoreCount = Double(self.cpuCores)
        
        for i in 0..<count {
            let pid = pids[i]
            if pid <= 0 { continue }
            
            var taskInfo = proc_taskinfo()
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
            if ret <= 0 { continue }
            
            let currentUser = taskInfo.pti_total_user
            let currentSys = taskInfo.pti_total_system
            let currentTicks = currentUser + currentSys
            currentProcTimes[pid] = (currentTicks, currentMachTime)
            
            // Calculate CPU percent for this PID (Whole Machine Absolute %)
            var pidCpuPercent: Double = 0.0
            if let prev = self.previousProcTimes[pid] {
                let deltaTicks = currentTicks >= prev.ticks ? Double(currentTicks - prev.ticks) : 0.0
                let deltaMach = currentMachTime >= prev.machTime ? Double(currentMachTime - prev.machTime) : 0.0
                
                if deltaMach > 0 {
                    let totalCapacity = deltaMach * cpuCoreCount
                    pidCpuPercent = (deltaTicks / totalCapacity) * 100.0
                }
            }
            
            let memBytes = Int64(taskInfo.pti_resident_size)
            
            // Resolve application display name and bundle path
            let (displayName, bundlePath) = resolveAppIdentity(pid: pid, runningApps: runningApps)
            
            if var existing = appMap[displayName] {
                existing.cpuPercent += pidCpuPercent
                existing.memoryBytes += memBytes
                existing.count += 1
                if existing.appPath == nil && bundlePath != nil {
                    existing.appPath = bundlePath
                }
                appMap[displayName] = existing
            } else {
                appMap[displayName] = AggregatedProcess(
                    name: displayName,
                    appPath: bundlePath,
                    cpuPercent: pidCpuPercent,
                    memoryBytes: memBytes,
                    count: 1
                )
            }
        }
        
        self.previousProcTimes = currentProcTimes
        
        // Transform to final Models
        let allItems: [SystemProcessItem] = appMap.values.map { item in
            SystemProcessItem(
                name: item.name,
                appPath: item.appPath,
                cpuPercent: max(0.0, item.cpuPercent),
                memoryBytes: max(0, item.memoryBytes),
                processCount: item.count
            )
        }
        
        // Top CPU list (Sorted descending by CPU %, top 25)
        let topCpu = allItems
            .filter { $0.cpuPercent >= 0.05 || $0.memoryBytes >= 10 * 1024 * 1024 }
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(25)
        
        // Top Memory list (Sorted descending by Memory bytes, top 25)
        let topMem = allItems
            .filter { $0.memoryBytes >= 5 * 1024 * 1024 }
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(25)
        
        let globalMetrics = SystemGlobalMetrics(
            totalCpuUsage: totalCpuPercent,
            cpuCores: self.cpuCores,
            usedMemoryBytes: usedMemoryBytes,
            totalMemoryBytes: self.totalMemoryBytes,
            isACPower: powerSnapshot.isACPower,
            isCharging: powerSnapshot.isCharging,
            batteryPercentage: powerSnapshot.batteryPercentage,
            timeRemainingMinutes: powerSnapshot.timeRemainingMinutes
        )
        
        Task { @MainActor in
            SystemMonitorViewModel.shared.updateMetrics(
                global: globalMetrics,
                topCpu: Array(topCpu),
                topMemory: Array(topMem)
            )
            AppState.shared.updateSystemMetrics(
                global: globalMetrics,
                topCpu: Array(topCpu),
                topMemory: Array(topMem)
            )
        }
    }
    
    // MARK: - App Identity & Bundle Extraction
    
    private func resolveAppIdentity(
        pid: pid_t,
        runningApps: [pid_t: NSRunningApplication]
    ) -> (name: String, path: String?) {
        // Query full executable path via proc_pidpath first to detect top-level bundle
        var fullPath: String?
        var pathBuf = [CChar](repeating: 0, count: 4096)
        let pathLen = proc_pidpath(pid, &pathBuf, 4096)
        if pathLen > 0 {
            fullPath = String(cString: pathBuf)
        }
        
        let targetPath = fullPath ?? runningApps[pid]?.bundleURL?.path
        
        // 1. Detect if belongs to a top-level .app (like /Applications/WeChat.app or Edge)
        if let path = targetPath, let range = path.range(of: ".app", options: .caseInsensitive) {
            let bundleSubPath = String(path[..<range.upperBound])
            let bundleName = ((bundleSubPath as NSString).lastPathComponent as NSString).deletingPathExtension
            if !bundleName.isEmpty {
                let friendlyName: String
                if bundleName == "WeChat" || bundleName == "WeChatAppEx" {
                    friendlyName = "微信"
                } else {
                    friendlyName = bundleName
                }
                return (friendlyName, bundleSubPath)
            }
        }
        
        // 2. Check NSRunningApplication directly
        if let app = runningApps[pid], let name = app.localizedName, !name.isEmpty {
            return (cleanProcessName(name), app.bundleURL?.path)
        }
        
        // 3. Fallback to path last component
        if let path = fullPath {
            let lastComponent = (path as NSString).lastPathComponent
            if !lastComponent.isEmpty {
                return (cleanProcessName(lastComponent), path)
            }
        }
        
        // 4. Fallback to proc_name
        var nameBuf = [CChar](repeating: 0, count: 256)
        let nameLen = proc_name(pid, &nameBuf, 256)
        if nameLen > 0 {
            let rawName = String(cString: nameBuf)
            if !rawName.isEmpty {
                return (cleanProcessName(rawName), nil)
            }
        }
        
        return ("PID \(pid)", nil)
    }
    
    private func cleanProcessName(_ raw: String) -> String {
        var name = raw
        if name.hasSuffix(" Helper (Renderer)") {
            name = String(name.dropLast(" Helper (Renderer)".count))
        } else if name.hasSuffix(" Helper (GPU)") {
            name = String(name.dropLast(" Helper (GPU)".count))
        } else if name.hasSuffix(" Helper (Plugin)") {
            name = String(name.dropLast(" Helper (Plugin)".count))
        } else if name.hasSuffix(" Helper") {
            name = String(name.dropLast(" Helper".count))
        }
        return name
    }
    
    // MARK: - Host CPU Load
    
    private func sampleHostCpuPercent() -> Double {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        
        let kr = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard kr == KERN_SUCCESS else { return 0.0 }
        
        guard let prev = self.previousCpuLoad else {
            self.previousCpuLoad = cpuLoad
            return 0.0
        }
        
        let userDiff = Double(cpuLoad.cpu_ticks.0 >= prev.cpu_ticks.0 ? cpuLoad.cpu_ticks.0 - prev.cpu_ticks.0 : 0)
        let sysDiff  = Double(cpuLoad.cpu_ticks.1 >= prev.cpu_ticks.1 ? cpuLoad.cpu_ticks.1 - prev.cpu_ticks.1 : 0)
        let idleDiff = Double(cpuLoad.cpu_ticks.2 >= prev.cpu_ticks.2 ? cpuLoad.cpu_ticks.2 - prev.cpu_ticks.2 : 0)
        let niceDiff = Double(cpuLoad.cpu_ticks.3 >= prev.cpu_ticks.3 ? cpuLoad.cpu_ticks.3 - prev.cpu_ticks.3 : 0)
        
        let totalTicks = userDiff + sysDiff + idleDiff + niceDiff
        self.previousCpuLoad = cpuLoad
        
        guard totalTicks > 0 else { return 0.0 }
        let activeTicks = userDiff + sysDiff + niceDiff
        let percent = (activeTicks / totalTicks) * 100.0
        return min(100.0, max(0.0, percent))
    }
    
    // MARK: - Host Physical Memory
    
    private func sampleHostMemoryUsed() -> Int64 {
        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        
        guard kr == KERN_SUCCESS else { return 0 }
        
        let pageSize = UInt64(vm_kernel_page_size)
        // macOS Active + Wire + Compressed Memory
        let activePages = UInt64(vmStats.active_count)
        let wirePages = UInt64(vmStats.wire_count)
        let compressedPages = UInt64(vmStats.compressor_page_count)
        
        let usedBytes = Int64((activePages + wirePages + compressedPages) * pageSize)
        return min(self.totalMemoryBytes, max(0, usedBytes))
    }
    
    // MARK: - Battery & Power State
    
    private struct PowerSnapshot {
        var isACPower: Bool = true
        var isCharging: Bool = false
        var batteryPercentage: Int = 100
        var timeRemainingMinutes: Int? = nil
    }
    
    private func samplePowerState() -> PowerSnapshot {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return PowerSnapshot(isACPower: true, isCharging: false, batteryPercentage: 100, timeRemainingMinutes: nil)
        }
        
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            
            let state = desc[kIOPSPowerSourceStateKey as String] as? String
            let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
            let capacity = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maxCapacity = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let timeToEmpty = desc[kIOPSTimeToEmptyKey as String] as? Int ?? -1
            
            let percent = maxCapacity > 0 ? Int((Double(capacity) / Double(maxCapacity)) * 100) : capacity
            let isAC = (state == (kIOPSACPowerValue as String))
            let minutes = (timeToEmpty > 0 && !isAC) ? timeToEmpty : nil
            
            return PowerSnapshot(
                isACPower: isAC,
                isCharging: isCharging,
                batteryPercentage: min(100, max(0, percent)),
                timeRemainingMinutes: minutes
            )
        }
        
        return PowerSnapshot(isACPower: true, isCharging: false, batteryPercentage: 100, timeRemainingMinutes: nil)
    }
}
