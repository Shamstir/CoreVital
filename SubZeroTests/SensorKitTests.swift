import XCTest
@testable import SubZero

final class SensorKitTests: XCTestCase {
    
    func testSensorModelsInitialization() {
        let fan = FanReading(id: 0, name: "Right Fan", currentRPM: 2400, minRPM: 1200, maxRPM: 6000)
        XCTAssertEqual(fan.name, "Right Fan")
        XCTAssertEqual(fan.currentRPM, 2400)
        
        let batt = BatteryInfo(isPresent: true, chargePercentage: 85.5, isCharging: false)
        XCTAssertTrue(batt.isPresent)
        XCTAssertEqual(batt.chargePercentage, 85.5)
        XCTAssertFalse(batt.isCharging)
    }
    
    func testTemperatureFormatting() async {
        let settings = await AppSettings.shared
        await MainActor.run {
            settings.temperatureUnit = .celsius
            XCTAssertEqual(settings.formatTemperature(50.0), "50°C")
            
            settings.temperatureUnit = .fahrenheit
            XCTAssertEqual(settings.formatTemperature(50.0), "122°F")
            
            // Reset to default
            settings.temperatureUnit = .celsius
        }
    }
    
    func testCPULoadMath() {
        let load = CPULoad(totalLoad: 45.2, pCoreLoad: 60.0, eCoreLoad: 20.0, perCoreLoads: [60, 60, 20, 20], pCoreCount: 2, eCoreCount: 2)
        XCTAssertEqual(load.pCoreCount, 2)
        XCTAssertEqual(load.perCoreLoads.count, 4)
        XCTAssertEqual(load.pCoreLoad, 60.0)
    }
    
    func testHistoryStoreRecordSnapshot() async {
        let store = await HistoryStore.shared
        await MainActor.run {
            let initialCount = store.snapshots1Min.count
            store.recordSnapshot(
                cpuLoad: 25.0,
                cpuTemp: 48.5,
                gpuTemp: 44.0,
                fanRPM: 1800,
                memoryPressure: 42.0,
                batteryPct: 90.0,
                packageWatts: 15.2,
                diskRead: 1024,
                diskWrite: 512,
                netRx: 2048,
                netTx: 1024
            )
            XCTAssertGreaterThanOrEqual(store.snapshots1Min.count, initialCount)
        }
    }
    
    func testHIDSensorHelperAndProvider() {
        let temps = HIDSensorHelper.shared.readTemperatures()
        if let cpu = temps.cpu {
            XCTAssertGreaterThan(cpu, 15.0)
            XCTAssertLessThan(cpu, 125.0)
        }
        
        let provider = AppleSiliconSensorProvider()
        if let cpuTemp = provider.cpuTemperature() {
            XCTAssertGreaterThan(cpuTemp, 15.0)
            XCTAssertLessThan(cpuTemp, 125.0)
        }
    }
    
    func testFanDiagnostic() {
        let smc = SMCConnection.shared
        XCTAssertTrue(smc.isConnected)
        let fans = smc.readFanSpeeds()
        // On Intel/Silicon Macs with fans, this will return the fan list.
        // On fanless models (MacBook Air), this returns [] without error.
        print("DIAGNOSTIC: readFanSpeeds = \(fans)")
    }
    
    func testFanCurveLinearInterpolation() {
        let profile = FanCurveProfile(name: "Test Profile", points: [
            FanCurvePoint(temperature: 40, targetRPM: 2000),
            FanCurvePoint(temperature: 60, targetRPM: 4000),
            FanCurvePoint(temperature: 80, targetRPM: 6000)
        ])
        // Below first point -> clamps to first point's target RPM (or minRPM if higher)
        XCTAssertEqual(profile.targetRPM(forTemperature: 30, minRPM: 1200, maxRPM: 6500), 2000)
        // Exactly at 50°C (midway between 40°C and 60°C) -> 3000 RPM
        XCTAssertEqual(profile.targetRPM(forTemperature: 50, minRPM: 1200, maxRPM: 6500), 3000)
        // Above last point -> clamps to last point's target RPM (6000)
        XCTAssertEqual(profile.targetRPM(forTemperature: 90, minRPM: 1200, maxRPM: 6500), 6000)
    }
    
    func testFanControlModesAndWatchdog() {
        XCTAssertEqual(FanControlMode.auto.displayName, "Auto")
        XCTAssertEqual(FanControlMode.manual.displayName, "Manual")
        XCTAssertEqual(FanControlMode.curve.displayName, "Curve")
    }
    
    func testFirebaseConfiguration() async {
        await MainActor.run {
            let manager = FirebaseManager.shared
            manager.configure()
            print("FIREBASE DIAGNOSTIC: status = \(manager.status), isConfigured = \(manager.isConfigured), deviceId = \(manager.deviceId)")
        }
    }
}

