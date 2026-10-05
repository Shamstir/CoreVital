import Foundation

@objc public protocol SubZeroHelperProtocol {
    func getHelperVersion(withReply reply: @escaping (String) -> Void)
    func setFanMode(fanID: Int, mode: Int, speed: Double, withReply reply: @escaping (Bool, String?) -> Void)
    func resetAllFansToAuto(withReply reply: @escaping (Bool, String?) -> Void)
}
