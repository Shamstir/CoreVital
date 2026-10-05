import Foundation
import Combine
import ServiceManagement
import AppKit

public enum FanControlMode: Int, Codable, CaseIterable {
    case auto = 0
    case manual = 1
    case curve = 2
    
    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .manual: return "Manual"
        case .curve: return "Curve"
        }
    }
}

public enum HelperStatus: String {
    case registered = "Installed & Active"
    case notRegistered = "Not Installed"
    case requiresApproval = "Requires System Settings Approval"
    case notFound = "Helper Bundle Missing"
}

@MainActor
public final class FanControlManager: ObservableObject {
    public static let shared = FanControlManager()
    
    @Published public var helperStatus: HelperStatus = .notRegistered
    @Published public var helperVersion: String? = nil
    @Published public var activeModes: [Int: FanControlMode] = [:]
    @Published public var manualTargets: [Int: Double] = [:]
    @Published public var selectedCurveProfiles: [Int: UUID] = [:]
    @Published public var availableCurveProfiles: [FanCurveProfile] = []
    @Published public var isEmergencyThermalOverrideActive: Bool = false
    @Published public var lastOperationError: String? = nil
    
    private var xpcConnection: NSXPCConnection?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadDefaultCurveProfiles()
        loadPreferences()
        refreshHelperStatus()
        setupWatchdogAndObserver()
        setupTerminationHook()
    }
    
    private func loadDefaultCurveProfiles() {
        let quiet = FanCurveProfile(name: "Quiet Acoustic", points: [
            FanCurvePoint(temperature: 45, targetRPM: 2317),
            FanCurvePoint(temperature: 65, targetRPM: 3000),
            FanCurvePoint(temperature: 85, targetRPM: 6550)
        ])
        
        let balanced = FanCurveProfile(name: "Balanced Cooling", points: [
            FanCurvePoint(temperature: 40, targetRPM: 2317),
            FanCurvePoint(temperature: 60, targetRPM: 4000),
            FanCurvePoint(temperature: 80, targetRPM: 6550)
        ])
        
        let performance = FanCurveProfile(name: "Max Performance", points: [
            FanCurvePoint(temperature: 35, targetRPM: 3000),
            FanCurvePoint(temperature: 55, targetRPM: 5000),
            FanCurvePoint(temperature: 75, targetRPM: 6550)
        ])
        
        self.availableCurveProfiles = [quiet, balanced, performance]
    }
    
    public func refreshHelperStatus() {
        let service = SMAppService.daemon(plistName: "com.subzero.helper.plist")
        switch service.status {
        case .enabled:
            self.helperStatus = .registered
            checkHelperConnection()
        case .requiresApproval:
            self.helperStatus = .requiresApproval
        case .notRegistered:
            self.helperStatus = .notRegistered
        case .notFound:
            self.helperStatus = .notFound
        @unknown default:
            self.helperStatus = .notRegistered
        }
    }
    
    public func installHelper() {
        let service = SMAppService.daemon(plistName: "com.subzero.helper.plist")
        do {
            try service.register()
            refreshHelperStatus()
            self.lastOperationError = nil
        } catch {
            self.lastOperationError = "Installation error: \(error.localizedDescription)"
            refreshHelperStatus()
        }
    }
    
    public func uninstallHelper() {
        let service = SMAppService.daemon(plistName: "com.subzero.helper.plist")
        do {
            try service.unregister()
            refreshHelperStatus()
            self.lastOperationError = nil
        } catch {
            self.lastOperationError = "Uninstallation error: \(error.localizedDescription)"
            refreshHelperStatus()
        }
    }
    
    private func getHelperProxy() -> SubZeroHelperProtocol? {
        if xpcConnection == nil {
            let connection = NSXPCConnection(machServiceName: "com.subzero.helper", options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: SubZeroHelperProtocol.self)
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor in
                    self?.xpcConnection = nil
                }
            }
            connection.interruptionHandler = { [weak self] in
                Task { @MainActor in
                    self?.xpcConnection = nil
                }
            }
            connection.resume()
            xpcConnection = connection
        }
        return xpcConnection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.lastOperationError = "XPC Connection Error: \(error.localizedDescription)"
                self?.xpcConnection = nil
            }
        } as? SubZeroHelperProtocol
    }
    
    public func checkHelperConnection() {
        guard let proxy = getHelperProxy() else { return }
        proxy.getHelperVersion(withReply: { version in
            Task { @MainActor in
                FanControlManager.shared.helperVersion = version
            }
        })
    }
    
    public func setMode(_ mode: FanControlMode, forFan fanID: Int, fanReadings: [FanReading]) {
        activeModes[fanID] = mode
        savePreferences()
        applyFanState(fanID: fanID, fanReadings: fanReadings)
    }
    
    public func setManualTarget(_ speed: Double, forFan fanID: Int, fanReadings: [FanReading]) {
        if let fan = fanReadings.first(where: { $0.id == fanID }) {
            let clamped = max(fan.minRPM, min(fan.maxRPM, speed))
            manualTargets[fanID] = clamped
        } else {
            manualTargets[fanID] = speed
        }
        savePreferences()
        if activeModes[fanID] == .manual {
            applyFanState(fanID: fanID, fanReadings: fanReadings)
        }
    }
    
    public func selectCurveProfile(_ profileID: UUID, forFan fanID: Int, fanReadings: [FanReading]) {
        selectedCurveProfiles[fanID] = profileID
        savePreferences()
        if activeModes[fanID] == .curve {
            applyFanState(fanID: fanID, fanReadings: fanReadings)
        }
    }
    
    public func applyFanState(fanID: Int, fanReadings: [FanReading]) {
        guard helperStatus == .registered else { return }
        guard let proxy = getHelperProxy() else { return }
        guard let fan = fanReadings.first(where: { $0.id == fanID }) else { return }
        
        let mode = activeModes[fanID] ?? .auto
        
        switch mode {
        case .auto:
            proxy.setFanMode(fanID: fanID, mode: 0, speed: 0.0, withReply: { success, msg in
                Task { @MainActor in
                    if !success { FanControlManager.shared.lastOperationError = msg }
                }
            })
        case .manual:
            let target = manualTargets[fanID] ?? fan.minRPM
            let clamped = max(fan.minRPM, min(fan.maxRPM, target))
            proxy.setFanMode(fanID: fanID, mode: 1, speed: clamped, withReply: { success, msg in
                Task { @MainActor in
                    if !success { FanControlManager.shared.lastOperationError = msg }
                }
            })
        case .curve:
            let target = computeCurveTargetRPM(forFan: fan)
            proxy.setFanMode(fanID: fanID, mode: 1, speed: target, withReply: { success, msg in
                Task { @MainActor in
                    if !success { FanControlManager.shared.lastOperationError = msg }
                }
            })
        }
    }
    
    public func applyAllFans(fanReadings: [FanReading]) {
        for fan in fanReadings {
            applyFanState(fanID: fan.id, fanReadings: fanReadings)
        }
    }
    
    private func computeCurveTargetRPM(forFan fan: FanReading) -> Double {
        let cpuT = SensorManager.shared.cpuTemp ?? 40.0
        let gpuT = SensorManager.shared.gpuTemp ?? 40.0
        let highestTemp = max(cpuT, gpuT)
        
        let profileID = selectedCurveProfiles[fan.id] ?? availableCurveProfiles.first?.id
        if let profile = availableCurveProfiles.first(where: { $0.id == profileID }) {
            return profile.targetRPM(forTemperature: highestTemp, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
        }
        return fan.minRPM
    }
    
    private func setupWatchdogAndObserver() {
        // Observe SensorManager updates every polling cycle
        SensorManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.evaluateWatchdogAndCurves()
            }
            .store(in: &cancellables)
    }
    
    private func evaluateWatchdogAndCurves() {
        guard helperStatus == .registered else { return }
        
        let cpuT = SensorManager.shared.cpuTemp ?? 0.0
        let gpuT = SensorManager.shared.gpuTemp ?? 0.0
        let highestTemp = max(cpuT, gpuT)
        let fans = SensorManager.shared.fanSpeeds
        guard !fans.isEmpty else { return }
        
        // Emergency Thermal Watchdog check (> 92°C)
        if highestTemp > 92.0 {
            if !isEmergencyThermalOverrideActive {
                isEmergencyThermalOverrideActive = true
                guard let proxy = getHelperProxy() else { return }
                for fan in fans {
                    proxy.setFanMode(fanID: fan.id, mode: 1, speed: fan.maxRPM, withReply: { _, _ in })
                }
            }
            return
        } else if isEmergencyThermalOverrideActive && highestTemp <= 88.0 {
            // Temperature dropped below safe threshold (hysteresis check at 88°C)
            isEmergencyThermalOverrideActive = false
            applyAllFans(fanReadings: fans)
            return
        }
        
        // If not emergency, continuously adjust curves if mode == .curve
        if !isEmergencyThermalOverrideActive {
            for fan in fans where activeModes[fan.id] == .curve {
                applyFanState(fanID: fan.id, fanReadings: fans)
            }
        }
    }
    
    public func setAllFansToFullManual() {
        guard let proxy = getHelperProxy() else { return }
        let fans = SensorManager.shared.fanSpeeds
        for fan in fans {
            activeModes[fan.id] = .manual
            manualTargets[fan.id] = fan.maxRPM
            proxy.setFanMode(fanID: fan.id, mode: 1, speed: fan.maxRPM, withReply: { _, _ in })
        }
        savePreferences()
    }
    
    public func resetAllFansToAuto() {
        resetAllToAuto()
    }
    
    public func resetAllToAuto() {
        guard let proxy = getHelperProxy() else { return }
        proxy.resetAllFansToAuto(withReply: { success, msg in
            Task { @MainActor in
                if success {
                    for key in FanControlManager.shared.activeModes.keys {
                        FanControlManager.shared.activeModes[key] = .auto
                    }
                    FanControlManager.shared.savePreferences()
                } else {
                    FanControlManager.shared.lastOperationError = msg
                }
            }
        })
    }
    
    private func setupTerminationHook() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                guard FanControlManager.shared.helperStatus == .registered else { return }
                guard let proxy = FanControlManager.shared.getHelperProxy() else { return }
                proxy.resetAllFansToAuto(withReply: { _, _ in })
            }
        }
    }
    
    private func savePreferences() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(activeModes) {
            defaults.set(data, forKey: "FanControlManager.activeModes")
        }
        if let data = try? JSONEncoder().encode(manualTargets) {
            defaults.set(data, forKey: "FanControlManager.manualTargets")
        }
        if let data = try? JSONEncoder().encode(selectedCurveProfiles) {
            defaults.set(data, forKey: "FanControlManager.selectedCurveProfiles")
        }
        if let data = try? JSONEncoder().encode(availableCurveProfiles) {
            defaults.set(data, forKey: "FanControlManager.availableCurveProfiles")
        }
    }
    
    private func loadPreferences() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "FanControlManager.activeModes"),
           let decoded = try? JSONDecoder().decode([Int: FanControlMode].self, from: data) {
            self.activeModes = decoded
        }
        if let data = defaults.data(forKey: "FanControlManager.manualTargets"),
           let decoded = try? JSONDecoder().decode([Int: Double].self, from: data) {
            self.manualTargets = decoded
        }
        if let data = defaults.data(forKey: "FanControlManager.selectedCurveProfiles"),
           let decoded = try? JSONDecoder().decode([Int: UUID].self, from: data) {
            self.selectedCurveProfiles = decoded
        }
        if let data = defaults.data(forKey: "FanControlManager.availableCurveProfiles"),
           let decoded = try? JSONDecoder().decode([FanCurveProfile].self, from: data) {
            self.availableCurveProfiles = decoded
        }
    }
}
