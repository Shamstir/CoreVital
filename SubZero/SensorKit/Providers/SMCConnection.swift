import Foundation
import IOKit

public final class SMCConnection {
    public static let shared = SMCConnection()
    
    private var conn: io_connect_t = 0
    private let lock = NSLock()
    
    private init() {
        open()
    }
    
    deinit {
        close()
    }
    
    public func open() {
        lock.lock()
        defer { lock.unlock() }
        if conn != 0 { return }
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service != 0 {
            let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
            IOObjectRelease(service)
            if result != kIOReturnSuccess {
                conn = 0
            }
        }
    }
    
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
    }
    
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return conn != 0
    }
    
    // MARK: - Structs
    
    private struct SMCKeyData_vers_t {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCKeyData_pLimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyData_keyInfo_t {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
    }

    private struct SMCKeyData_t {
        var key: UInt32 = 0
        var vers = SMCKeyData_vers_t()
        var pLimitData = SMCKeyData_pLimitData_t()
        var keyInfo = SMCKeyData_keyInfo_t()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
            0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
            0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
        )
    }

    private struct SMCVal_t {
        var key: UInt32 = 0
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var bytes: [UInt8] = []
    }
    
    private func fourCC(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for char in str.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }
    
    private func stringFromFourCC(_ code: UInt32) -> String {
        let chars: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ].filter { $0 != 0 }
        return (String(bytes: chars, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func callStructMethod(input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
        lock.lock()
        defer { lock.unlock() }
        guard conn != 0 else { return kIOReturnNoDevice }
        
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        
        return IOConnectCallStructMethod(
            conn,
            2, // KERNEL_INDEX_SMC
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }
    
    public func readKeyInfo(_ key: String) -> (dataSize: UInt32, dataType: String)? {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        
        input.key = fourCC(key)
        input.data8 = 9 // SMC_CMD_READ_KEYINFO
        
        let status = callStructMethod(input: &input, output: &output)
        if status == kIOReturnSuccess && output.result == 0 {
            return (output.keyInfo.dataSize, stringFromFourCC(output.keyInfo.dataType))
        }
        return nil
    }
    
    public func readData(_ key: String) -> [UInt8]? {
        guard let info = readKeyInfo(key) else { return nil }
        
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        
        input.key = fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 5 // SMC_CMD_READ_BYTES
        
        let status = callStructMethod(input: &input, output: &output)
        if status == kIOReturnSuccess && output.result == 0 {
            let mirror = Mirror(reflecting: output.bytes)
            var bytes: [UInt8] = []
            for child in mirror.children {
                if let byte = child.value as? UInt8 {
                    bytes.append(byte)
                }
            }
            return Array(bytes.prefix(Int(info.dataSize)))
        }
        return nil
    }
    
    public func readDouble(_ key: String) -> Double? {
        guard let info = readKeyInfo(key), let bytes = readData(key) else { return nil }
        let type = info.dataType
        
        if type == "sp78" && bytes.count >= 2 {
            let intVal = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(intVal) / 256.0
        } else if type == "fpe2" && bytes.count >= 2 {
            let intVal = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(intVal) / 4.0
        } else if type == "fhs" && bytes.count >= 2 {
            // Half-precision float (16-bit) or fixed-point fhs used on M-series fan speeds
            let intVal = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(intVal) / 4.0
        } else if type == "flt" && bytes.count >= 4 {
            var val: Float = 0
            let data = Data(bytes)
            _ = data.withUnsafeBytes { ptr in
                memcpy(&val, ptr.baseAddress, 4)
            }
            return Double(val)
        } else if type == "ui8" && bytes.count >= 1 {
            return Double(bytes[0])
        } else if type == "ui16" && bytes.count >= 2 {
            let val = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(val)
        } else if type == "ui32" && bytes.count >= 4 {
            let val = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            return Double(val)
        }
        return nil
    }
    
    public func readString(_ key: String) -> String? {
        guard let bytes = readData(key) else { return nil }
        let trimmed = bytes.prefix(while: { $0 != 0 })
        return String(bytes: trimmed, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Read all fan readings using standard FNum and F%d... keys
    public func readFanSpeeds() -> [FanReading] {
        guard let fanCountVal = readDouble("FNum") else { return [] }
        let count = Int(fanCountVal)
        guard count > 0 && count < 16 else { return [] }
        
        var fans: [FanReading] = []
        for i in 0..<count {
            // Check F%dAc first, fallback to FL0Ac (left) / FR0Ac (right) on Apple Silicon
            var current = readDouble(String(format: "F%dAc", i))
            if current == nil {
                if i == 0 { current = readDouble("FL0Ac") }
                else if i == 1 { current = readDouble("FR0Ac") }
            }
            let currentVal = current ?? 0.0
            
            var min = readDouble(String(format: "F%dMn", i))
            if min == nil {
                if i == 0 { min = readDouble("FL0Mn") }
                else if i == 1 { min = readDouble("FR0Mn") }
            }
            let minVal = min ?? 0.0
            
            var maxReading = readDouble(String(format: "F%dMx", i))
            if maxReading == nil {
                if i == 0 { maxReading = readDouble("FL0Mx") }
                else if i == 1 { maxReading = readDouble("FR0Mx") }
            }
            let maxVal = (maxReading != nil && maxReading! > 0) ? maxReading! : (minVal > 0 ? Swift.max(minVal + 3000.0, 5000.0) : 5000.0)
            
            // Try reading custom identifier string, or F%dID
            var name = "Fan \(i + 1)"
            if let idStr = readString(String(format: "F%dID", i)), !idStr.isEmpty {
                name = idStr
            } else if count == 2 {
                name = (i == 0) ? "Left Fan" : "Right Fan"
            }
            
            fans.append(FanReading(
                id: i,
                name: name,
                currentRPM: currentVal,
                minRPM: minVal,
                maxRPM: maxVal
            ))
        }
        return fans
    }
}
