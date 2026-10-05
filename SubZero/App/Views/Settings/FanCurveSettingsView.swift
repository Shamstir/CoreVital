import SwiftUI

struct FanCurveSettingsView: View {
    @ObservedObject private var fanControl = FanControlManager.shared
    @State private var selectedProfileID: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Temperature vs RPM Cooling Curves")
                    .font(.headline)
                Spacer()
                Button(action: createNewProfile) {
                    Label("Add Profile", systemImage: "plus")
                }
            }
            
            Text("Define how fast fans should spin at specific CPU/GPU temperatures when in Custom Curve mode. Temperatures are evaluated in °C.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HSplitView {
                // Profile list
                List(selection: $selectedProfileID) {
                    ForEach(fanControl.availableCurveProfiles) { profile in
                        Text(profile.name)
                            .tag(profile.id)
                    }
                }
                .frame(minWidth: 160, maxWidth: 220)
                
                // Profile details editor
                if let selectedID = selectedProfileID ?? fanControl.availableCurveProfiles.first?.id,
                   let index = fanControl.availableCurveProfiles.firstIndex(where: { $0.id == selectedID }) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Profile Name:")
                                .font(.subheadline.bold())
                            TextField("Name", text: $fanControl.availableCurveProfiles[index].name)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Divider()
                        
                        Text("Curve Points (Temperature → Target RPM)")
                            .font(.subheadline.bold())
                        
                        ForEach(Array(fanControl.availableCurveProfiles[index].points.enumerated()), id: \.element.id) { pointIndex, _ in
                            HStack(spacing: 12) {
                                Text("Temp (°C):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Slider(value: $fanControl.availableCurveProfiles[index].points[pointIndex].temperature, in: 30...90, step: 5)
                                    .frame(width: 100)
                                
                                Text(String(format: "%.0f°C", fanControl.availableCurveProfiles[index].points[pointIndex].temperature))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 40)
                                
                                Text("Speed:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Slider(value: $fanControl.availableCurveProfiles[index].points[pointIndex].targetRPM, in: 1500...6550, step: 100)
                                    .frame(width: 120)
                                
                                Text(String(format: "%.0f RPM", fanControl.availableCurveProfiles[index].points[pointIndex].targetRPM))
                                    .font(.caption.bold().monospacedDigit())
                                    .frame(width: 65, alignment: .trailing)
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                } else {
                    Text("Select or add a profile to configure curve points.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding()
        .onAppear {
            if selectedProfileID == nil {
                selectedProfileID = fanControl.availableCurveProfiles.first?.id
            }
        }
    }
    
    private func createNewProfile() {
        let newProfile = FanCurveProfile(name: "Custom Profile", points: [
            FanCurvePoint(temperature: 45, targetRPM: 2317),
            FanCurvePoint(temperature: 65, targetRPM: 3800),
            FanCurvePoint(temperature: 85, targetRPM: 6550)
        ])
        fanControl.availableCurveProfiles.append(newProfile)
        selectedProfileID = newProfile.id
    }
}
