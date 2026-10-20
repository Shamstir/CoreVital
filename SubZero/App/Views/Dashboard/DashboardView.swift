import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var sensors: SensorManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var historyStore: HistoryStore
    
    @StateObject private var chartViewModel = DashboardViewModel()
    @ObservedObject private var fanControl = FanControlManager.shared
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 16) {
                headerSection
                
                MetricChartView(viewModel: chartViewModel)
                    .environmentObject(historyStore)
                
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    cpuLoadSection
                    temperatureSection
                    memoryDiskSection
                    fansSection
                    batterySection
                    networkSection
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 800, minHeight: 600)
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                
                HStack(spacing: 8) {
                    Label(sensors.chipName, systemImage: "cpu")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(sensors.isAppleSilicon ? "Apple Silicon" : "Intel Architecture")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            // Thermal Badge
            thermalBadge
            
            // Demo Alert Phone Button
            Button(action: {
                PairingManager.shared.triggerTestAlert()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("Alert Phone")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .foregroundColor(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Send a simulated critical thermal alert to your Android phone (Demo)")
            
            // Preferences Button
            Button(action: {
                if let delegate = NSApplication.shared.delegate as? AppDelegate {
                    delegate.showSettingsWindow()
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Circle().fill(Color(NSColor.controlBackgroundColor)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
    }
    
    private var thermalBadge: some View {
        let state = sensors.thermalState
        let (title, color, icon): (String, Color, String) = {
            switch state {
            case .nominal:
                return ("Thermal: Nominal", .green, "checkmark.circle.fill")
            case .fair:
                return ("Thermal: Fair", .yellow, "exclamationmark.circle.fill")
            case .serious:
                return ("Thermal: Serious", .orange, "flame.fill")
            case .critical:
                return ("Thermal: Critical", .red, "flame.circle.fill")
            @unknown default:
                return ("Thermal: Unknown", .secondary, "questionmark.circle")
            }
        }()
        
        return HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
    
    // MARK: - CPU & GPU Load Section
    private var cpuLoadSection: some View {
        cardView(title: "CPU & Core Utilization", icon: "cpu", color: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Load")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", sensors.cpuLoad.totalLoad))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                    }
                    Spacer()
                    if let p = sensors.cpuLoad.pCoreLoad {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("P-Cores (\(sensors.cpuLoad.pCoreCount ?? 0))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f%%", p))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.orange)
                        }
                    }
                    if let e = sensors.cpuLoad.eCoreLoad {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("E-Cores (\(sensors.cpuLoad.eCoreCount ?? 0))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f%%", e))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Divider()
                
                // Per core grid
                if !sensors.cpuLoad.perCoreLoads.isEmpty {
                    Text("Per-Core Breakdown")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    let columns = [GridItem(.adaptive(minimum: 45), spacing: 6)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(Array(sensors.cpuLoad.perCoreLoads.enumerated()), id: \.offset) { index, load in
                            VStack(spacing: 2) {
                                Text("C\(index + 1)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                GeometryReader { geo in
                                    ZStack(alignment: .bottom) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.secondary.opacity(0.15))
                                        
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(load > 80 ? Color.red : (load > 50 ? Color.orange : Color.blue))
                                            .frame(height: geo.size.height * CGFloat(load / 100.0))
                                    }
                                }
                                .frame(height: 24)
                                
                                Text(String(format: "%.0f%%", load))
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Temperature Section
    private var temperatureSection: some View {
        cardView(title: "Hardware Temperatures", icon: "thermometer.medium", color: .orange) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    tempRow(label: "CPU Average", val: sensors.cpuTemp, color: .orange)
                    Spacer()
                    tempRow(label: "GPU Average", val: sensors.gpuTemp, color: .red)
                }
                
                Divider()
                
                // Power Draw (Watts) if available
                if let power = sensors.powerReadings {
                    Text("Package Power Draw")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        if let cpuW = power.cpuWatts {
                            powerRow(label: "CPU", watts: cpuW, color: .blue)
                        }
                        if let gpuW = power.gpuWatts {
                            powerRow(label: "GPU", watts: gpuW, color: .purple)
                        }
                        if let totalW = power.totalPackageWatts {
                            powerRow(label: "Total Package", watts: totalW, color: .green)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "bolt.slash")
                        Text("Detailed power breakdown not reported on this architecture")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private func tempRow(label: String, val: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            if let v = val {
                Text(settings.formatTemperature(v))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            } else {
                Text("--")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func powerRow(label: String, watts: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(String(format: "%.1f W", watts))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
    }
    
    // MARK: - Memory & Disk Section
    private var memoryDiskSection: some View {
        cardView(title: "Memory & Storage I/O", icon: "memorychip", color: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                // Memory
                let usedGB = Double(sensors.memoryStats.usedBytes) / 1_073_741_824.0
                let totalGB = Double(sensors.memoryStats.totalBytes) / 1_073_741_824.0
                let swapGB = Double(sensors.memoryStats.swapUsedBytes) / 1_073_741_824.0
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Used / Total Memory")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f GB / %.0f GB", usedGB, totalGB))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Pressure")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", sensors.memoryStats.pressurePercentage))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(sensors.memoryStats.pressurePercentage > 75 ? .red : .purple)
                    }
                }
                
                if swapGB > 0 {
                    Text(String(format: "Swap Used: %.2f GB", swapGB))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Disk I/O
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Disk Read", systemImage: "arrow.down.doc")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatSpeed(sensors.diskIO.readBytesPerSec))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Label("Disk Write", systemImage: "arrow.up.doc")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatSpeed(sensors.diskIO.writeBytesPerSec))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
    }
    
    // MARK: - Fans Section
    private var fansSection: some View {
        cardView(title: "Cooling & Fans", icon: "fanblades.fill", color: .cyan) {
            VStack(alignment: .leading, spacing: 14) {
                // Emergency Thermal Warning Banner
                if fanControl.isEmergencyThermalOverrideActive {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Emergency Thermal Override (>92°C)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                            Text("Fans locked to 100% until hardware cools to safe levels.")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                
                // Helper Status & Error Banner
                if let error = fanControl.lastOperationError {
                    HStack {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                        Spacer()
                        Button("Dismiss") {
                            fanControl.lastOperationError = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.bold())
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                } else if fanControl.helperStatus != .registered {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.righthalf.filled")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Privileged Helper Required for Manual Control")
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                            Text("macOS requires root authorization via SMAppService to write fan speeds.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Install Helper") {
                            fanControl.installHelper()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                }
                
                if sensors.fanSpeeds.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "wind")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No active cooling fans reported on this Mac")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Apple Silicon systems without fans or unsupported models report 0 fans.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ForEach(sensors.fanSpeeds) { fan in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(fan.name)
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(fan.currentRPM <= 0 ? "0 RPM (Idle)" : String(format: "%.0f RPM", fan.currentRPM))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.cyan)
                            }
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                    
                                    let progress = max(0.0, min(1.0, (fan.currentRPM - fan.minRPM) / max(1.0, fan.maxRPM - fan.minRPM)))
                                    Capsule()
                                        .fill(Color.cyan)
                                        .frame(width: geo.size.width * CGFloat(progress))
                                }
                            }
                            .frame(height: 8)
                            
                            HStack {
                                Text(String(format: "Min: %.0f", fan.minRPM))
                                Spacer()
                                Text(String(format: "Max: %.0f", fan.maxRPM))
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            
                            // Interactive Controls (Active only when helper is registered)
                            if fanControl.helperStatus == .registered {
                                Divider().padding(.vertical, 2)
                                
                                HStack {
                                    Text("Mode:")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    
                                    Picker("Mode", selection: Binding(
                                        get: { fanControl.activeModes[fan.id] ?? .auto },
                                        set: { fanControl.setMode($0, forFan: fan.id, fanReadings: sensors.fanSpeeds) }
                                    )) {
                                        ForEach(FanControlMode.allCases, id: \.self) { mode in
                                            Text(mode.displayName).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 220)
                                    
                                    Spacer()
                                }
                                
                                if (fanControl.activeModes[fan.id] ?? .auto) == .manual {
                                    HStack(spacing: 8) {
                                        Text("Fixed Speed:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Slider(
                                            value: Binding(
                                                get: { fanControl.manualTargets[fan.id] ?? fan.minRPM },
                                                set: { fanControl.setManualTarget($0, forFan: fan.id, fanReadings: sensors.fanSpeeds) }
                                            ),
                                            in: fan.minRPM...fan.maxRPM,
                                            step: 50
                                        )
                                        .tint(.cyan)
                                        
                                        Text(String(format: "%.0f RPM", fanControl.manualTargets[fan.id] ?? fan.minRPM))
                                            .font(.caption.bold().monospacedDigit())
                                            .foregroundColor(.cyan)
                                            .frame(width: 65, alignment: .trailing)
                                    }
                                    .padding(.top, 2)
                                } else if (fanControl.activeModes[fan.id] ?? .auto) == .curve {
                                    HStack {
                                        Text("Profile:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Picker("Profile", selection: Binding(
                                            get: { fanControl.selectedCurveProfiles[fan.id] ?? fanControl.availableCurveProfiles.first?.id ?? UUID() },
                                            set: { fanControl.selectCurveProfile($0, forFan: fan.id, fanReadings: sensors.fanSpeeds) }
                                        )) {
                                            ForEach(fanControl.availableCurveProfiles) { profile in
                                                Text(profile.name).tag(profile.id)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - Battery Section
    private var batterySection: some View {
        cardView(title: "Battery Health & Power", icon: "battery.100", color: .green) {
            VStack(alignment: .leading, spacing: 12) {
                if !sensors.batteryInfo.isPresent {
                    VStack(spacing: 8) {
                        Image(systemName: "bolt.batteryblock.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No battery installed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Desktop macOS systems (Mac Studio, Mac mini, Mac Pro, iMac) operate on AC power directly.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sensors.batteryInfo.isCharging ? "Charging" : "Current Charge")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f%%", sensors.batteryInfo.chargePercentage ?? 0))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        if let health = sensors.batteryInfo.healthPercentage {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Health (Max Cap)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f%%", health))
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                            }
                        }
                    }
                    
                    Divider()
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        if let cycles = sensors.batteryInfo.cycleCount {
                            statBox(label: "Cycles", val: "\(cycles)")
                        }
                        if let temp = sensors.batteryInfo.temperature {
                            statBox(label: "Temperature", val: settings.formatTemperature(temp))
                        }
                        if let v = sensors.batteryInfo.voltage {
                            statBox(label: "Voltage", val: String(format: "%.2f V", v))
                        }
                        if let w = sensors.batteryInfo.wattage {
                            statBox(label: "Wattage", val: String(format: "%.2f W", w))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Network Section
    private var networkSection: some View {
        cardView(title: "Network Throughput", icon: "network", color: .indigo) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Download Rate", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(formatSpeed(sensors.networkStats.downloadBytesPerSec))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Label("Upload Rate", systemImage: "arrow.up.circle.fill")
                            .font(.caption)
                            .foregroundColor(.indigo)
                        Text(formatSpeed(sensors.networkStats.uploadBytesPerSec))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                }
                
                Divider()
                
                Text("Represents live active interface traffic delta (excluding local loopback).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Helpers
    private func cardView<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.headline)
                Spacer()
            }
            
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
    }
    
    private func statBox(label: String, val: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(val)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576.0 {
            return String(format: "%.2f MB/s", bytesPerSec / 1_048_576.0)
        } else if bytesPerSec >= 1024.0 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024.0)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }
}
