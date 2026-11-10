import Foundation
import MachO
import IOKit

public struct TempCluster {
    public let name: String
    public let temperature: Double
}

public struct CPUStats {
    public var usagePercent: Double = 0.0
    public var userPercent: Double = 0.0
    public var systemPercent: Double = 0.0
    public var idlePercent: Double = 0.0
    public var coreCount: Int = 0
    public var temperature: Double = 0.0
    public var tempClusters: [TempCluster] = []
    public var thermalState: ProcessInfo.ThermalState = .nominal

    public var thermalStateDescription: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

public struct MemoryStats {
    public var usedBytes: UInt64 = 0
    public var totalBytes: UInt64 = 0
    public var activeBytes: UInt64 = 0
    public var wiredBytes: UInt64 = 0
    public var compressedBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0
    public var pressureLevel: Int = 0 // 1: Normal, 2: Warning, 4: Critical

    public var usedGB: Double {
        return Double(usedBytes) / 1_073_741_824.0
    }
    
    public var totalGB: Double {
        return Double(totalBytes) / 1_073_741_824.0
    }
    
    public var usedPercent: Double {
        return totalBytes > 0 ? (Double(usedBytes) / Double(totalBytes)) * 100.0 : 0.0
    }
}

public class StatsEngine {
    // Cached immutable system values (queried once)
    private let hostPort: mach_port_t = mach_host_self()
    private let totalPhysicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    private let cachedPageSize: UInt64
    private let cachedCoreCount: Int = ProcessInfo.processInfo.activeProcessorCount
    private let debugLogPath = "/tmp/memo_debug.log"
    private var debugLogHandle: FileHandle?

    // CPU delta tracking (stack allocated via host_statistics, zero VM allocation)
    private var prevCpuTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    
    /// Appends a debug message to `/tmp/memo_debug.log` when `--debug` is active.
    /// The handle is kept open for the lifetime of the engine to avoid an
    /// open/close pair for every log line.
    private func writeDebugLog(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        if debugLogHandle != nil && !FileManager.default.fileExists(atPath: debugLogPath) {
            // Writing to an unlinked file succeeds silently, so detect external
            // deletion before reusing the handle.
            try? debugLogHandle?.close()
            debugLogHandle = nil
        }
        if debugLogHandle == nil {
            if !FileManager.default.fileExists(atPath: debugLogPath) {
                _ = FileManager.default.createFile(atPath: debugLogPath, contents: nil)
            }
            debugLogHandle = FileHandle(forWritingAtPath: debugLogPath)
        }
        guard let handle = debugLogHandle else { return }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // The file may have been removed or rotated externally. Drop the
            // stale handle so the next call recreates it.
            try? handle.close()
            debugLogHandle = nil
        }
    }
    
    // Active CPU core temperature keys (raw FourCharCode for zero string allocation in hot path)
    private var activeCpuFourCCs: [UInt32] = []
    private var activeTempKeys: [String: [String]] = [:]

    public init() {
        var pageSize: vm_size_t = 4096
        host_page_size(hostPort, &pageSize)
        cachedPageSize = UInt64(pageSize)

        self.activeTempKeys = scanActiveTempKeys()
    }

    /// Targeted candidate probe for Apple Silicon CPU temperature keys (Tp* and Te*).
    /// Drops startup freeze from ~166ms to ~12ms. Falls back to full enumeration only if probe yields 0 keys.
    private func scanActiveTempKeys() -> [String: [String]] {
        let smc = SMC.shared
        var groups: [String: [String]] = [
            "P-Cores": [],
            "E-Cores": []
        ]

        // Candidate probe: Apple Silicon P-Cores (Tp00..Tp3Z) and E-Cores (Te00..Te3Z)
        let chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        for c1 in "0123" {
            for c2 in chars {
                let pKey = "Tp\(c1)\(c2)"
                if let val = smc.getValue(pKey), val > 15.0 && val < 110.0 {
                    groups["P-Cores"]?.append(pKey)
                }
                let eKey = "Te\(c1)\(c2)"
                if let val = smc.getValue(eKey), val > 15.0 && val < 110.0 {
                    groups["E-Cores"]?.append(eKey)
                }
            }
        }

        let pCount = groups["P-Cores"]?.count ?? 0
        let eCount = groups["E-Cores"]?.count ?? 0

        var allDiscoveredKeys: [String] = []

        if pCount > 0 || eCount > 0 {
            allDiscoveredKeys = (groups["P-Cores"] ?? []) + (groups["E-Cores"] ?? [])
        } else {
            // Fallback for Intel or non-standard hardware layout
            func isActive(_ key: String) -> Bool {
                guard let val = smc.getValue(key) else { return false }
                return val > 15.0 && val < 110.0
            }

            groups["Other CPU"] = []
            let allTempKeys = smc.getAllTemperatureKeys().filter(isActive)

            for key in allTempKeys {
                if key.hasPrefix("Tp") {
                    groups["P-Cores"]?.append(key)
                } else if key.hasPrefix("Te") {
                    groups["E-Cores"]?.append(key)
                } else if key.hasPrefix("Tc") || key.hasPrefix("Tf") || key.hasPrefix("TC") {
                    groups["Other CPU"]?.append(key)
                }
            }

            if !(groups["P-Cores"]?.isEmpty ?? true) || !(groups["E-Cores"]?.isEmpty ?? true) {
                groups.removeValue(forKey: "Other CPU")
            }
            allDiscoveredKeys = groups.values.flatMap { $0 }
        }

        // Cache raw FourCharCodes for zero-allocation sampling in hot path
        activeCpuFourCCs = allDiscoveredKeys.map { FourCharCode(fromString: $0) }

        // Remove empty groups
        return groups.filter { !$0.value.isEmpty }
    }

