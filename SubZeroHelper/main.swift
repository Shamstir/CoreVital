import Foundation

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: "com.subzero.helper")
listener.delegate = delegate
listener.resume()

// Keep helper daemon running
RunLoop.current.run()
