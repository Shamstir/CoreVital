import SwiftUI

struct CloudSyncSettingsView: View {
    @ObservedObject private var firebase = FirebaseManager.shared
    @ObservedObject private var fanControl = FanControlManager.shared
    @State private var showingSyncAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Firebase Cloud Sync & Backup")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            Text("Connect SubZero to Google Firebase to securely back up custom fan cooling curves, sync profiles across Macs, and store telemetry.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            if !firebase.isConfigured {
                unconfiguredView
            } else {
                configuredSyncView
            }

            Spacer()
        }
        .padding(16)
        .alert(isPresented: $showingSyncAlert) {
            Alert(title: Text("Cloud Sync"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(firebase.isConfigured ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(firebase.status.rawValue)
                .font(.caption.bold())
                .foregroundColor(firebase.isConfigured ? .green : .orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    private var unconfiguredView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Firebase Setup Required")
                        .font(.subheadline.bold())
                    Text("To activate cloud synchronization, create a project at console.firebase.google.com, register com.subzero.app, and replace GoogleService-Info.plist.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(8)

            Button(action: {
                if let url = URL(string: "https://console.firebase.google.com/") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Label("Open Firebase Console", systemImage: "arrow.up.right.square")
            }
            .controlSize(.small)

            Text("Status: \(firebase.statusMessage)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var configuredSyncView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                if let uid = firebase.currentUserId {
                    HStack {
                        Text("Cloud Account UID:")
                            .font(.caption.bold())
                        Text(uid)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                if let lastSync = firebase.lastSyncTime {
                    HStack {
                        Text("Last Sync:")
                            .font(.caption.bold())
                        Text(lastSync.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(6)

            HStack(spacing: 12) {
                Button(action: backupCurves) {
                    if firebase.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Backup Curves to Cloud", systemImage: "icloud.and.arrow.up")
                    }
                }
                .disabled(firebase.isSyncing)

                Button(action: restoreCurves) {
                    Label("Restore Curves from Cloud", systemImage: "icloud.and.arrow.down")
                }
                .disabled(firebase.isSyncing)
            }

            Toggle("Auto-Sync Hardware Telemetry Snapshots", isOn: $firebase.isAutoTelemetrySyncEnabled)
                .font(.subheadline)
                .padding(.top, 4)

            Text("Status: \(firebase.statusMessage)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func backupCurves() {
        Task {
            let success = await firebase.syncCurvesToCloud(profiles: fanControl.availableCurveProfiles)
            if success {
                alertMessage = "Successfully backed up \(fanControl.availableCurveProfiles.count) fan curves to Firebase!"
            } else {
                alertMessage = firebase.lastError ?? "Backup failed."
            }
            showingSyncAlert = true
        }
    }

    private func restoreCurves() {
        Task {
            if let profiles = await firebase.fetchCurvesFromCloud() {
                fanControl.availableCurveProfiles = profiles
                alertMessage = "Successfully restored \(profiles.count) fan curves from Firebase Cloud!"
            } else {
                alertMessage = firebase.lastError ?? "No curves found in cloud."
            }
            showingSyncAlert = true
        }
    }
}
