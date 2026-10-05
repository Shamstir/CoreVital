import Foundation
import Combine

public struct HistoricalSnapshot: Identifiable, Equatable, Codable {
    public var id = UUID()
    public var timestamp: Date
    public var cpuLoad: Double
    public var cpuTemp: Double?
    public var gpuTemp: Double?
    public var fanRPM: Double?
    public var memoryPressure: Double
    public var batteryPct: Double?
    public var packageWatts: Double?
    public var diskReadBytesPerSec: Double
    public var diskWriteBytesPerSec: Double
    public var netRxBytesPerSec: Double
    public var netTxBytesPerSec: Double
    
    public init(
        timestamp: Date = Date(),
        cpuLoad: Double = 0.0,
        cpuTemp: Double? = nil,
        gpuTemp: Double? = nil,
        fanRPM: Double? = nil,
        memoryPressure: Double = 0.0,
        batteryPct: Double? = nil,
        packageWatts: Double? = nil,
        diskReadBytesPerSec: Double = 0.0,
        diskWriteBytesPerSec: Double = 0.0,
        netRxBytesPerSec: Double = 0.0,
        netTxBytesPerSec: Double = 0.0
    ) {
        self.timestamp = timestamp
        self.cpuLoad = cpuLoad
        self.cpuTemp = cpuTemp
        self.gpuTemp = gpuTemp
        self.fanRPM = fanRPM
        self.memoryPressure = memoryPressure
        self.batteryPct = batteryPct
        self.packageWatts = packageWatts
        self.diskReadBytesPerSec = diskReadBytesPerSec
        self.diskWriteBytesPerSec = diskWriteBytesPerSec
        self.netRxBytesPerSec = netRxBytesPerSec
        self.netTxBytesPerSec = netTxBytesPerSec
    }
}

@MainActor
public final class HistoryStore: ObservableObject {
    public static let shared = HistoryStore()
    
    @Published public private(set) var snapshots1Min: [HistoricalSnapshot] = []
    @Published public private(set) var snapshots1Hour: [HistoricalSnapshot] = []
    @Published public private(set) var snapshots24Hour: [HistoricalSnapshot] = []
    
    private var bufferForNextHourPoint: [HistoricalSnapshot] = []
    private var bufferForNext24HourPoint: [HistoricalSnapshot] = []
    
    private let persistenceURL: URL?
    private var saveTask: Task<Void, Never>?
    
    private init() {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("SubZero", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.persistenceURL = dir.appendingPathComponent("history.json")
        } else {
            self.persistenceURL = nil
        }
        
        loadFromDisk()
    }
    
    public func recordSnapshot(
        cpuLoad: Double,
        cpuTemp: Double?,
        gpuTemp: Double?,
        fanRPM: Double?,
        memoryPressure: Double,
        batteryPct: Double?,
        packageWatts: Double?,
        diskRead: Double,
        diskWrite: Double,
        netRx: Double,
        netTx: Double
    ) {
        let snapshot = HistoricalSnapshot(
            timestamp: Date(),
            cpuLoad: cpuLoad,
            cpuTemp: cpuTemp,
            gpuTemp: gpuTemp,
            fanRPM: fanRPM,
            memoryPressure: memoryPressure,
            batteryPct: batteryPct,
            packageWatts: packageWatts,
            diskReadBytesPerSec: diskRead,
            diskWriteBytesPerSec: diskWrite,
            netRxBytesPerSec: netRx,
            netTxBytesPerSec: netTx
        )
        
        // 1 Minute buffer (keep last 60 seconds of points)
        snapshots1Min.append(snapshot)
        let cutoff1Min = Date().addingTimeInterval(-60)
        snapshots1Min.removeAll { $0.timestamp < cutoff1Min }
        if snapshots1Min.count > 120 {
            snapshots1Min.removeFirst(snapshots1Min.count - 120)
        }
        
        // Accumulate for 1 Hour buffer (downsample to 1 point per minute)
        bufferForNextHourPoint.append(snapshot)
        if let first = bufferForNextHourPoint.first, Date().timeIntervalSince(first.timestamp) >= 60 {
            if let aggregated = aggregate(snapshots: bufferForNextHourPoint) {
                snapshots1Hour.append(aggregated)
                let cutoff1Hour = Date().addingTimeInterval(-3600)
                snapshots1Hour.removeAll { $0.timestamp < cutoff1Hour }
            }
            bufferForNextHourPoint.removeAll()
        }
        
        // Accumulate for 24 Hour buffer (downsample to 1 point per 10 minutes)
        bufferForNext24HourPoint.append(snapshot)
        if let first = bufferForNext24HourPoint.first, Date().timeIntervalSince(first.timestamp) >= 600 {
            if let aggregated = aggregate(snapshots: bufferForNext24HourPoint) {
                snapshots24Hour.append(aggregated)
                let cutoff24Hour = Date().addingTimeInterval(-86400)
                snapshots24Hour.removeAll { $0.timestamp < cutoff24Hour }
            }
            bufferForNext24HourPoint.removeAll()
        }
        
        scheduleSave()
    }
    