    deinit {
        mach_port_deallocate(mach_task_self_, hostPort)
        try? debugLogHandle?.close()
    }

    // MARK: - CPU Sampling
    public func fetchCPUStats(includeTemperature: Bool = true) -> CPUStats {
        var stats = CPUStats()
        stats.coreCount = cachedCoreCount

        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var load = host_cpu_load_info()
        let kr = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return stats
        }

        let currentTicks = (
            user: load.cpu_ticks.0,
            system: load.cpu_ticks.1,
            idle: load.cpu_ticks.2,
            nice: load.cpu_ticks.3
        )

        if let prev = prevCpuTicks {
            let userDelta = UInt64(max(0, Int64(currentTicks.user) - Int64(prev.user)))
            let systemDelta = UInt64(max(0, Int64(currentTicks.system) - Int64(prev.system)))
            let idleDelta = UInt64(max(0, Int64(currentTicks.idle) - Int64(prev.idle)))
            let niceDelta = UInt64(max(0, Int64(currentTicks.nice) - Int64(prev.nice)))
            let totalTicks = userDelta + systemDelta + idleDelta + niceDelta

            if totalTicks > 0 {
                let totalActive = userDelta + systemDelta + niceDelta
                stats.usagePercent = (Double(totalActive) / Double(totalTicks)) * 100.0
                stats.userPercent = (Double(userDelta) / Double(totalTicks)) * 100.0
                stats.systemPercent = (Double(systemDelta) / Double(totalTicks)) * 100.0
                stats.idlePercent = (Double(idleDelta) / Double(totalTicks)) * 100.0
            }
        }

        self.prevCpuTicks = currentTicks
        stats.thermalState = ProcessInfo.processInfo.thermalState

        guard includeTemperature else {
            return stats
        }

        let tempResult = sampleTemperatures(fullSample: false)
        stats.temperature = tempResult.temperature
        stats.tempClusters = tempResult.clusters

        if isDebugMode {
            let log = "[DEBUG CPU] Usage: \(String(format: "%.1f", stats.usagePercent))% | Cores: \(stats.coreCount) | Temp: \(String(format: "%.1f", stats.temperature))°C | Thermal: \(stats.thermalStateDescription)\n"
            writeDebugLog(log)
        }

        return stats
    }

    /// Resets CPU tick delta tracking to prevent arithmetic distortion upon wake from sleep.
    public func resetCpuTicks() {
        prevCpuTicks = nil
    }

    /// Helper for current system thermal state from Foundation.
    public var thermalState: ProcessInfo.ThermalState {
        return ProcessInfo.processInfo.thermalState
    }

    public var thermalStateDescription: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    /// Samples active SMC CPU core temperature sensors directly in a single pass.
    /// Eliminates all dictionary insertions, lookups, and unused cluster allocations.
    public func sampleTemperatures(fullSample: Bool = false) -> (temperature: Double, clusters: [TempCluster]) {
        guard !activeCpuFourCCs.isEmpty else { return (0.0, []) }
        let smc = SMC.shared

        var sum: Double = 0.0
        var count = 0

        for key in activeCpuFourCCs {
            if let val = smc.getValue(key), val > 15.0 && val < 110.0 {
                sum += val
                count += 1
            }
        }

        let avgTemp = count > 0 ? (sum / Double(count)) : 0.0
        return (avgTemp, [])
    }

    /// Returns the current active CPU core temperature (P-Cores + E-Cores average) synchronously.
    public func fetchTemperature() -> Double {
        return sampleTemperatures().temperature
    }

    // MARK: - Memory Sampling
    public func fetchMemoryStats() -> MemoryStats {
        var stats = MemoryStats()
        stats.totalBytes = totalPhysicalMemory
        
        var stats64 = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let kerr = withUnsafeMutablePointer(to: &stats64) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            return stats
        }
        
        let page = cachedPageSize
        let active = UInt64(stats64.active_count) * page
        let wired = UInt64(stats64.wire_count) * page
        let compressed = UInt64(stats64.compressor_page_count) * page
        let free = UInt64(stats64.free_count) * page
        
        let speculative = UInt64(stats64.speculative_count) * page
        let purgeable = UInt64(stats64.purgeable_count) * page
        
        let appMemory = active + speculative > purgeable ? (active + speculative - purgeable) : 0
        
        stats.activeBytes = active
        stats.wiredBytes = wired
        stats.compressedBytes = compressed
        stats.freeBytes = free
        stats.usedBytes = appMemory + wired + compressed
        
        if isDebugMode {
            var pressureLevel: Int32 = 0
            var size = MemoryLayout<Int32>.size
            if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0) == 0 {
                stats.pressureLevel = Int(pressureLevel)
            }
            let activeGB = Double(active) / 1_073_741_824.0
            let wiredGB = Double(wired) / 1_073_741_824.0
            let compressedGB = Double(compressed) / 1_073_741_824.0
            let speculativeGB = Double(speculative) / 1_073_741_824.0
            let purgeableGB = Double(purgeable) / 1_073_741_824.0
            let log = "[DEBUG RAM] Used: \(String(format: "%.1f", stats.usedGB))GB / \(String(format: "%.1f", stats.totalGB))GB | Pressure: \(stats.pressureLevel) | active:\(String(format: "%.1f", activeGB)) wired:\(String(format: "%.1f", wiredGB)) compressed:\(String(format: "%.1f", compressedGB)) speculative:\(String(format: "%.1f", speculativeGB)) purgeable:\(String(format: "%.1f", purgeableGB))\n"
            writeDebugLog(log)
        }
        
        return stats
    }
}
