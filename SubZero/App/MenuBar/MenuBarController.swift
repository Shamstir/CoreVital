import AppKit
import SwiftUI
import Combine

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var menu: NSMenu!
    
    private var cpuMenuItem: NSMenuItem!
    private var gpuMenuItem: NSMenuItem!
    private var memMenuItem: NSMenuItem!
    private var fanMenuItem: NSMenuItem!
    private var batteryMenuItem: NSMenuItem!
    private var netMenuItem: NSMenuItem!
    private var standMenuItem: NSMenuItem!
    private var accountMenuItem: NSMenuItem!
    
    public var onOpenDashboard: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    
    public override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupMenu()
        bindData()
    }
    
    private func setupMenu() {
        menu = NSMenu()
        menu.delegate = self
        
        let headerItem = NSMenuItem(title: "sub_zero", action: nil, keyEquivalent: "")
        headerItem.attributedTitle = NSAttributedString(string: "sub_zero", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ])
        menu.addItem(headerItem)

        accountMenuItem = NSMenuItem(title: "Account: Connecting...", action: #selector(openSettingsAction), keyEquivalent: "")
        accountMenuItem.target = self
        menu.addItem(accountMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        cpuMenuItem = NSMenuItem(title: "CPU: --", action: #selector(openDashboardAction), keyEquivalent: "")
        cpuMenuItem.target = self
        menu.addItem(cpuMenuItem)
        
        gpuMenuItem = NSMenuItem(title: "GPU: --", action: #selector(openDashboardAction), keyEquivalent: "")
        gpuMenuItem.target = self
        menu.addItem(gpuMenuItem)
        
        memMenuItem = NSMenuItem(title: "Memory: --", action: #selector(openDashboardAction), keyEquivalent: "")
        memMenuItem.target = self
        menu.addItem(memMenuItem)
        
        fanMenuItem = NSMenuItem(title: "Fans: --", action: #selector(openDashboardAction), keyEquivalent: "")
        fanMenuItem.target = self
        menu.addItem(fanMenuItem)
        
        batteryMenuItem = NSMenuItem(title: "Battery: --", action: #selector(openDashboardAction), keyEquivalent: "")
        batteryMenuItem.target = self
        menu.addItem(batteryMenuItem)
        
        netMenuItem = NSMenuItem(title: "Network: --", action: #selector(openDashboardAction), keyEquivalent: "")
        netMenuItem.target = self
        menu.addItem(netMenuItem)

        standMenuItem = NSMenuItem(title: "Stand: --", action: #selector(openDashboardAction), keyEquivalent: "")
        standMenuItem.target = self
        standMenuItem.isHidden = true
        menu.addItem(standMenuItem)

        menu.addItem(NSMenuItem.separator())
        
        let dashItem = NSMenuItem(title: "Open Dashboard...", action: #selector(openDashboardAction), keyEquivalent: "d")
        dashItem.target = self
        menu.addItem(dashItem)
        
        let settingsItem = NSMenuItem(title: "Preferences...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let demoAlertItem = NSMenuItem(title: "🔥 Trigger Phone Thermal Alert (Demo)", action: #selector(triggerPhoneAlertAction), keyEquivalent: "t")
        demoAlertItem.target = self
        menu.addItem(demoAlertItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit sub_zero", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func triggerPhoneAlertAction() {
        PairingManager.shared.triggerTestAlert()
    }
    
    private func bindData() {
        // Observe both SensorManager and AppSettings
        SensorManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarAndDropdown()
            }
            .store(in: &cancellables)
            
        AppSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarAndDropdown()
            }
            .store(in: &cancellables)

        FirebaseManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarAndDropdown()
            }
            .store(in: &cancellables)

        StandManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarAndDropdown()
            }
            .store(in: &cancellables)
    
        // Initial update
        updateMenuBarAndDropdown()
    }
    
    private func updateMenuBarAndDropdown() {
        guard let button = statusItem.button else { return }
        
        let sensors = SensorManager.shared
        let settings = AppSettings.shared
        let selected = settings.selectedMenuBarMetrics
        
        // Build compact string / attributed title
        var parts: [String] = []
        for metric in selected.prefix(4) {
            switch metric {
            case .cpuLoad:
                parts.append(String(format: "CPU %.0f%%", sensors.cpuLoad.totalLoad))
            case .cpuTemp:
                parts.append(settings.formatTemperature(sensors.cpuTemp))
            case .gpuTemp:
                if let g = sensors.gpuTemp {
                    parts.append("GPU " + settings.formatTemperature(g))
                }
            case .memoryPct:
                parts.append(String(format: "MEM %.0f%%", sensors.memoryStats.pressurePercentage))
            case .fanRPM:
                if let firstFan = sensors.fanSpeeds.first {
                    parts.append(String(format: "%.0f RPM", firstFan.currentRPM))
                }
            case .batteryPct:
                if let pct = sensors.batteryInfo.chargePercentage {
                    parts.append(String(format: "%.0f%%", pct))
                }
            case .networkSpeed:
                let downMB = sensors.networkStats.downloadBytesPerSec / 1_048_576.0
                parts.append(String(format: "↓%.1fM", downMB))
            }
        }
        
        if parts.isEmpty {
            button.title = "App"
        } else {
            button.title = parts.joined(separator: " | ")
        }
        
        // Update menu items
        cpuMenuItem.title = String(format: "CPU: %.1f%% (%@)", sensors.cpuLoad.totalLoad, settings.formatTemperature(sensors.cpuTemp))
        if let g = sensors.gpuTemp {
            gpuMenuItem.isHidden = false
            gpuMenuItem.title = "GPU Temp: " + settings.formatTemperature(g)
        } else {
            gpuMenuItem.isHidden = true
        }
        
        let usedGB = Double(sensors.memoryStats.usedBytes) / 1_073_741_824.0
        let totalGB = Double(sensors.memoryStats.totalBytes) / 1_073_741_824.0
        memMenuItem.title = String(format: "Memory: %.1f GB / %.0f GB (%.0f%%)", usedGB, totalGB, sensors.memoryStats.pressurePercentage)
        
        if sensors.fanSpeeds.isEmpty {
            fanMenuItem.isHidden = true
        } else {
            fanMenuItem.isHidden = false
            let fanStrings = sensors.fanSpeeds.map { String(format: "%@: %.0f RPM", $0.name, $0.currentRPM) }
            fanMenuItem.title = "Fans: " + fanStrings.joined(separator: ", ")
        }
        
        if sensors.batteryInfo.isPresent, let pct = sensors.batteryInfo.chargePercentage {
            batteryMenuItem.isHidden = false
            let statusStr = sensors.batteryInfo.isCharging ? "Charging" : "On Battery"
            batteryMenuItem.title = String(format: "Battery: %.0f%% (%@)", pct, statusStr)
        } else {
            batteryMenuItem.isHidden = true
        }
        
        let downKB = sensors.networkStats.downloadBytesPerSec / 1024.0
        let upKB = sensors.networkStats.uploadBytesPerSec / 1024.0
        netMenuItem.title = String(format: "Network: ↓%.1f KB/s | ↑%.1f KB/s", downKB, upKB)

        let stand = StandManager.shared
        if stand.connectionState == .connected {
            standMenuItem.isHidden = false
            let cooling = stand.isCooling
                ? (stand.rampReady ? "Cooling (optimal)" : String(format: "Cooling (optimal in %ds)", stand.secondsToOptimal))
                : "Idle"
            standMenuItem.title = "Stand: \(stand.isAutoEnabled ? "Auto" : "Manual") · \(cooling)"
        } else {
            standMenuItem.isHidden = stand.connectionState != .scanning && stand.connectionState != .connecting
            standMenuItem.title = "Stand: \(stand.connectionState.rawValue)..."
        }

        if let email = FirebaseManager.shared.currentUserEmail {
            accountMenuItem.title = "Account: \(email) (Linked)"
        } else if FirebaseManager.shared.isConfigured {
            accountMenuItem.title = "Account: Guest (Click to Link...)"
        } else {
            accountMenuItem.title = "Account: Not Configured"
        }
    }
    
    @objc private func openDashboardAction() {
        onOpenDashboard?()
    }
    
    @objc private func openSettingsAction() {
        onOpenSettings?()
    }
    
    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
