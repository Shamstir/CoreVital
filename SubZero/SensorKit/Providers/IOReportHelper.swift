import Foundation

// Safe dynamic wrapper around /System/Library/PrivateFrameworks/IOReport.framework
public final class IOReportHelper {
    public static let shared = IOReportHelper()
    
    private var handle: UnsafeMutableRawPointer?
    private var isLoaded: Bool = false
    private let lock = NSLock()
    
    // Function pointer types
    typealias IOReportCopyChannelsInGroupFunc = @convention(c) (String?, String?, UInt64, UInt64, UInt64) -> CFDictionary?
    typealias IOReportCreateSubscriptionFunc = @convention(c) (UnsafeRawPointer?, CFDictionary?, UnsafeMutablePointer<CFMutableDictionary?>?, UInt64, CFTypeRef?) -> IOReportSubscriptionRef?
    typealias IOReportCreateSamplesFunc = @convention(c) (IOReportSubscriptionRef?, CFMutableDictionary?, CFTypeRef?) -> CFDictionary?
    typealias IOReportCreateSamplesDeltaFunc = @convention(c) (CFDictionary?, CFDictionary?, CFTypeRef?) -> CFDictionary?
    typealias IOReportGetChannelCountFunc = @convention(c) (CFDictionary?) -> Int32
    typealias IOReportGetChannelValueFunc = @convention(c) (CFDictionary?, Int32) -> Int64
    typealias IOReportGetChannelNameFunc = @convention(c) (CFDictionary?, Int32) -> String?
    typealias IOReportGetSubgroupNameFunc = @convention(c) (CFDictionary?, Int32) -> String?
    
    private var copyChannelsInGroup: IOReportCopyChannelsInGroupFunc?
    private var createSubscription: IOReportCreateSubscriptionFunc?
    private var createSamples: IOReportCreateSamplesFunc?
    private var createSamplesDelta: IOReportCreateSamplesDeltaFunc?
    private var getChannelCount: IOReportGetChannelCountFunc?
    private var getChannelValue: IOReportGetChannelValueFunc?
    private var getChannelName: IOReportGetChannelNameFunc?
    private var getSubgroupName: IOReportGetSubgroupNameFunc?
    
    public typealias IOReportSubscriptionRef = UnsafeRawPointer
    private var subscription: IOReportSubscriptionRef?
    private var channelsDict: CFDictionary?
    private var subscribedChannels: CFMutableDictionary?
    private var previousSamples: CFDictionary?
    private var previousTimestamp: Date?
    
    private init() {
        loadFramework()
    }
    
    private func loadFramework() {
        lock.lock()
        defer { lock.unlock() }
        
        let path = "/System/Library/PrivateFrameworks/IOReport.framework/IOReport"
        guard let h = dlopen(path, RTLD_NOW) else { return }
        self.handle = h
        
        copyChannelsInGroup = unsafeBitCast(dlsym(h, "IOReportCopyChannelsInGroup"), to: IOReportCopyChannelsInGroupFunc?.self)
        createSubscription = unsafeBitCast(dlsym(h, "IOReportCreateSubscription"), to: IOReportCreateSubscriptionFunc?.self)
        createSamples = unsafeBitCast(dlsym(h, "IOReportCreateSamples"), to: IOReportCreateSamplesFunc?.self)
        createSamplesDelta = unsafeBitCast(dlsym(h, "IOReportCreateSamplesDelta"), to: IOReportCreateSamplesDeltaFunc?.self)
        getChannelCount = unsafeBitCast(dlsym(h, "IOReportGetChannelCount"), to: IOReportGetChannelCountFunc?.self)
        getChannelValue = unsafeBitCast(dlsym(h, "IOReportGetChannelValue"), to: IOReportGetChannelValueFunc?.self)
        getChannelName = unsafeBitCast(dlsym(h, "IOReportGetChannelName"), to: IOReportGetChannelNameFunc?.self)
        getSubgroupName = unsafeBitCast(dlsym(h, "IOReportGetSubgroupName"), to: IOReportGetSubgroupNameFunc?.self)
        
        if copyChannelsInGroup != nil && createSubscription != nil && createSamples != nil && getChannelValue != nil {
            isLoaded = true
            setupSubscription()
        }
    }
    
