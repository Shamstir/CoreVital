import Foundation
import IOKit
import IOKit.ps
import SystemConfiguration

public final class SystemMetricsHelper {
    public static let shared = SystemMetricsHelper()
    
    private var previousCPUInfo: processor_info_array_t?
    private var previousCPUMsgCount: mach_msg_type_number_t = 0
    private let host = mach_host_self()
    private let lock = NSLock()
    
    private var lastDiskReadBytes: UInt64 = 0
    private var lastDiskWriteBytes: UInt64 = 0
    private var lastDiskTimestamp: Date?
    
    private var lastNetRxBytes: UInt64 = 0
    private var lastNetTxBytes: UInt64 = 0
    private var lastNetTimestamp: Date?
    
    private init() {}
    
    // MARK: - CPU Load
    public func getCPULoad(pCoreCount: Int? = nil, eCoreCount: Int? = nil) -> CPULoad {
        lock.lock()
        defer { lock.unlock() }
        
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        
        let err = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCPUInfo)
        guard err == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return CPULoad()
        }
        
        var perCoreLoads: [Double] = []
        var totalUser: Int32 = 0
        var totalSystem: Int32 = 0
        var totalIdle: Int32 = 0
        
        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let user = cpuInfo[offset + Int(CPU_STATE_USER)]
            let system = cpuInfo[offset + Int(CPU_STATE_SYSTEM)]
            let nice = cpuInfo[offset + Int(CPU_STATE_NICE)]
            let idle = cpuInfo[offset + Int(CPU_STATE_IDLE)]
            
            var coreLoad: Double = 0.0
            if let prev = previousCPUInfo, previousCPUMsgCount == numCPUInfo {
                let prevUser = prev[offset + Int(CPU_STATE_USER)]
                let prevSystem = prev[offset + Int(CPU_STATE_SYSTEM)]
                let prevNice = prev[offset + Int(CPU_STATE_NICE)]
                let prevIdle = prev[offset + Int(CPU_STATE_IDLE)]
                
                let deltaActive = (user - prevUser) + (system - prevSystem) + (nice - prevNice)
                let deltaTotal = deltaActive + (idle - prevIdle)
                
                if deltaTotal > 0 {
                    coreLoad = (Double(deltaActive) / Double(deltaTotal)) * 100.0
                }
            }
            perCoreLoads.append(max(0.0, min(100.0, coreLoad)))
            totalUser += user
            totalSystem += system
            totalIdle += idle
        }
        
        // Deallocate previous
        if let prev = previousCPUInfo {
            let prevSize = vm_size_t(previousCPUMsgCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), prevSize)
        }
        previousCPUInfo = cpuInfo
        previousCPUMsgCount = numCPUInfo
        
        let totalLoad: Double
        if !perCoreLoads.isEmpty {
            totalLoad = perCoreLoads.reduce(0.0, +) / Double(perCoreLoads.count)
        } else {
            totalLoad = 0.0
        }
        
        var pLoad: Double?
        var eLoad: Double?
        
        if let pCount = pCoreCount, let eCount = eCoreCount, (pCount + eCount) == perCoreLoads.count {
            let pCores = perCoreLoads.prefix(pCount)
            let eCores = perCoreLoads.suffix(eCount)
            pLoad = pCores.reduce(0.0, +) / Double(max(1, pCount))
            eLoad = eCores.reduce(0.0, +) / Double(max(1, eCount))
        } else if let pCount = pCoreCount, pCount > 0, pCount <= perCoreLoads.count {
            let pCores = perCoreLoads.prefix(pCount)
            let eCores = perCoreLoads.suffix(perCoreLoads.count - pCount)
            pLoad = pCores.reduce(0.0, +) / Double(max(1, pCount))
            if !eCores.isEmpty {
                eLoad = eCores.reduce(0.0, +) / Double(eCores.count)
            }
        }
        
        return CPULoad(
            totalLoad: totalLoad,
            pCoreLoad: pLoad,
            eCoreLoad: eLoad,
            perCoreLoads: perCoreLoads,
            pCoreCount: pCoreCount ?? Int(numCPUs),
            eCoreCount: eCoreCount ?? 0
        )
    }
    
    // MARK: - Memory Stats
    public func getMemoryStats() -> MemoryStats {
        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        
        let err = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard err == KERN_SUCCESS else {
            return MemoryStats()
        }
        
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let wired = UInt64(vmStats.wire_count) * UInt64(pageSize)
        let active = UInt64(vmStats.active_count) * UInt64(pageSize)
        let compressed = UInt64(vmStats.compressor_page_count) * UInt64(pageSize)
        
        let usedBytes = wired + active + compressed
        
        // Get Swap
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let swapErr = sysctlbyname("vm.swapusage", &xsw, &size, nil, 0)
        let swapUsed = (swapErr == 0) ? UInt64(xsw.xsu_used) : 0
        
        // Pressure
        let pressure = min(100.0, max(0.0, (Double(usedBytes) / Double(max(1, totalBytes))) * 100.0))
        
        return MemoryStats(
            usedBytes: usedBytes,
            totalBytes: totalBytes,
            swapUsedBytes: swapUsed,
            pressurePercentage: pressure
        )
    }
    
    // MARK: - Battery Info
    public func getBatteryInfo() -> BatteryInfo {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] ?? []
        
        if sources.isEmpty {
            // No battery present
            return BatteryInfo(isPresent: false)
        }
        
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            
            let isPresent = desc[kIOPSIsPresentKey] as? Bool ?? true
            if !isPresent { continue }
            
            let currentCap = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let powerSourceState = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            let isPluggedIn = (powerSourceState == kIOPSACPowerValue)
            
            let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int
            let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int
            let timeRemaining = isCharging ? timeToFull : (timeToEmpty != -1 ? timeToEmpty : nil)
            
            let chargePct = min(100.0, max(0.0, (Double(currentCap) / Double(max(1, maxCap))) * 100.0))
            
            // Try to read advanced properties from AppleSmartBattery
            var cycleCount: Int?
            var voltage: Double?
            var amperage: Double?
            var wattage: Double?
            var temp: Double?
            var healthPct: Double?
            
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    
                    if let cycles = dict["CycleCount"] as? Int {
                        cycleCount = cycles
                    }
                    if let mv = dict["Voltage"] as? Int {
                        voltage = Double(mv) / 1000.0
                    }
                    if let ma = dict["Amperage"] as? Int {
                        amperage = Double(ma) / 1000.0
                    }
                    if let v = voltage, let a = amperage {
                        wattage = abs(v * a)
                    }
                    if let t = dict["Temperature"] as? Int {
                        // Temperature is reported in deca-kelvins (tenths of a Kelvin)
                        temp = (Double(t) / 10.0) - 273.15
                    }
                    if let designCap = dict["DesignCapacity"] as? Int, designCap > 0,
                       let maxCapacity = dict["MaxCapacity"] as? Int {
                        healthPct = min(100.0, max(0.0, (Double(maxCapacity) / Double(designCap)) * 100.0))
                    }
                }
                IOObjectRelease(service)
            }
            
            if temp == nil {
                temp = HIDSensorHelper.shared.readTemperatures().battery
            }
            
            return BatteryInfo(
                isPresent: true,
                chargePercentage: chargePct,
                healthPercentage: healthPct,
                cycleCount: cycleCount,
                voltage: voltage,
                amperage: amperage,
                wattage: wattage,
                timeRemainingMinutes: timeRemaining,
                temperature: temp,
                isCharging: isCharging,
                isPluggedIn: isPluggedIn
            )
        }
        
        return BatteryInfo(isPresent: false)
    }
    
    // MARK: - Disk IO
    public func getDiskIO() -> DiskIOStats {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        
        let matching = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = props?.takeRetainedValue() as? [String: Any],
                   let stats = dict["Statistics"] as? [String: Any] {
                    
                    if let read = stats["Bytes (Read)"] as? UInt64 {
                        totalRead += read
                    }
                    if let write = stats["Bytes (Write)"] as? UInt64 {
                        totalWrite += write
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        var readRate: Double = 0.0
        var writeRate: Double = 0.0
        
        if let timestamp = lastDiskTimestamp {
            let elapsed = now.timeIntervalSince(timestamp)
            if elapsed > 0 && totalRead >= lastDiskReadBytes && totalWrite >= lastDiskWriteBytes {
                readRate = Double(totalRead - lastDiskReadBytes) / elapsed
                writeRate = Double(totalWrite - lastDiskWriteBytes) / elapsed
            }
        }
        
        lastDiskReadBytes = totalRead
        lastDiskWriteBytes = totalWrite
        lastDiskTimestamp = now
        
        return DiskIOStats(readBytesPerSec: readRate, writeBytesPerSec: writeRate)
    }
    
    // MARK: - Network Throughput
    public func getNetworkThroughput() -> NetworkStats {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return NetworkStats()
        }
        
        var ptr = firstAddr
        while true {
            let name = String(cString: ptr.pointee.ifa_name)
            if !name.hasPrefix("lo") && ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                if let data = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    totalRx += UInt64(data.pointee.ifi_ibytes)
                    totalTx += UInt64(data.pointee.ifi_obytes)
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        freeifaddrs(ifaddr)
        
        var rxRate: Double = 0.0
        var txRate: Double = 0.0
        
        if let timestamp = lastNetTimestamp {
            let elapsed = now.timeIntervalSince(timestamp)
            if elapsed > 0 && totalRx >= lastNetRxBytes && totalTx >= lastNetTxBytes {
                rxRate = Double(totalRx - lastNetRxBytes) / elapsed
                txRate = Double(totalTx - lastNetTxBytes) / elapsed
            }
        }
        
        lastNetRxBytes = totalRx
        lastNetTxBytes = totalTx
        lastNetTimestamp = now
        
        return NetworkStats(downloadBytesPerSec: rxRate, uploadBytesPerSec: txRate)
    }
}
