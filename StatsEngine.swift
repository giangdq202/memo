import Foundation
import MachO
import IOKit
import SystemConfiguration

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

public struct NetworkStats {
    public var uploadBytesPerSec: Double = 0.0
    public var downloadBytesPerSec: Double = 0.0
    public var totalSentBytes: UInt64 = 0
    public var totalRecvBytes: UInt64 = 0
    public var activeInterface: String = "en0"
}

public struct ProcessUsage {
    public let name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64
}

public class StatsEngine {
    // Cached immutable system values (queried once)
    private let hostPort: mach_port_t = mach_host_self()
    private let totalPhysicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    private let cachedPageSize: UInt64
    
    // CPU delta tracking
    private var prevCpuInfo: processor_info_array_t?
    private var prevCpuInfoCount: mach_msg_type_number_t = 0
    
    // Network delta tracking
    private let dynamicStore: SCDynamicStore? = SCDynamicStoreCreate(nil, "MeMo" as CFString, nil, nil)
    private var prevNetBytesSent: UInt64 = 0
    private var prevNetBytesRecv: UInt64 = 0
    private var prevNetTime: CFAbsoluteTime = 0
    private var cachedActiveInterface: String = "en0"
    
    /// Queries SystemConfiguration for the current primary IPv4 network interface.
    private func getPrimaryInterface() -> String {
        if let store = dynamicStore,
           let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
           let primaryInterface = ipv4["PrimaryInterface"] as? String {
            return primaryInterface
        }
        return "en0"
    }
    