    private func setupSubscription() {
        guard let copyChannels = copyChannelsInGroup, let subscribe = createSubscription else { return }
        
        // Subscribe to Energy Model and Thermal groups safely
        let energyChannels = copyChannels("Energy Model", nil, 0, 0, 0)
        let thermalChannels = copyChannels("CPU Stats", nil, 0, 0, 0)
        
        var combinedChannels = [AnyHashable: Any]()
        if let energy = energyChannels as? [AnyHashable: Any] {
            energy.forEach { combinedChannels[$0.key] = $0.value }
        }
        if let thermal = thermalChannels as? [AnyHashable: Any] {
            thermal.forEach { combinedChannels[$0.key] = $0.value }
        }
        
        guard !combinedChannels.isEmpty else { return }
        let dict = combinedChannels as CFDictionary
        self.channelsDict = dict
        
        var subChannels: CFMutableDictionary?
        self.subscription = subscribe(nil, dict, &subChannels, 0, nil)
        self.subscribedChannels = subChannels
    }
    
    // Sample power channels (returning average Watts over elapsed time)
    public func samplePowerReadings() -> PowerReadings? {
        lock.lock()
        defer { lock.unlock() }
        guard isLoaded, let sub = subscription, let subChannels = subscribedChannels, let sampleFunc = createSamples else { return nil }
        
        let now = Date()
        guard let currentSamples = sampleFunc(sub, subChannels, nil) else { return nil }
        
        var cpuWatts: Double?
        var gpuWatts: Double?
        var aneWatts: Double?
        var dramWatts: Double?
        var totalWatts: Double?
        
        if let prev = previousSamples, let prevTime = previousTimestamp, let deltaFunc = createSamplesDelta, let countFunc = getChannelCount, let valueFunc = getChannelValue, let nameFunc = getChannelName {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0.05, let delta = deltaFunc(prev, currentSamples, nil) {
                let count = countFunc(delta)
                for i in 0..<count {
                    guard let name = nameFunc(delta, i) else { continue }
                    let val = Double(valueFunc(delta, i))
                    // IOReport energy units are typically nanojoules (nJ) or microjoules depending on channel
                    // On Apple Silicon, most Energy Model channels report in nanojoules (1e-9 J) or microjoules.
                    // We calculate Watts = Joules / elapsedSeconds
                    // A typical check: values > 1e6 indicate nanojoules
                    let watts = (val > 1_000_000 ? val * 1e-9 : val * 1e-6) / elapsed
                    
                    let lower = name.lowercased()
                    if lower.contains("cpu") || lower.contains("ecpu") || lower.contains("pcpu") {
                        cpuWatts = (cpuWatts ?? 0) + max(0, watts)
                    } else if lower.contains("gpu") {
                        gpuWatts = (gpuWatts ?? 0) + max(0, watts)
                    } else if lower.contains("ane") {
                        aneWatts = (aneWatts ?? 0) + max(0, watts)
                    } else if lower.contains("dram") || lower.contains("memory") {
                        dramWatts = (dramWatts ?? 0) + max(0, watts)
                    } else if lower.contains("package") || lower.contains("soc") {
                        totalWatts = (totalWatts ?? 0) + max(0, watts)
                    }
                }
            }
        }
        
        previousSamples = currentSamples
        previousTimestamp = now
        
        // If package is not reported explicitly, sum up components
        if totalWatts == nil {
            let sum = (cpuWatts ?? 0) + (gpuWatts ?? 0) + (aneWatts ?? 0) + (dramWatts ?? 0)
            if sum > 0 { totalWatts = sum }
        }
        
        if cpuWatts == nil && gpuWatts == nil && totalWatts == nil { return nil }
        
        return PowerReadings(
            cpuWatts: cpuWatts,
            gpuWatts: gpuWatts,
            aneWatts: aneWatts,
            dramWatts: dramWatts,
            totalPackageWatts: totalWatts
        )
    }
}
