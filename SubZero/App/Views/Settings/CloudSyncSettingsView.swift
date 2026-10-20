import SwiftUI

struct CloudSyncSettingsView: View {
    @ObservedObject private var firebase = FirebaseManager.shared
    @ObservedObject private var pairing = PairingManager.shared
    @ObservedObject private var fanControl = FanControlManager.shared

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSignUpMode = false
    @State private var authErrorMessage: String? = nil

    @State private var showingSyncAlert = false
    @State private var alertMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Firebase Cloud Sync & Account")
                            .font(.headline)
                        Text("Pair this Mac with your Android companion app using the same email address.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    statusBadge
                }

                Divider()

                pairingSection

                Divider()

                if !firebase.isConfigured {
                    unconfiguredView
                } else {
                    configuredAccountSection
                    Divider()
                    backupAndTelemetrySection
                }

                Spacer(minLength: 10)
            }
            .padding(16)
        }
        .alert(isPresented: $showingSyncAlert) {
            Alert(title: Text("Cloud Sync"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ANDROID PUSH NOTIFICATION PAIRING")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text("Pair this Mac with the Android app. No email or Keychain sign-in is required on this Mac.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let code = pairing.pairingCode, !pairing.isPaired {
                Text(code)
                    .font(.title.monospaced().bold())
                    .tracking(2)
                    .textSelection(.enabled)
                Text("In Android, open Settings → Pair Mac, then enter this code.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Cancel Pairing") { pairing.cancelPairing() }
                    .controlSize(.small)
            } else if pairing.isPaired {
                Label(pairing.statusMessage, systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Button("Unpair This Mac") { pairing.cancelPairing() }
                    .controlSize(.small)
            } else {
                Button("Generate Pairing Code") {
                    pairing.beginPairing(deviceId: firebase.deviceId, deviceName: Host.current().localizedName ?? "Mac")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!pairing.isConfigured)
                if !pairing.isConfigured {
                    Text("Deploy the Cloudflare Worker and set SUBZERO_PAIRING_WORKER_URL in this target's Info.plist.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            Text(pairing.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            if let error = pairing.lastError {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(firebase.isConfigured ? (firebase.isAuthenticatedWithEmail ? Color.green : Color.blue) : Color.orange)
                .frame(width: 8, height: 8)
            Text(firebase.isAuthenticatedWithEmail ? "Linked" : (firebase.isConfigured ? "Connected" : firebase.status.rawValue))
                .font(.caption.bold())
                .foregroundColor(firebase.isConfigured ? (firebase.isAuthenticatedWithEmail ? .green : .blue) : .orange)
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

    // MARK: - Email / Password Account Section
    private var configuredAccountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNT & SYNC PAIRING")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            if firebase.isAuthenticatedWithEmail, let currentEmail = firebase.currentUserEmail {
                // Logged in state
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 24))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed In as")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(currentEmail)
                                .font(.subheadline.bold())
                        }

                        Spacer()

                        Button(role: .destructive, action: handleSignOut) {
                            Text("Sign Out")
                        }
                        .controlSize(.small)
                    }

                    if let uid = firebase.currentUserId {
                        HStack(spacing: 4) {
                            Text("UID:")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                            Text(uid)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("Live telemetry is linked to \(currentEmail). The Android app logged into this account will automatically stream this Mac's hardware.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(6)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)

            } else {
                // Unauthenticated / Anonymous state -> Show Sign In / Sign Up form
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "link.badge.plus")
                            .foregroundColor(.blue)
                        Text("Sign in with the same email as your Android companion app to stream hardware metrics and thermal alerts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(6)

                    Picker("", selection: $isSignUpMode) {
                        Text("Sign In").tag(false)
                        Text("Create Account").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Email Address", text: $email)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)

                        if isSignUpMode {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let err = authErrorMessage ?? firebase.authErrorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    HStack {
                        Button(action: handleAuthSubmit) {
                            if firebase.isAuthLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(isSignUpMode ? "Create Account & Link" : "Sign In & Link")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(firebase.isAuthLoading || email.isEmpty || password.isEmpty)

                        Spacer()
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Backup and Telemetry Controls
    private var backupAndTelemetrySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DATA TRANSPORT & BACKUP")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            if let lastSync = firebase.lastSyncTime {
                HStack {
                    Text("Last Cloud Sync:")
                        .font(.caption.bold())
                    Text(lastSync.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

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

            Button(action: {
                PairingManager.shared.triggerTestAlert()
                alertMessage = "Simulated high-temperature push notification sent to Android companion app!"
                showingSyncAlert = true
            }) {
                Label("Trigger Test Alert to Android Phone", systemImage: "bell.badge.fill")
            }
            .buttonStyle(.bordered)

            Text("Status: \(firebase.statusMessage)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func handleAuthSubmit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty || !trimmedEmail.contains("@") {
            authErrorMessage = "Please enter a valid email address."
            return
        }
        if password.count < 6 {
            authErrorMessage = "Password must be at least 6 characters."
            return
        }
        if isSignUpMode && password != confirmPassword {
            authErrorMessage = "Passwords do not match."
            return
        }

        authErrorMessage = nil

        Task {
            do {
                if isSignUpMode {
                    try await firebase.signUp(email: trimmedEmail, password: password)
                } else {
                    try await firebase.signIn(email: trimmedEmail, password: password)
                }
                email = ""
                password = ""
                confirmPassword = ""
            } catch {
                authErrorMessage = error.localizedDescription
            }
        }
    }

    private func handleSignOut() {
        do {
            try firebase.signOut()
        } catch {
            authErrorMessage = error.localizedDescription
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
