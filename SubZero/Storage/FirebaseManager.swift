import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

public enum FirebaseConnectionStatus: String {
    case notConfigured = "Configuration File Missing"
    case configured = "Connected"
    case error = "Initialization Error"
}

@MainActor
public final class FirebaseManager: ObservableObject {
    public static let shared = FirebaseManager()

    @Published public var status: FirebaseConnectionStatus = .notConfigured
    @Published public var isConfigured: Bool = false
    @Published public var currentUserId: String? = nil
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncTime: Date? = nil
    @Published public var statusMessage: String = "Ready"
    @Published public var lastError: String? = nil
    @Published public var isAutoTelemetrySyncEnabled: Bool = true
    @Published public var thermalAlertThreshold: Double = 85.0
    @Published public var lastPublishedTimestamp: Date? = nil

    private var db: Firestore?
    private var commandListener: ListenerRegistration?
    public let deviceId: String = {
        // Unique hardware UUID or device host name fallback
        if let uuid = getHardwareUUID() {
            return uuid
        }
        return Host.current().localizedName?.replacingOccurrences(of: " ", with: "-").lowercased() ?? "macbook"
    }()

    private init() {}

    public func configure() {
        guard !isConfigured else { return }

        // Check if GoogleService-Info.plist exists and contains non-empty credentials
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              let apiKey = options.apiKey, !apiKey.isEmpty, !apiKey.contains("Placeholder"),
              let projectID = options.projectID, !projectID.isEmpty else {
            self.status = .notConfigured
            self.statusMessage = "Replace GoogleService-Info.plist with your project's credentials to enable cloud features."
            print("[SubZero Firebase] Notice: GoogleService-Info.plist is using template/placeholder values. Connect your real Firebase project to enable live cloud sync.")
            return
        }

        do {
            if FirebaseApp.app() == nil {
                FirebaseApp.configure(options: options)
            }
            self.db = Firestore.firestore()
            self.isConfigured = true
            self.status = .configured
            self.statusMessage = "Connected to Firebase (\(options.projectID ?? ""))."
            print("[SubZero Firebase] Initialized successfully with project: \(options.projectID ?? "")")
            
            // Authenticate anonymously for cloud storage
            authenticateAnonymously()
            startListeningToRemoteCommands()
        } catch {
            self.status = .error
            self.lastError = error.localizedDescription
            self.statusMessage = "Error: \(error.localizedDescription)"
            print("[SubZero Firebase] Initialization error: \(error)")
        }
    }

    public func authenticateAnonymously() {
        guard isConfigured else { return }
        if let user = Auth.auth().currentUser {
            self.currentUserId = user.uid
            return
        }

        Auth.auth().signInAnonymously { [weak self] authResult, error in
            Task { @MainActor in
                if let error = error {
                    self?.lastError = error.localizedDescription
                    print("[SubZero Firebase] Auth error: \(error)")
                } else if let user = authResult?.user {
                    self?.currentUserId = user.uid
                    print("[SubZero Firebase] Signed in anonymously with UID: \(user.uid)")
                }
            }
        }
    }

    // MARK: - Live Telemetry Streamer for Android Companion
    public func publishLiveTelemetry(
        cpuTemp: Double?,
        gpuTemp: Double?,
        cpuLoad: CPULoad,
        memoryStats: MemoryStats,
        fanSpeeds: [FanReading],
        batteryInfo: BatteryInfo,
        powerReadings: PowerReadings?,
        thermalState: ProcessInfo.ThermalState,
        chipName: String
    ) {
        guard isConfigured, let db = db else { return }

        let effectiveCPUTemp = cpuTemp ?? 0.0
        let effectiveGPUTemp = gpuTemp ?? 0.0
        let maxTemp = max(effectiveCPUTemp, effectiveGPUTemp)
        let isOverheating = maxTemp >= thermalAlertThreshold

        let fanData = fanSpeeds.map { [
            "name": $0.name,
            "currentRPM": $0.currentRPM,
            "minRPM": $0.minRPM,
            "maxRPM": $0.maxRPM
        ] }

        var thermalStateString = "Nominal"
        switch thermalState {
        case .nominal: thermalStateString = "Nominal"
        case .fair: thermalStateString = "Fair"
        case .serious: thermalStateString = "Serious"
        case .critical: thermalStateString = "Critical"
        @unknown default: thermalStateString = "Unknown"
        }

        let payload: [String: Any] = [
            "deviceId": deviceId,
            "deviceName": Host.current().localizedName ?? "MacBook",
            "chipName": chipName,
            "cpuTemp": effectiveCPUTemp,
            "gpuTemp": effectiveGPUTemp,
            "maxTemp": maxTemp,
            "cpuLoad": cpuLoad.totalLoad,
            "pCoreLoad": cpuLoad.pCoreLoad,
            "eCoreLoad": cpuLoad.eCoreLoad,
            "memoryPressure": memoryStats.pressurePercentage,
            "memoryUsedBytes": memoryStats.usedBytes,
            "memoryTotalBytes": memoryStats.totalBytes,
            "fanSpeeds": fanData,
            "batteryPct": batteryInfo.chargePercentage ?? 0.0,
            "isCharging": batteryInfo.isCharging,
            "packageWatts": powerReadings?.totalPackageWatts ?? 0.0,
            "thermalState": thermalStateString,
            "updatedAt": FieldValue.serverTimestamp(),
            "alertThreshold": thermalAlertThreshold,
            "alertTriggered": isOverheating,
            "alertMessage": isOverheating ? String(format: "High Thermal Alert: %.1f°C exceeds %.0f°C limit!", maxTemp, thermalAlertThreshold) : ""
        ]

        // Update active device document in Firestore
        print("[SubZero Firebase] 📡 Broadcasting telemetry for device '\(deviceId)' to Firestore /devices/\(deviceId)...")
        db.collection("devices").document(deviceId).setData(payload, merge: true) { [weak self] error in
            if let error = error {
                print("[SubZero Firebase] ❌ Firestore publish error: \(error.localizedDescription)")
            } else {
                print("[SubZero Firebase] ✅ Telemetry successfully written to Firestore (/devices/\(self?.deviceId ?? ""))")
                Task { @MainActor in
                    self?.lastPublishedTimestamp = Date()
                }
            }
        }
    }

