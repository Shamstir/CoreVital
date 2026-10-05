import Foundation

public final class HIDSensorHelper {
    public static let shared = HIDSensorHelper()
    
    private let lock = NSLock()
    private var client: CFTypeRef?
    
    private typealias IOHIDEventSystemClientCreateFunc = @convention(c) (CFAllocator?) -> CFTypeRef?
    private typealias IOHIDEventSystemClientCopyServicesFunc = @convention(c) (CFTypeRef) -> CFArray?
    private typealias IOHIDServiceClientCopyPropertyFunc = @convention(c) (CFTypeRef, CFString) -> CFTypeRef?
    private typealias IOHIDServiceClientCopyEventFunc = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> CFTypeRef?
    private typealias IOHIDEventGetFloatValueFunc = @convention(c) (CFTypeRef, Int64) -> Double
    
    private var copyServicesFunc: IOHIDEventSystemClientCopyServicesFunc?
    private var copyPropertyFunc: IOHIDServiceClientCopyPropertyFunc?
    private var copyEventFunc: IOHIDServiceClientCopyEventFunc?
    private var getFloatFunc: IOHIDEventGetFloatValueFunc?
    
    private init() {
        loadHIDFramework()
    }
    
    private func loadHIDFramework() {
        lock.lock()
        defer { lock.unlock() }
        
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return }
        
        guard let createSym = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let copyServicesSym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let copyPropertySym = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let copyEventSym = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let getFloatSym = dlsym(handle, "IOHIDEventGetFloatValue") else {
            return
        }
        
        let clientCreate = unsafeBitCast(createSym, to: IOHIDEventSystemClientCreateFunc.self)
        self.copyServicesFunc = unsafeBitCast(copyServicesSym, to: IOHIDEventSystemClientCopyServicesFunc.self)
        self.copyPropertyFunc = unsafeBitCast(copyPropertySym, to: IOHIDServiceClientCopyPropertyFunc.self)
        self.copyEventFunc = unsafeBitCast(copyEventSym, to: IOHIDServiceClientCopyEventFunc.self)
        self.getFloatFunc = unsafeBitCast(getFloatSym, to: IOHIDEventGetFloatValueFunc.self)
        
        self.client = clientCreate(kCFAllocatorDefault)
    }
    
    public func readTemperatures() -> (cpu: Double?, gpu: Double?, battery: Double?) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let client = client,
              let copyServices = copyServicesFunc,
              let copyProperty = copyPropertyFunc,
              let copyEvent = copyEventFunc,
              let getFloat = getFloatFunc,
              let services = copyServices(client) as? [CFTypeRef] else {
            return (nil, nil, nil)
        }
        
        var cpuTemps: [Double] = []
        var gpuTemps: [Double] = []
        var batteryTemp: Double?
        
        // kIOHIDEventTypeTemperature = 15
        // kIOHIDEventFieldTemperatureLevel = (15 << 16) | 0 = 0xF0000 = 983040
        for service in services {
            guard let name = (copyProperty(service, "Product" as CFString) as? String)?.lowercased() ??
                             (copyProperty(service, "PrimaryUsagePage" as CFString) as? String)?.lowercased() else {
                continue
            }
            
            guard let event = copyEvent(service, 15, 0, 0) else { continue }
            let temp = getFloat(event, 0xF0000)
            
            // Valid Apple Silicon thermal sensor range: 15°C to 125°C
            guard temp > 15.0 && temp < 125.0 else { continue }
            
            if name.contains("tdie") || name.contains("pacc") || name.contains("eacc") || name.contains("cpu") || name.contains("soc") {
                cpuTemps.append(temp)
            } else if name.contains("tdev") || name.contains("gpu") {
                gpuTemps.append(temp)
            } else if name.contains("gas gauge") || name.contains("battery") {
                batteryTemp = temp
            }
        }
        
        let cpuAvg = cpuTemps.isEmpty ? nil : cpuTemps.reduce(0.0, +) / Double(cpuTemps.count)
        let gpuAvg = gpuTemps.isEmpty ? nil : gpuTemps.reduce(0.0, +) / Double(gpuTemps.count)
        
        return (cpuAvg, gpuAvg, batteryTemp)
    }
}
