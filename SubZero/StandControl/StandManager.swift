import Foundation
import Combine
import CoreBluetooth

// MARK: - Pure, unit-testable status frame parser

/// Parses ESP32 status frames: `ST,<cooling 0|1>,<onForSeconds>,<rampReady 0|1>,<uptimeSeconds>`
public struct StandStatusFrame: Equatable {
    public let isCooling: Bool
    public let onForSeconds: Int
    public let rampReady: Bool
    public let uptimeSeconds: Int

    public init(isCooling: Bool, onForSeconds: Int, rampReady: Bool, uptimeSeconds: Int) {
        self.isCooling = isCooling
        self.onForSeconds = onForSeconds
        self.rampReady = rampReady
        self.uptimeSeconds = uptimeSeconds
    }

    /// Pure parser: returns nil for malformed input instead of guessing.
    public static func parse(_ raw: String) -> StandStatusFrame? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ",").map(String.init)
        guard parts.count >= 5, parts[0] == "ST" else { return nil }

        guard let cooling = Int(parts[1]), cooling == 0 || cooling == 1,
              let onFor = Int(parts[2]), onFor >= 0,
              let ramp = Int(parts[3]), ramp == 0 || ramp == 1,
              let uptime = Int(parts[4]), uptime >= 0 else { return nil }

        return StandStatusFrame(
            isCooling: cooling == 1,
            onForSeconds: onFor,
            rampReady: ramp == 1,
            uptimeSeconds: uptime
        )
    }
}

// MARK: - Pure, unit-testable autopilot decision

/// Hysteresis rule from the stand contract:
/// - Cooling OFF: turn ON when `maxTemp >= cutoff`.
/// - Cooling ON: turn OFF when `maxTemp <= cutoff - hysteresis` (default 5 °C).
/// - Between the two thresholds: no change (no flapping).
/// - Nil temperature (no sensor data): never act.
public struct CoolingPilot {
    public enum Decision: Equatable {
        case none
        case turnOn
        case turnOff
    }

    public init() {}

    public static func decide(
        maxTemp: Double?,
        cutoff: Double,
        hysteresis: Double = 5.0,
        coolingOn: Bool
    ) -> Decision {
        guard let temp = maxTemp else { return .none }
        if coolingOn {
            return temp <= cutoff - hysteresis ? .turnOff : .none
        } else {
            return temp >= cutoff ? .turnOn : .none
        }
    }
}

// MARK: - Connection state

public enum StandConnectionState: String {
    case disconnected
    case scanning
    case connecting
    case connected
}

// MARK: - StandManager (BLE central + autopilot)

/// Owns the CoreBluetooth central link to the "SubZero Stand" ESP32 peripheral.
/// All mutable state is MainActor-isolated; CoreBluetooth delegate callbacks arrive
/// on a private background queue and hop to the MainActor before touching state.
///
/// Integration (no circular dependency): FirebaseManager sets `onStatusChanged`
/// to push status into Firestore, and calls `sendManual`/`setAuto` when a
/// `standCommand` arrives from the phone.
@MainActor
public final class StandManager: NSObject, ObservableObject {

    public static let shared = StandManager()

    // MARK: Published state

    @Published public private(set) var connectionState: StandConnectionState = .disconnected
    @Published public private(set) var isCooling: Bool = false
    @Published public private(set) var lastHeartbeatAt: Date?
    @Published public private(set) var onForSeconds: Int = 0
    @Published public private(set) var rampReady: Bool = false
    @Published public private(set) var standName: String?
    @Published public private(set) var isAutoEnabled: Bool = false
    @Published public private(set) var cutoffTemp: Double = 70.0

    /// Seconds until the peltier reaches optimal temperature (contract: 300 s ramp).
    public var secondsToOptimal: Int {
        guard isCooling, !rampReady else { return 0 }
        return max(0, Self.rampTargetSeconds - onForSeconds)
    }

    /// Contract: standConnected = BLE link up AND heartbeat fresh (<= 15 s old).
    public var isHeartbeatFresh: Bool {
        guard connectionState == .connected, let last = lastHeartbeatAt else { return false }
        return Date().timeIntervalSince(last) <= Self.heartbeatTimeout
    }