    /// Appends a debug message to `/tmp/memo_debug.log` when `--debug` is active.
    private func writeDebugLog(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: "/tmp/memo_debug.log") {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? message.write(toFile: "/tmp/memo_debug.log", atomically: true, encoding: .utf8)
        }
    }
    
    // Active temperature keys grouped by cluster (e.g. CPU, GPU)
    private var activeTempKeys: [String: [String]] = [:]

    public init() {
        var pageSize: vm_size_t = 4096
        host_page_size(hostPort, &pageSize)
        cachedPageSize = UInt64(pageSize)
        
        self.activeTempKeys = scanActiveTempKeys()
    }
    
    private func scanActiveTempKeys() -> [String: [String]] {
        let smc = SMC.shared
        func isActive(_ key: String) -> Bool {
            guard let val = smc.getValue(key) else { return false }
            return val > 15.0 && val < 110.0
        }

        var groups: [String: [String]] = [
            "P-Cores": [],
            "E-Cores": [],
            "GPU": [],
            "Other CPU": []
        ]

        let allTempKeys = smc.getAllTemperatureKeys().filter(isActive)
        
        for key in allTempKeys {
            if key.hasPrefix("Tp") {
                groups["P-Cores"]?.append(key)
            } else if key.hasPrefix("Te") {
                groups["E-Cores"]?.append(key)
            } else if key.hasPrefix("Tg") || key.hasPrefix("TG") {
                groups["GPU"]?.append(key)
            } else if key.hasPrefix("Tc") || key.hasPrefix("Tf") || key.hasPrefix("Tm") || key.hasPrefix("Ts") || key.hasPrefix("Ta") || key.hasPrefix("Th") || key.hasPrefix("Tb") || key.hasPrefix("TC") || key.hasPrefix("TH") || key.hasPrefix("TM") || key.hasPrefix("TP") || key.hasPrefix("TS") || key.hasPrefix("TA") || key.hasPrefix("TB") {
                // To filter out some noise keys that might just be battery / random system sensors, 
                // we can optionally put the rest in "Other CPU" if they look like CPU sensors.
                // For simplicity, any other 'T' key that has a valid reading can go to Other CPU.
                groups["Other CPU"]?.append(key)
            }
        }
        
        // Remove empty groups
        return groups.filter { !$0.value.isEmpty }
    }

    deinit {
        if let prevCpuInfo = prevCpuInfo {
            let prevSize = MemoryLayout<integer_t>.size * Int(prevCpuInfoCount)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevCpuInfo), vm_size_t(prevSize))
        }
    }

    // MARK: - CPU Sampling
    public func fetchCPUStats() -> CPUStats {
        var stats = CPUStats()
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        
        let result = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &cpuInfoCount)
        if result != KERN_SUCCESS {
            if let cpuInfo = cpuInfo {
                let size = MemoryLayout<integer_t>.size * Int(cpuInfoCount)
                if size > 0 {
                    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(size))
                }
            }
            return stats
        }
        guard let cpuInfo = cpuInfo else {
            return stats
        }
        
        stats.coreCount = Int(numCPUs)
        
        if let prevCpuInfo = prevCpuInfo {
            var totalUser: UInt64 = 0
            var totalSystem: UInt64 = 0
            var totalIdle: UInt64 = 0
            var totalNice: UInt64 = 0
            var totalTicks: UInt64 = 0
            
            for i in 0..<Int(numCPUs) {
                let offset = Int(CPU_STATE_MAX) * i
                
                let userDelta = UInt64(max(0, Int64(cpuInfo[offset + Int(CPU_STATE_USER)]) - Int64(prevCpuInfo[offset + Int(CPU_STATE_USER)])))
                let systemDelta = UInt64(max(0, Int64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)]) - Int64(prevCpuInfo[offset + Int(CPU_STATE_SYSTEM)])))
                let idleDelta = UInt64(max(0, Int64(cpuInfo[offset + Int(CPU_STATE_IDLE)]) - Int64(prevCpuInfo[offset + Int(CPU_STATE_IDLE)])))
                let niceDelta = UInt64(max(0, Int64(cpuInfo[offset + Int(CPU_STATE_NICE)]) - Int64(prevCpuInfo[offset + Int(CPU_STATE_NICE)])))
                
                totalUser += userDelta
                totalSystem += systemDelta
                totalIdle += idleDelta
                totalNice += niceDelta
                totalTicks += (userDelta + systemDelta + idleDelta + niceDelta)
            }
            
            if totalTicks > 0 {
                let totalActive = totalUser + totalSystem + totalNice
                stats.usagePercent = (Double(totalActive) / Double(totalTicks)) * 100.0
                stats.userPercent = (Double(totalUser) / Double(totalTicks)) * 100.0
                stats.systemPercent = (Double(totalSystem) / Double(totalTicks)) * 100.0
                stats.idlePercent = (Double(totalIdle) / Double(totalTicks)) * 100.0
            }
            
            let prevSize = MemoryLayout<integer_t>.size * Int(prevCpuInfoCount)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevCpuInfo), vm_size_t(prevSize))
        }
        
        self.prevCpuInfo = cpuInfo
        self.prevCpuInfoCount = cpuInfoCount
        
        // Calculate CPU average temperature and cluster temperatures
        if !activeTempKeys.isEmpty {
            let clusterOrder = ["P-Cores", "E-Cores", "GPU", "Other CPU"]
            var coreSum: Double = 0.0
            var coreCount = 0
            var fallbackSum: Double = 0.0
            var fallbackCount = 0
            let smc = SMC.shared
            
            for groupName in clusterOrder {
                guard let keys = activeTempKeys[groupName] else { continue }
                var groupSum: Double = 0.0
                var groupCount = 0
                for key in keys {
                    if let val = smc.getValue(key), val > 15.0 && val < 110.0 {
                        groupSum += val
                        groupCount += 1
                        if groupName == "P-Cores" || groupName == "E-Cores" {
                            coreSum += val
                            coreCount += 1
                        } else if groupName == "Other CPU" {
                            fallbackSum += val
                            fallbackCount += 1
                        }
                    }
                }
                if groupCount > 0 {
                    stats.tempClusters.append(TempCluster(name: groupName, temperature: groupSum / Double(groupCount)))
                }
            }
            
            if coreCount > 0 {
                stats.temperature = coreSum / Double(coreCount)
            } else if fallbackCount > 0 {
                stats.temperature = fallbackSum / Double(fallbackCount)
            }
        }
        
        if isDebugMode {
            let log = "[DEBUG CPU] Usage: \(String(format: "%.1f", stats.usagePercent))% | Cores: \(stats.coreCount) | Temp: \(String(format: "%.1f", stats.temperature))°C | Clusters: \(stats.tempClusters.count)\n"
            writeDebugLog(log)
        }
        
        return stats
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
        
        var pressureLevel: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0) == 0 {
            stats.pressureLevel = Int(pressureLevel)
        }
        
        if isDebugMode {
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

    // MARK: - Network Sampling
    public func fetchNetworkStats() -> NetworkStats {
        var stats = NetworkStats()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return stats
        }
        defer { freeifaddrs(ifaddr) }
        
        var currentBytesSent: UInt64 = 0
        var currentBytesRecv: UInt64 = 0
        
        let primaryInterface = getPrimaryInterface()
        let interfaceChanged = (primaryInterface != cachedActiveInterface)
        if interfaceChanged {
            cachedActiveInterface = primaryInterface
        }
        
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let curr = ptr {
            let flags = Int32(curr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            
            if isUp && isRunning && !isLoopback,
               let addr = curr.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let namePtr = curr.pointee.ifa_name,
               strcmp(namePtr, primaryInterface) == 0,
               let data = curr.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self)
                currentBytesRecv += UInt64(ifData.pointee.ifi_ibytes)
                currentBytesSent += UInt64(ifData.pointee.ifi_obytes)
            }
            ptr = curr.pointee.ifa_next
        }
        
        stats.totalSentBytes = currentBytesSent
        stats.totalRecvBytes = currentBytesRecv
        stats.activeInterface = cachedActiveInterface
        
        let now = CFAbsoluteTimeGetCurrent()
        if prevNetTime > 0 && !interfaceChanged {
            let dt = now - prevNetTime
            if dt > 0 {
                // When the total drops (e.g. an interface disconnected and its
                // counters reset), treat the delta as zero rather than assuming a
                // UInt32 wrap — counters are summed across interfaces, so the old
                // wrap formula doesn't apply. The next sample will be correct.
                let sentDelta = currentBytesSent >= prevNetBytesSent
                    ? currentBytesSent - prevNetBytesSent : 0
                let recvDelta = currentBytesRecv >= prevNetBytesRecv
                    ? currentBytesRecv - prevNetBytesRecv : 0
                
                stats.uploadBytesPerSec = Double(sentDelta) / dt
                stats.downloadBytesPerSec = Double(recvDelta) / dt
                
                // Spike filter: drop impossibly large speeds (e.g. > 100 Gbps or 12.5 GB/s)
                let maxReasonable: Double = 12_500_000_000
                if stats.uploadBytesPerSec > maxReasonable { stats.uploadBytesPerSec = 0 }
                if stats.downloadBytesPerSec > maxReasonable { stats.downloadBytesPerSec = 0 }
            }
        }
        
        self.prevNetBytesSent = currentBytesSent
        self.prevNetBytesRecv = currentBytesRecv
        self.prevNetTime = now

        if isDebugMode {
            let log = "[DEBUG NET] Interface: \(stats.activeInterface) | Up: \(String(format: "%.0f", stats.uploadBytesPerSec)) B/s | Down: \(String(format: "%.0f", stats.downloadBytesPerSec)) B/s\n"
            writeDebugLog(log)
        }

        return stats
    }

    // MARK: - Per-Process Sampling
    /// Returns per-application resource usage, ranked by CPU and by memory.
    /// Only the current user's processes are included, which naturally
    /// excludes root/system daemons (kernel_task, WindowServer, mds, …).
    /// Helper processes are rolled up into their parent `.app` bundle so a
    /// browser's many renderers appear as a single application.
    ///
    /// `ps` reports an instantaneous %CPU (the kernel's decaying average), so
    /// no second sample is needed. This is only called on menu open, so the
    /// one-off subprocess cost never touches the periodic update path.
    public func fetchTopProcesses(limit: Int) -> (byCPU: [ProcessUsage], byMemory: [ProcessUsage]) {
        let currentUID = getuid()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -a: all users  -x: include processes with no controlling tty (GUI apps).
        // `comm` (full executable path) must be last since it can contain spaces.
        task.arguments = ["-axo", "pcpu=,rss=,uid=,comm="]
        task.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        guard (try? task.run()) != nil else { return ([], []) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return ([], []) }

        // Exclude our own app from the ranking.
        let selfName = Bundle.main.infoDictionary?["CFBundleName"] as? String

        var byName: [String: ProcessUsage] = [:]
        for line in output.split(separator: "\n") {
            guard let (cpu, rssKB, uid, comm) = Self.parseProcessLine(line) else { continue }
            guard uid == currentUID else { continue }
            let name = Self.appName(fromPath: comm)
            guard !name.isEmpty, name != selfName else { continue }

            if var existing = byName[name] {
                existing.cpuPercent += cpu
                existing.memoryBytes += rssKB * 1024
                byName[name] = existing
            } else {
                byName[name] = ProcessUsage(name: name, cpuPercent: cpu, memoryBytes: rssKB * 1024)
            }
        }

        let all = Array(byName.values)
        let byCPU = all.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit)
        let byMemory = all.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit)
        return (Array(byCPU), Array(byMemory))
    }

    /// Parses one `ps` line: three leading numeric columns (pcpu, rss, uid)
    /// followed by the command path, which may itself contain spaces.
    private static func parseProcessLine(_ line: Substring) -> (cpu: Double, rssKB: UInt64, uid: uid_t, comm: String)? {
        var idx = line.startIndex
        func skipSpaces() { while idx < line.endIndex, line[idx] == " " { idx = line.index(after: idx) } }
        func nextToken() -> Substring? {
            skipSpaces()
            guard idx < line.endIndex else { return nil }
            let start = idx
            while idx < line.endIndex, line[idx] != " " { idx = line.index(after: idx) }
            return line[start..<idx]
        }

        guard let t1 = nextToken(), let cpu = Double(t1),
              let t2 = nextToken(), let rss = UInt64(t2),
              let t3 = nextToken(), let uid = UInt32(t3) else { return nil }
        skipSpaces()
        guard idx < line.endIndex else { return nil }
        return (cpu, rss, uid_t(uid), String(line[idx...]))
    }

    /// Derives a friendly application name from an executable path. Prefers the
    /// top-level `.app` bundle name (so helpers roll up into their parent app);
    /// otherwise falls back to the executable's file name.
    private static func appName(fromPath path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        for comp in components where comp.hasSuffix(".app") {
            return String(comp.dropLast(4))
        }
        return components.last.map(String.init) ?? ""
    }
}