    private func aggregate(snapshots: [HistoricalSnapshot]) -> HistoricalSnapshot? {
        guard !snapshots.isEmpty else { return nil }
        let count = Double(snapshots.count)
        
        let avgCpuLoad = snapshots.reduce(0.0) { $0 + $1.cpuLoad } / count
        let avgMemPressure = snapshots.reduce(0.0) { $0 + $1.memoryPressure } / count
        let avgDiskRead = snapshots.reduce(0.0) { $0 + $1.diskReadBytesPerSec } / count
        let avgDiskWrite = snapshots.reduce(0.0) { $0 + $1.diskWriteBytesPerSec } / count
        let avgNetRx = snapshots.reduce(0.0) { $0 + $1.netRxBytesPerSec } / count
        let avgNetTx = snapshots.reduce(0.0) { $0 + $1.netTxBytesPerSec } / count
        
        let validCpuTemps = snapshots.compactMap { $0.cpuTemp }
        let avgCpuTemp = validCpuTemps.isEmpty ? nil : validCpuTemps.reduce(0.0, +) / Double(validCpuTemps.count)
        
        let validGpuTemps = snapshots.compactMap { $0.gpuTemp }
        let avgGpuTemp = validGpuTemps.isEmpty ? nil : validGpuTemps.reduce(0.0, +) / Double(validGpuTemps.count)
        
        let validFanRPMs = snapshots.compactMap { $0.fanRPM }
        let avgFanRPM = validFanRPMs.isEmpty ? nil : validFanRPMs.reduce(0.0, +) / Double(validFanRPMs.count)
        
        let validBatts = snapshots.compactMap { $0.batteryPct }
        let avgBatt = validBatts.isEmpty ? nil : validBatts.reduce(0.0, +) / Double(validBatts.count)
        
        let validWatts = snapshots.compactMap { $0.packageWatts }
        let avgWatts = validWatts.isEmpty ? nil : validWatts.reduce(0.0, +) / Double(validWatts.count)
        
        return HistoricalSnapshot(
            timestamp: snapshots.last?.timestamp ?? Date(),
            cpuLoad: avgCpuLoad,
            cpuTemp: avgCpuTemp,
            gpuTemp: avgGpuTemp,
            fanRPM: avgFanRPM,
            memoryPressure: avgMemPressure,
            batteryPct: avgBatt,
            packageWatts: avgWatts,
            diskReadBytesPerSec: avgDiskRead,
            diskWriteBytesPerSec: avgDiskWrite,
            netRxBytesPerSec: avgNetRx,
            netTxBytesPerSec: avgNetTx
        )
    }
    
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // Debounce 5s
            guard !Task.isCancelled else { return }
            saveToDisk()
        }
    }
    
    private func saveToDisk() {
        guard let url = persistenceURL else { return }
        let dataToSave = HistoryPersistData(
            hour: snapshots1Hour,
            day: snapshots24Hour
        )
        if let encoded = try? JSONEncoder().encode(dataToSave) {
            try? encoded.write(to: url, options: .atomic)
        }
    }
    
    private func loadFromDisk() {
        guard let url = persistenceURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(HistoryPersistData.self, from: data) else {
            return
        }
        let now = Date()
        self.snapshots1Hour = decoded.hour.filter { now.timeIntervalSince($0.timestamp) <= 3600 }
        self.snapshots24Hour = decoded.day.filter { now.timeIntervalSince($0.timestamp) <= 86400 }
    }
    
    private struct HistoryPersistData: Codable {
        var hour: [HistoricalSnapshot]
        var day: [HistoricalSnapshot]
    }
}
