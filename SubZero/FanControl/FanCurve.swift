import Foundation

public struct FanCurvePoint: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var temperature: Double
    public var targetRPM: Double
    
    public init(id: UUID = UUID(), temperature: Double, targetRPM: Double) {
        self.id = id
        self.temperature = temperature
        self.targetRPM = targetRPM
    }
}

public struct FanCurveProfile: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var points: [FanCurvePoint]
    
    public init(id: UUID = UUID(), name: String, points: [FanCurvePoint]) {
        self.id = id
        self.name = name
        self.points = points.sorted(by: { $0.temperature < $1.temperature })
    }
    
    // Compute target RPM using linear interpolation between curve points
    public func targetRPM(forTemperature temp: Double, minRPM: Double, maxRPM: Double) -> Double {
        guard !points.isEmpty else { return minRPM }
        
        let sorted = points.sorted(by: { $0.temperature < $1.temperature })
        if temp <= sorted.first!.temperature {
            return Swift.max(minRPM, Swift.min(maxRPM, sorted.first!.targetRPM))
        }
        if temp >= sorted.last!.temperature {
            return Swift.max(minRPM, Swift.min(maxRPM, sorted.last!.targetRPM))
        }
        
        for i in 0..<(sorted.count - 1) {
            let p1 = sorted[i]
            let p2 = sorted[i + 1]
            if temp >= p1.temperature && temp <= p2.temperature {
                let rangeTemp = p2.temperature - p1.temperature
                guard rangeTemp > 0 else { return p1.targetRPM }
                let progress = (temp - p1.temperature) / rangeTemp
                let rpm = p1.targetRPM + progress * (p2.targetRPM - p1.targetRPM)
                return Swift.max(minRPM, Swift.min(maxRPM, rpm))
            }
        }
        return minRPM
    }
}
