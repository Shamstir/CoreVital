import Foundation

public final class SubZeroHelperService: NSObject, SubZeroHelperProtocol {
    private let smcWriter = SMCWriter.shared
    
    public func getHelperVersion(withReply reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }
    
    public func setFanMode(fanID: Int, mode: Int, speed: Double, withReply reply: @escaping (Bool, String?) -> Void) {
        let result = smcWriter.setFanMode(fanID: fanID, mode: mode, speed: speed)
        reply(result.success, result.message)
    }
    
    public func resetAllFansToAuto(withReply reply: @escaping (Bool, String?) -> Void) {
        let result = smcWriter.resetAllFansToAuto()
        reply(result.success, result.message)
    }
}
