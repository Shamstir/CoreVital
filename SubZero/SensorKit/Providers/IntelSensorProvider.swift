import Foundation

public final class IntelSensorProvider: SensorProvider {
    private let smc = SMCConnection.shared
    private let metricsHelper = SystemMetricsHelper.shared
    
    public init() {}
    
    public func cpuTemperature() -> Double? {
        // Try common Intel CPU thermal keys in priority order
        let keys = ["TC0P", "TC0D", "TC0E", "TC0F", "TC1C", "Th0H"]
        for key in keys {
            if let temp = smc.readDouble(key), temp > 0 && temp < 150 {
                return temp
            }
        }
        return nil
    }
    
    public func gpuTemperature() -> Double? {
        // Try common Intel/Discrete GPU thermal keys
        let keys = ["TG0D", "TG0P", "TG0H", "TG1D"]
        for key in keys {
            if let temp = smc.readDouble(key), temp > 0 && temp < 150 {
                return temp
            }
        }
        return nil
    }
    
    public func fanSpeeds() -> [FanReading] {
        return smc.readFanSpeeds()
    }
    
    public func batteryInfo() -> BatteryInfo {
        return metricsHelper.getBatteryInfo()
    }
    
    public func cpuLoad() -> CPULoad {
        return metricsHelper.getCPULoad()
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
        let cpuWatts = smc.readDouble("PCPC") ?? smc.readDouble("PCPT")
        let gpuWatts = smc.readDouble("PGPC") ?? smc.readDouble("PGTR")
        let totalWatts = smc.readDouble("PSTR") ?? smc.readDouble("PDTR")
        
        if cpuWatts == nil && gpuWatts == nil && totalWatts == nil {
            return nil
        }
        
        return PowerReadings(
            cpuWatts: cpuWatts,
            gpuWatts: gpuWatts,
            totalPackageWatts: totalWatts
        )
    }
    
    public func thermalState() -> ProcessInfo.ThermalState {
        return ProcessInfo.processInfo.thermalState
    }
}
