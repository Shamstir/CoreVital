import Foundation
import SwiftUI
import Combine

public enum ChartTimeRange: String, CaseIterable, Identifiable {
    case oneMin = "1 Min"
    case oneHour = "1 Hour"
    case twentyFourHour = "24 Hours"
    
    public var id: String { rawValue }
}

public enum ChartMetricType: String, CaseIterable, Identifiable {
    case cpuLoad = "CPU Usage"
    case cpuTemp = "CPU Temperature"
    case memoryPressure = "Memory Pressure"
    case fanRPM = "Fan Speed"
    case batteryPct = "Battery Level"
    case powerWatts = "Power Draw"
    
    public var id: String { rawValue }
    
    @MainActor
    public var unitString: String {
        switch self {
        case .cpuLoad, .memoryPressure, .batteryPct: return "%"
        case .cpuTemp: return AppSettings.shared.temperatureUnit.symbol
        case .fanRPM: return "RPM"
        case .powerWatts: return "W"
        }
    }
    
    public var color: Color {
        switch self {
        case .cpuLoad: return .blue
        case .cpuTemp: return .orange
        case .memoryPressure: return .purple
        case .fanRPM: return .cyan
        case .batteryPct: return .green
        case .powerWatts: return .yellow
        }
    }
}

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public var selectedTimeRange: ChartTimeRange = .oneMin
    @Published public var selectedChartMetric: ChartMetricType = .cpuLoad
    
    public init() {}
    
    public func getSnapshots(from store: HistoryStore) -> [HistoricalSnapshot] {
        switch selectedTimeRange {
        case .oneMin:
            return store.snapshots1Min
        case .oneHour:
            return store.snapshots1Hour
        case .twentyFourHour:
            return store.snapshots24Hour
        }
    }
    
    public func getValue(for metric: ChartMetricType, from snapshot: HistoricalSnapshot) -> Double? {
        switch metric {
        case .cpuLoad:
            return snapshot.cpuLoad
        case .cpuTemp:
            guard let c = snapshot.cpuTemp else { return nil }
            if AppSettings.shared.temperatureUnit == .fahrenheit {
                return (c * 9.0 / 5.0) + 32.0
            }
            return c
        case .memoryPressure:
            return snapshot.memoryPressure
        case .fanRPM:
            return snapshot.fanRPM
        case .batteryPct:
            return snapshot.batteryPct
        case .powerWatts:
            return snapshot.packageWatts
        }
    }
}