    // MARK: - Demo Trigger Alert to Phone
    public func triggerRemoteDemoAlert() {
        guard isConfigured, let db = db else {
            print("[SubZero Firebase] Cannot trigger demo alert: Firebase is not configured.")
            return
        }
        
        let demoPayload: [String: Any] = [
            "alertTriggered": true,
            "alertMessage": "🔥 [DEMO ALERT] Critical Mac Temperature (92.5°C) Simulated!",
            "maxTemp": 92.5,
            "cpuTemp": 92.5,
            "gpuTemp": 89.0,
            "thermalState": "Critical",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        print("[SubZero Firebase] 🚨 Triggering live thermal alert on remote Android device...")
        db.collection("devices").document(deviceId).setData(demoPayload, merge: true) { error in
            if let error = error {
                print("[SubZero Firebase] ❌ Demo alert error: \(error.localizedDescription)")
            } else {
                print("[SubZero Firebase] ✅ Demo alert successfully sent to Android phone!")
            }
        }
    }

    // MARK: - Remote Commands (From Android App)
    private func startListeningToRemoteCommands() {
        guard let db = db else { return }
        commandListener?.remove()

        commandListener = db.collection("devices").document(deviceId).collection("commands")
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .addSnapshotListener { snapshot, error in
                guard let doc = snapshot?.documents.first, error == nil else { return }
                let data = doc.data()
                guard let isExecuted = data["executed"] as? Bool, !isExecuted,
                      let action = data["action"] as? String else { return }

                Task { @MainActor in
                    print("[SubZero Firebase] Received remote command from Android: \(action)")
                    if action == "setFanMax" {
                        FanControlManager.shared.setAllFansToFullManual()
                    } else if action == "setFanAuto" {
                        FanControlManager.shared.resetAllFansToAuto()
                    }
                    // Mark command as executed
                    doc.reference.updateData(["executed": true, "executedAt": FieldValue.serverTimestamp()])
                }
            }
    }

    // MARK: - Fan Curves Cloud Sync
    public func syncCurvesToCloud(profiles: [FanCurveProfile]) async -> Bool {
        guard isConfigured, let db = db, let uid = currentUserId ?? Auth.auth().currentUser?.uid else {
            self.lastError = "Firebase is not configured or user is not authenticated."
            return false
        }

        self.isSyncing = true
        defer { self.isSyncing = false }

        do {
            let data = try JSONEncoder().encode(profiles)
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            
            try await db.collection("users").document(uid).setData([
                "fan_curves": jsonObject,
                "updated_at": FieldValue.serverTimestamp(),
                "device_name": Host.current().localizedName ?? "Mac"
            ], merge: true)

            self.lastSyncTime = Date()
            self.statusMessage = "Synced \(profiles.count) curves to cloud."
            self.lastError = nil
            return true
        } catch {
            self.lastError = "Sync failed: \(error.localizedDescription)"
            self.statusMessage = "Sync failed: \(error.localizedDescription)"
            return false
        }
    }

    public func fetchCurvesFromCloud() async -> [FanCurveProfile]? {
        guard isConfigured, let db = db, let uid = currentUserId ?? Auth.auth().currentUser?.uid else {
            self.lastError = "Firebase is not configured."
            return nil
        }

        self.isSyncing = true
        defer { self.isSyncing = false }

        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            guard let data = doc.data(), let rawCurves = data["fan_curves"] else {
                self.statusMessage = "No cloud curves found for this account."
                return nil
            }

            let jsonData = try JSONSerialization.data(withJSONObject: rawCurves, options: [])
            let profiles = try JSONDecoder().decode([FanCurveProfile].self, from: jsonData)
            self.lastSyncTime = Date()
            self.statusMessage = "Fetched \(profiles.count) curves from cloud."
            self.lastError = nil
            return profiles
        } catch {
            self.lastError = "Fetch failed: \(error.localizedDescription)"
            return nil
        }
    }

    private static func getHardwareUUID() -> String? {
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        let platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, matching)
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        if let serial = IORegistryEntryCreateCFProperty(platformExpert, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return serial.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