    // MARK: Integration hooks

    /// Set by FirebaseManager; invoked on every state change / heartbeat refresh.
    public var onStatusChanged: (() -> Void)?

    // MARK: BLE constants (from the stand contract)

    private static let peripheralName = "SubZero Stand"
    private static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let rxUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let txUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let rampTargetSeconds = 300
    private static let heartbeatTimeout: TimeInterval = 15
    private static let connectTimeout: TimeInterval = 12
    private static let watchdogInterval: TimeInterval = 2

    // MARK: Private state

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var pump: BLEPump?
    private var watchdogTimer: Timer?
    private var connectStartedAt: Date?
    private var desiredCooling: Bool?
    private var started = false
    private var cancellables = Set<AnyCancellable>()
    /// Suppresses a Firestore write while applying settings that arrived FROM Firestore.
    private var suppressSettingsPublish = false

    private let bleQueue = DispatchQueue(label: "com.subzero.stand.ble")

    private override init() {
        super.init()
        syncSettingsFromStorage()
        observeAppSettings()
    }

    // MARK: Lifecycle

    /// Starts scanning and the heartbeat watchdog. Safe to call more than once; runs exactly once.
    public func start() {
        guard !started else { return }
        started = true

        let delegate = BLEPump(owner: self, queue: bleQueue)
        pump = delegate
        let central = CBCentralManager(delegate: delegate, queue: bleQueue)
        self.central = central

        watchdogTimer = Timer.scheduledTimer(
            withTimeInterval: Self.watchdogInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.watchdogTick() }
        }
        if let timer = watchdogTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        observeSensorTemps()

