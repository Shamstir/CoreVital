import Foundation

public protocol SensorProvider: AnyObject {
    func cpuTemperature() -> Double?
    func gpuTemperature() -> Double?
    func fanSpeeds() -> [FanReading]
    func batteryInfo() -> BatteryInfo
    func cpuLoad() -> CPULoad
    func memoryStats() -> MemoryStats
    func diskIO() -> DiskIOStats
    func networkThroughput() -> NetworkStats
    func powerDraw() -> PowerReadings?
    func thermalState() -> ProcessInfo.ThermalState
}
