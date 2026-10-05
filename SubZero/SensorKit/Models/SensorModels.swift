import Foundation

public struct FanReading: Identifiable, Equatable, Codable {
    public var id: Int
    public var name: String
    public var currentRPM: Double
    public var minRPM: Double
    public var maxRPM: Double
    
    public init(id: Int, name: String, currentRPM: Double, minRPM: Double, maxRPM: Double) {
        self.id = id
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

public struct BatteryInfo: Equatable, Codable {
    public var isPresent: Bool
    public var chargePercentage: Double?
    public var healthPercentage: Double?
    public var cycleCount: Int?
    public var voltage: Double?
    public var amperage: Double?
    public var wattage: Double?
    public var timeRemainingMinutes: Int?
    public var temperature: Double?
    public var isCharging: Bool
    public var isPluggedIn: Bool
    
    public init(
        isPresent: Bool = false,
        chargePercentage: Double? = nil,
        healthPercentage: Double? = nil,
        cycleCount: Int? = nil,
        voltage: Double? = nil,
        amperage: Double? = nil,
        wattage: Double? = nil,
        timeRemainingMinutes: Int? = nil,
        temperature: Double? = nil,
        isCharging: Bool = false,
        isPluggedIn: Bool = false
    ) {
        self.isPresent = isPresent
        self.chargePercentage = chargePercentage
        self.healthPercentage = healthPercentage
        self.cycleCount = cycleCount
        self.voltage = voltage
        self.amperage = amperage
        self.wattage = wattage
        self.timeRemainingMinutes = timeRemainingMinutes
        self.temperature = temperature
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
    }
}

public struct CPULoad: Equatable, Codable {
    public var totalLoad: Double
    public var pCoreLoad: Double?
    public var eCoreLoad: Double?
    public var perCoreLoads: [Double]
    public var pCoreCount: Int?
    public var eCoreCount: Int?
    
    public init(
        totalLoad: Double = 0.0,
        pCoreLoad: Double? = nil,
        eCoreLoad: Double? = nil,
        perCoreLoads: [Double] = [],
        pCoreCount: Int? = nil,
        eCoreCount: Int? = nil
    ) {
        self.totalLoad = totalLoad
        self.pCoreLoad = pCoreLoad
        self.eCoreLoad = eCoreLoad
        self.perCoreLoads = perCoreLoads
        self.pCoreCount = pCoreCount
        self.eCoreCount = eCoreCount
    }
}

public struct MemoryStats: Equatable, Codable {
    public var usedBytes: UInt64
    public var totalBytes: UInt64
    public var swapUsedBytes: UInt64
    public var pressurePercentage: Double
    
    public init(
        usedBytes: UInt64 = 0,
        totalBytes: UInt64 = 0,
        swapUsedBytes: UInt64 = 0,
        pressurePercentage: Double = 0.0
    ) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressurePercentage = pressurePercentage
    }
}

public struct DiskIOStats: Equatable, Codable {
    public var readBytesPerSec: Double
    public var writeBytesPerSec: Double
    
    public init(readBytesPerSec: Double = 0.0, writeBytesPerSec: Double = 0.0) {
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
    }
}

public struct NetworkStats: Equatable, Codable {
    public var downloadBytesPerSec: Double
    public var uploadBytesPerSec: Double
    
    public init(downloadBytesPerSec: Double = 0.0, uploadBytesPerSec: Double = 0.0) {
        self.downloadBytesPerSec = downloadBytesPerSec
        self.uploadBytesPerSec = uploadBytesPerSec
    }
}

public struct PowerReadings: Equatable, Codable {
    public var cpuWatts: Double?
    public var gpuWatts: Double?
    public var aneWatts: Double?
    public var dramWatts: Double?
    public var totalPackageWatts: Double?
    
    public init(
        cpuWatts: Double? = nil,
        gpuWatts: Double? = nil,
        aneWatts: Double? = nil,
        dramWatts: Double? = nil,
        totalPackageWatts: Double? = nil
    ) {
        self.cpuWatts = cpuWatts
        self.gpuWatts = gpuWatts
        self.aneWatts = aneWatts
        self.dramWatts = dramWatts
        self.totalPackageWatts = totalPackageWatts
    }
}

public struct ThermalStatus: Equatable {
    public var thermalState: ProcessInfo.ThermalState
    public var cpuTemperature: Double?
    public var gpuTemperature: Double?
    public var socTemperature: Double?
    
    public init(
        thermalState: ProcessInfo.ThermalState = .nominal,
        cpuTemperature: Double? = nil,
        gpuTemperature: Double? = nil,
        socTemperature: Double? = nil
    ) {
        self.thermalState = thermalState
        self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature
        self.socTemperature = socTemperature
    }
}
