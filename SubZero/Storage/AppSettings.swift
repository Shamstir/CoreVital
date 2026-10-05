import Foundation
import SwiftUI
import ServiceManagement

public enum TemperatureUnit: String, CaseIterable, Identifiable, Codable {
    case celsius = "Celsius (°C)"
    case fahrenheit = "Fahrenheit (°F)"
    public var id: String { rawValue }
    
    public var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}

public enum MenuBarMetricType: String, CaseIterable, Identifiable, Codable {
    case cpuLoad = "cpuLoad"
    case cpuTemp = "cpuTemp"
    case gpuTemp = "gpuTemp"
    case memoryPct = "memoryPct"
    case fanRPM = "fanRPM"
    case batteryPct = "batteryPct"
    case networkSpeed = "networkSpeed"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .cpuLoad: return "CPU Usage"
        case .cpuTemp: return "CPU Temperature"
        case .gpuTemp: return "GPU Temperature"
        case .memoryPct: return "Memory Usage"
        case .fanRPM: return "Fan Speed"
        case .batteryPct: return "Battery Charge"
        case .networkSpeed: return "Network Speed"
        }
    }
    
    public var iconName: String {
        switch self {
        case .cpuLoad: return "cpu"
        case .cpuTemp: return "thermometer.medium"
        case .gpuTemp: return "display.2"
        case .memoryPct: return "memorychip"
        case .fanRPM: return "fanblades.fill"
        case .batteryPct: return "battery.100"
        case .networkSpeed: return "network"
        }
    }
}

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    @AppStorage("refreshInterval") public var refreshInterval: Double = 2.0 {
        didSet {
            SensorManager.shared.startPolling(interval: refreshInterval)
        }
    }
    
    @AppStorage("temperatureUnit") public var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue {
        didSet {
            objectWillChange.send()
        }
    }
    
    public var temperatureUnit: TemperatureUnit {
        get { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
        set { temperatureUnitRaw = newValue.rawValue }
    }
    
    @AppStorage("selectedMenuBarMetricsRaw") private var selectedMenuBarMetricsRaw: String = "cpuLoad,cpuTemp,memoryPct" {
        didSet {
            objectWillChange.send()
        }
    }
    
    public var selectedMenuBarMetrics: [MenuBarMetricType] {
        get {
            let components = selectedMenuBarMetricsRaw.split(separator: ",").map(String.init)
            return components.compactMap { MenuBarMetricType(rawValue: $0) }
        }
        set {
            selectedMenuBarMetricsRaw = newValue.map { $0.rawValue }.joined(separator: ",")
        }
    }
    
    @AppStorage("launchAtLogin") public var launchAtLogin: Bool = false {
        didSet {
            updateLaunchAtLogin()
        }
    }
    
    private init() {
        // Sync launch at login status from OS on start
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            let isEnabled = (status == .enabled)
            if launchAtLogin != isEnabled {
                launchAtLogin = isEnabled
            }
        }
    }
    
    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to toggle launch at login via SMAppService: \(error)")
            }
        }
    }
    
    public func formatTemperature(_ celsius: Double?) -> String {
        guard let c = celsius else { return "--" }
        switch temperatureUnit {
        case .celsius:
            return String(format: "%.0f°C", c)
        case .fahrenheit:
            let f = (c * 9.0 / 5.0) + 32.0
            return String(format: "%.0f°F", f)
        }
    }
}
