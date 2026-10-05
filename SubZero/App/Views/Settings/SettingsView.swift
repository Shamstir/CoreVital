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