        if central.state == .poweredOn {
            restartScan()
        }
        notifyStatusChanged()
    }

    // MARK: Public commands

    /// Manual cool on/off (Mac UI or relayed phone command). Ignored while not connected.
    public func sendManual(_ on: Bool) {
        guard connectionState == .connected, central?.state == .poweredOn else { return }
        desiredCooling = on
        writeCommand(on ? "COOL_ON\n" : "COOL_OFF\n")
        // Optimistic update; corrected by the next heartbeat frame.
        isCooling = on
        if !on {
            onForSeconds = 0
            rampReady = false
        }
        notifyStatusChanged()
    }

    /// Auto-pilot mode. Persists via AppSettings and re-evaluates immediately.
    public func setAuto(_ enabled: Bool) {
        if AppSettings.shared.standAutoEnabled != enabled {
            AppSettings.shared.standAutoEnabled = enabled
        }
        syncSettingsFromStorage()
        if enabled {
            evaluateAutoPilot()
        }
        notifyStatusChanged()
    }

    /// Cutoff temperature in °C. Persists via AppSettings and re-evaluates if auto.
    public func setCutoff(_ celsius: Double) {
        if AppSettings.shared.standCutoffTemp != celsius {
            AppSettings.shared.standCutoffTemp = celsius
        }
        syncSettingsFromStorage()
        if isAutoEnabled {
            evaluateAutoPilot()
        }
        notifyStatusChanged()
    }

    /// Applies settings that arrived from the phone. Applies only when different
    /// (equality guard) and does NOT trigger a Firestore write-back on apply;
    /// the applied values are persisted with the next throttled heartbeat refresh.
    public func applyRemoteSettings(autoEnabled: Bool, cutoff: Double) {
        suppressSettingsPublish = true
        defer { suppressSettingsPublish = false }

        if AppSettings.shared.standAutoEnabled != autoEnabled {
            AppSettings.shared.standAutoEnabled = autoEnabled
        }
        if AppSettings.shared.standCutoffTemp != cutoff {
            AppSettings.shared.standCutoffTemp = cutoff
        }
        syncSettingsFromStorage()

        if isAutoEnabled {
            evaluateAutoPilot()
        }
    }

    // MARK: Autopilot

    private func observeSensorTemps() {
        // @Published fires willSet; hop to the next MainActor turn so the new
        // temperature values are visible when the pilot runs.
        SensorManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.evaluateAutoPilot() }
            }
            .store(in: &cancellables)
    }

    private func evaluateAutoPilot() {
        guard started, isAutoEnabled, connectionState == .connected else { return }
        let cpu = SensorManager.shared.cpuTemp
        let gpu = SensorManager.shared.gpuTemp
        let maxTemp: Double?
        switch (cpu, gpu) {
        case let (c?, g?): maxTemp = max(c, g)
        case let (c?, nil): maxTemp = c
        case let (nil, g?): maxTemp = g
        default: maxTemp = nil
        }

        let decision = CoolingPilot.decide(
            maxTemp: maxTemp,
            cutoff: cutoffTemp,
            hysteresis: 5.0,
            coolingOn: desiredCooling ?? isCooling
        )

        switch decision {
        case .none:
            break
        case .turnOn:
            if desiredCooling != true {
                sendManual(true)
            }
        case .turnOff:
            if desiredCooling != false {
                sendManual(false)
            }
        }
    }

    // MARK: Settings sync (AppSettings <-> published state)

    private func observeAppSettings() {
        AppSettings.shared.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.syncSettingsFromStorage() }
            }
            .store(in: &cancellables)
    }

    private func syncSettingsFromStorage() {
        let auto = AppSettings.shared.standAutoEnabled
        let cutoff = AppSettings.shared.standCutoffTemp
        let changed = auto != isAutoEnabled || cutoff != cutoffTemp
        isAutoEnabled = auto
        cutoffTemp = cutoff
        if changed && !suppressSettingsPublish {
            notifyStatusChanged()
        }
    }

    // MARK: Watchdog

    private func watchdogTick() {
        switch connectionState {
        case .connected:
            if let last = lastHeartbeatAt, Date().timeIntervalSince(last) > Self.heartbeatTimeout {
                handleLinkDead()
            }
        case .connecting:
            if let start = connectStartedAt, Date().timeIntervalSince(start) > Self.connectTimeout {
                handleConnectTimeout()
            }
        default:
            break
        }
    }

    private func handleLinkDead() {
        if let peripheral = peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        tearDownLink(publishState: .disconnected)
        restartScan()
    }

    /// Peripheral dropped (ESP32 failsafe turned cooling OFF); reconnect loop restarts.
    private func handleDisconnected() {
        tearDownLink(publishState: .disconnected)
        restartScan()
    }

    private func handleConnectTimeout() {
        if let peripheral = peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        tearDownLink(publishState: .disconnected)
        restartScan()
    }

    private func tearDownLink(publishState newState: StandConnectionState) {
        peripheral = nil
        rxCharacteristic = nil
        connectionState = newState
        notifyStatusChanged()
    }

    // MARK: Scanning / reconnect

    private func restartScan() {
        guard let central, central.state == .poweredOn else { return }
        central.stopScan()
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        connectionState = .scanning
        notifyStatusChanged()
    }

    // MARK: BLE write path (manual commands and autopilot decisions both go through here)

    private func writeCommand(_ command: String) {
        guard let rx = rxCharacteristic, let data = command.data(using: .utf8) else { return }
        peripheral?.writeValue(data, for: rx, type: .withResponse)
    }

    /// On (re)connect, resync the state the Mac wants — the ESP32 failsafe
    /// turned cooling OFF on disconnect.
    private func resyncDesiredState() {
        if let desired = desiredCooling {
            writeCommand(desired ? "COOL_ON\n" : "COOL_OFF\n")
        }
        writeCommand("STATUS?\n")
    }

    private func notifyStatusChanged() {
        onStatusChanged?()
    }

    // MARK: MainActor handlers for BLE events (hopped from the BLE queue)

    private func handleCentralState(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            restartScan()
        case .poweredOff, .unauthorized, .unsupported:
            tearDownLink(publishState: .disconnected)
        default:
            break
        }
    }

    private func handleDiscovered(_ discovered: CBPeripheral, name: String?) {
        guard connectionState != .connected, connectionState != .connecting else { return }
        guard name == Self.peripheralName || discovered.name == Self.peripheralName else { return }

        peripheral = discovered
        standName = discovered.name ?? name
        discovered.delegate = pump
        central?.stopScan()
        connectionState = .connecting
        connectStartedAt = Date()
        central?.connect(discovered, options: nil)
        notifyStatusChanged()
    }

    private func handleConnected() {
        connectionState = .connecting
        connectStartedAt = Date()
        peripheral?.discoverServices([Self.serviceUUID])
        notifyStatusChanged()
    }

    private func handleServicesDiscovered() {
        guard let service = peripheral?.services?.first(where: { $0.uuid == Self.serviceUUID })
                ?? peripheral?.services?.first else { return }
        peripheral?.discoverCharacteristics([Self.rxUUID, Self.txUUID], for: service)
    }

    private func handleCharacteristicsDiscovered(service: CBService) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.rxUUID {
                rxCharacteristic = characteristic
            } else if characteristic.uuid == Self.txUUID {
                peripheral?.setNotifyValue(true, for: characteristic)
            }
        }
    }

    private func handleNotificationState(characteristic: CBCharacteristic) {
        guard characteristic.uuid == Self.txUUID, characteristic.isNotifying else { return }
        // Subscribe complete: link is up. Treat now as a fresh heartbeat so the
        // watchdog has a full window before judging the link.
        lastHeartbeatAt = Date()
        connectionState = .connected
        resyncDesiredState()
        notifyStatusChanged()
    }

    private func handleFrameData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            guard let frame = StandStatusFrame.parse(String(line)) else { continue }
            lastHeartbeatAt = Date()
            isCooling = frame.isCooling
            onForSeconds = frame.onForSeconds
            rampReady = frame.rampReady
            notifyStatusChanged()
        }
    }

    /// Nonisolated delegate pump; hops every callback onto the MainActor.
    private final class BLEPump: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        weak var owner: StandManager?
        private let queue: DispatchQueue

        init(owner: StandManager, queue: DispatchQueue) {
            self.owner = owner
            self.queue = queue
            super.init()
        }

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            let state = central.state
            Task { @MainActor [weak self] in self?.owner?.handleCentralState(state) }
        }

        func centralManager(_ central: CBCentralManager,
                            didDiscover peripheral: CBPeripheral,
                            advertisementData: [String: Any],
                            rssi RSSI: NSNumber) {
            let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            Task { @MainActor [weak self] in
                self?.owner?.handleDiscovered(peripheral, name: localName)
            }
        }

        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            Task { @MainActor [weak self] in self?.owner?.handleConnected() }
        }

        func centralManager(_ central: CBCentralManager,
                            didFailToConnect peripheral: CBPeripheral,
                            error: Error?) {
            Task { @MainActor [weak self] in self?.owner?.connectDidFail() }
        }

        func centralManager(_ central: CBCentralManager,
                            didDisconnectPeripheral peripheral: CBPeripheral,
                            error: Error?) {
            Task { @MainActor [weak self] in self?.owner?.handleDisconnected() }
        }

        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            Task { @MainActor [weak self] in self?.owner?.handleServicesDiscovered() }
        }

        func peripheral(_ peripheral: CBPeripheral,
                        didDiscoverCharacteristicsFor service: CBService,
                        error: Error?) {
            Task { @MainActor [weak self] in
                self?.owner?.handleCharacteristicsDiscovered(service: service)
            }
        }

        func peripheral(_ peripheral: CBPeripheral,
                        didUpdateNotificationStateFor characteristic: CBCharacteristic,
                        error: Error?) {
            Task { @MainActor [weak self] in
                self?.owner?.handleNotificationState(characteristic: characteristic)
            }
        }

        func peripheral(_ peripheral: CBPeripheral,
                        didUpdateValueFor characteristic: CBCharacteristic,
                        error: Error?) {
            let data = characteristic.value
            Task { @MainActor [weak self] in
                self?.owner?.handleFrameData(data ?? Data())
            }
        }
    }

    private func connectDidFail() {
        tearDownLink(publishState: .disconnected)
        restartScan()
    }
}
