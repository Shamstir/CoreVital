import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    
    var body: some View {
        TabView {
            generalSettingsTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            menuBarSettingsTab
                .tabItem {
                    Label("Menu Bar", systemImage: "menubar.dock")
                }
            
            FanCurveSettingsView()
                .tabItem {
                    Label("Cooling & Fans", systemImage: "fanblades.fill")
                }

            standSettingsTab
                .tabItem {
                    Label("Cooling Stand", systemImage: "snowflake")
                }

            CloudSyncSettingsView()
                .tabItem {
                    Label("Cloud Sync", systemImage: "icloud.and.arrow.up")
                }
        }
        .padding(20)
        .frame(width: 580, height: 460)
    }
    
    private var generalSettingsTab: some View {
        Form {
            Section {
                Picker("Polling Interval:", selection: $settings.refreshInterval) {
                    Text("1 Second (Fast)").tag(1.0)
                    Text("2 Seconds (Standard)").tag(2.0)
                    Text("3 Seconds (Balanced)").tag(3.0)
                    Text("5 Seconds (Eco)").tag(5.0)
                    Text("10 Seconds (Low Power)").tag(10.0)
                }
                .pickerStyle(.menu)
                
                Picker("Temperature Unit:", selection: $settings.temperatureUnitRaw) {
                    ForEach(TemperatureUnit.allCases) { u in
                        Text(u.rawValue).tag(u.rawValue)
                    }
                }
                .pickerStyle(.menu)
                
                Toggle("Launch SubZero at Login", isOn: $settings.launchAtLogin)
                    .padding(.top, 8)
            }
            
            Spacer()
            
            Text("SubZero operates outside the App Store with Developer ID notarization and direct hardware sensor access.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var standSettingsTab: some View {
        StandSettingsView()
    }

    private var menuBarSettingsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select up to 4 metrics to display live directly in the macOS menu bar:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            List {
                ForEach(MenuBarMetricType.allCases) { metric in
                    HStack {
                        Image(systemName: metric.iconName)
                            .frame(width: 24)
                            .foregroundColor(.blue)
                        Text(metric.displayName)
                        Spacer()
                        
                        let isSelected = settings.selectedMenuBarMetrics.contains(metric)
                        Toggle("", isOn: Binding(
                            get: { isSelected },
                            set: { newValue in
                                var current = settings.selectedMenuBarMetrics
                                if newValue {
                                    if !current.contains(metric) && current.count < 4 {
                                        current.append(metric)
                                    }
                                } else {
                                    current.removeAll { $0 == metric }
                                }
                                settings.selectedMenuBarMetrics = current
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .disabled(!isSelected && settings.selectedMenuBarMetrics.count >= 4)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.bordered)
            .frame(height: 200)
            
            Text("Currently displaying: \(settings.selectedMenuBarMetrics.count) / 4 metrics")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct StandSettingsView: View {
    @ObservedObject var stand = StandManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Connection:")
                    Spacer()
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 10, height: 10)
                    Text(connectionText)
                        .foregroundColor(.secondary)
                }

                if stand.connectionState == .connected {
                    HStack {
                        Text("Status:")
                        Spacer()
                        Text(runningText)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                HStack {
                    Button("Cooling ON") {
                        StandManager.shared.sendManual(true)
                    }
                    .disabled(!isConnected)

                    Button("Cooling OFF") {
                        StandManager.shared.sendManual(false)
                    }
                    .disabled(!isConnected)
                }

                Toggle("Auto-Pilot (cool automatically above cutoff)", isOn: Binding(
                    get: { stand.isAutoEnabled },
                    set: { StandManager.shared.setAuto($0) }
                ))

                HStack {
                    Text("Cutoff:")
                    Slider(
                        value: Binding(
                            get: { stand.cutoffTemp },
                            set: { StandManager.shared.setCutoff($0) }
                        ),
                        in: 55...90,
                        step: 1
                    )
                    Text(String(format: "%.0f °C", stand.cutoffTemp))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }

                Text("In auto-pilot mode the stand cools when the hottest sensor reaches the cutoff and stops once it falls 5 °C below it.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private var isConnected: Bool {
        stand.connectionState == .connected
    }

    private var connectionColor: Color {
        switch stand.connectionState {
        case .connected: return stand.isHeartbeatFresh ? .green : .orange
        case .scanning, .connecting: return .orange
        case .disconnected: return .gray
        }
    }

    private var connectionText: String {
        switch stand.connectionState {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return stand.isHeartbeatFresh ? "Connected" : "Connected (stale link)"
        }
    }

    private var runningText: String {
        if stand.isCooling {
            return stand.rampReady
                ? "Cooling (optimal temperature)"
                : String(format: "Cooling (optimal in %ds)", stand.secondsToOptimal)
        }
        return "Idle"
    }
}
