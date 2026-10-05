import Foundation

public final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Configure exported interface and object
        newConnection.exportedInterface = NSXPCInterface(with: SubZeroHelperProtocol.self)
        newConnection.exportedObject = SubZeroHelperService()
        
        newConnection.resume()
        return true
    }
}
