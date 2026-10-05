import Foundation
import Combine

@MainActor
public final class SensorManager: ObservableObject {
    public static let shared = SensorManager()
    
    private var provider: SensorProvider
    private var timer: Timer?
    
    @Published public private(set) var cpuTemp: Double?
    @Published public private(set) var gpuTemp: Double?
    @Published public private(set) var fanSpeeds: [FanReading] = []
    @Published public private(set) var batteryInfo: BatteryInfo = BatteryInfo()
    @Published public private(set) var cpuLoad: CPULoad = CPULoad()
    @Published public private(set) var memoryStats: MemoryStats = MemoryStats()
    @Published public private(set) var diskIO: DiskIOStats = DiskIOStats()
    @Published public private(set) var networkStats: NetworkStats = NetworkStats()
    @Published public private(set) var powerReadings: PowerReadings?
    @Published public private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published public private(set) var chipName: String = ""
    @Published public private(set) var isAppleSilicon: Bool = false
    
    public var currentRefreshInterval: TimeInterval = 2.0 {
        didSet {
            if oldValue != currentRefreshInterval {
                startPolling(interval: currentRefreshInterval)
            }
        }
    }
    
    private init() {
        var isArm = false
        var arm64Val: Int = 0
        var size = MemoryLayout<Int>.stride
        if sysctlbyname("hw.optional.arm64", &arm64Val, &size, nil, 0) == 0 && arm64Val == 1 {
            isArm = true
        }
        
        // Detect chip brand string
        var brandBuffer = [CChar](repeating: 0, count: 256)
        var brandSize = brandBuffer.count
        var brandName = "Mac"
        if sysctlbyname("machdep.cpu.brand_string", &brandBuffer, &brandSize, nil, 0) == 0 {
            brandName = String(cString: brandBuffer)
        }
        
        self.isAppleSilicon = isArm
        self.chipName = brandName
        
        if isArm {
            self.provider = AppleSiliconSensorProvider()
        } else {
            self.provider = IntelSensorProvider()
        }
        
        // Initial sample
        refreshNow()
        startPolling(interval: AppSettings.shared.refreshInterval)
    }
    
    public func startPolling(interval: TimeInterval) {
        timer?.invalidate()
        self.currentRefreshInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshNow()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    public func refreshNow() {
        self.cpuTemp = provider.cpuTemperature()
        self.gpuTemp = provider.gpuTemperature()
        self.fanSpeeds = provider.fanSpeeds()
        self.batteryInfo = provider.batteryInfo()
        self.cpuLoad = provider.cpuLoad()
        self.memoryStats = provider.memoryStats()
        self.diskIO = provider.diskIO()
        self.networkStats = provider.networkThroughput()
        self.powerReadings = provider.powerDraw()
        self.thermalState = provider.thermalState()
        
        // Record into history
        HistoryStore.shared.recordSnapshot(
            cpuLoad: cpuLoad.totalLoad,
            cpuTemp: cpuTemp,
            gpuTemp: gpuTemp,
            fanRPM: fanSpeeds.first?.currentRPM,
            memoryPressure: memoryStats.pressurePercentage,
            batteryPct: batteryInfo.chargePercentage,
            packageWatts: powerReadings?.totalPackageWatts,
            diskRead: diskIO.readBytesPerSec,
            diskWrite: diskIO.writeBytesPerSec,
            netRx: networkStats.downloadBytesPerSec,
            netTx: networkStats.uploadBytesPerSec
        )
        
        // Broadcast live telemetry to Firebase Cloud for Android companion
        FirebaseManager.shared.publishLiveTelemetry(
            cpuTemp: cpuTemp,
            gpuTemp: gpuTemp,
            cpuLoad: cpuLoad,
            memoryStats: memoryStats,
            fanSpeeds: fanSpeeds,
            batteryInfo: batteryInfo,
            powerReadings: powerReadings,
            thermalState: thermalState,
            chipName: chipName
        )
    }
}
