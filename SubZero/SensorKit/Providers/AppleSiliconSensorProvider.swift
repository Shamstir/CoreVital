import Foundation

public final class AppleSiliconSensorProvider: SensorProvider {
    private let smc = SMCConnection.shared
    private let metricsHelper = SystemMetricsHelper.shared
    private let ioReport = IOReportHelper.shared
    private var pCoreCount: Int = 0
    private var eCoreCount: Int = 0
    
    public init() {
        detectCoreTopology()
    }
    
    private func detectCoreTopology() {
        var pCores: Int = 0
        var size = MemoryLayout<Int>.stride
        if sysctlbyname("hw.perflevel0.physicalcpu", &pCores, &size, nil, 0) == 0 && pCores > 0 {
            self.pCoreCount = pCores
        }
        
        var eCores: Int = 0
        size = MemoryLayout<Int>.stride
        if sysctlbyname("hw.perflevel1.physicalcpu", &eCores, &size, nil, 0) == 0 && eCores > 0 {
            self.eCoreCount = eCores
        }
        
        // Fallback if sysctl topology wasn't available
        if pCoreCount == 0 {
            self.pCoreCount = ProcessInfo.processInfo.activeProcessorCount
        }
    }
    
    public func cpuTemperature() -> Double? {
        if let hidTemp = HIDSensorHelper.shared.readTemperatures().cpu {
            return hidTemp
        }
        
        // Fallback to SMC keys if HID sensor wasn't available
        let cpuKeys = [
            "Tp09", "Tp0L", "Tp01", "Tp05", "Tp0D", "Tp0E", "Tp0F", "Tp0G", "Tp0H",
            "Tp0b", "Tp0c", "Tp0d", "Te05", "Te0L", "Te01", "Te04", "Te0D", "Te0E",
            "Te0b", "Te0c", "Te0d", "Th0H"
        ]
        
        var validReadings: [Double] = []
        for key in cpuKeys {
            if let val = smc.readDouble(key), val > 15 && val < 130 {
                validReadings.append(val)
            }
        }
        
        guard !validReadings.isEmpty else { return nil }
        return validReadings.reduce(0.0, +) / Double(validReadings.count)
    }
    
    public func gpuTemperature() -> Double? {
        if let hidTemp = HIDSensorHelper.shared.readTemperatures().gpu {
            return hidTemp
        }
        
        let gpuKeys = [
            "TG0B", "TG0D", "TG0V", "TG0b", "TG0c", "TG0d", "Tg05", "Tg0D", "Tg0L"
        ]
        
        var validReadings: [Double] = []
        for key in gpuKeys {
            if let val = smc.readDouble(key), val > 15 && val < 130 {
                validReadings.append(val)
            }
        }
        
        guard !validReadings.isEmpty else { return nil }
        return validReadings.reduce(0.0, +) / Double(validReadings.count)
    }
    
    public func fanSpeeds() -> [FanReading] {
        // Read-only fan speeds via AppleSMC.
        // On M-series Macs without fans (MacBook Air), this returns an empty array gracefully.
        return smc.readFanSpeeds()
    }
    
    public func batteryInfo() -> BatteryInfo {
        return metricsHelper.getBatteryInfo()
    }
    
    public func cpuLoad() -> CPULoad {
        return metricsHelper.getCPULoad(pCoreCount: pCoreCount, eCoreCount: eCoreCount)
    }
    
    public func memoryStats() -> MemoryStats {
        return metricsHelper.getMemoryStats()
    }
    
    public func diskIO() -> DiskIOStats {
        return metricsHelper.getDiskIO()
    }
    
    public func networkThroughput() -> NetworkStats {
        return metricsHelper.getNetworkThroughput()
    }
    
    public func powerDraw() -> PowerReadings? {
        return ioReport.samplePowerReadings()
    }
    
    public func thermalState() -> ProcessInfo.ThermalState {
        return ProcessInfo.processInfo.thermalState
    }
}
