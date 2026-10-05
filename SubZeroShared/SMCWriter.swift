import Foundation
import IOKit

public final class SMCWriter {
    public static let shared = SMCWriter()
    
    private var conn: io_connect_t = 0
    private let lock = NSLock()
    public private(set) var isConnected: Bool = false
    
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
    
    private init() {
        connect()
    }
    
    deinit {
        disconnect()
    }
    
    private func connect() {
        lock.lock()
        defer { lock.unlock() }
        
        guard conn == 0 else { return }
        
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            print("SMCWriter [Error]: AppleSMC service not found.")
            return
        }
        defer { IOObjectRelease(service) }
        
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        if result == kIOReturnSuccess {
            isConnected = true
        } else {
            print("SMCWriter [Error]: IOServiceOpen failed with code: 0x\(String(result, radix: 16))")
            conn = 0
            isConnected = false
        }
    }
    
    private func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
            isConnected = false
        }
    }
    
    private func fourCC(_ string: String) -> UInt32 {
        guard string.count == 4 else { return 0 }
        let bytes = Array(string.utf8)
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
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
        if conn == 0 {
            lock.unlock()
            connect()
            lock.lock()
        }
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
    
    public func readDouble(_ key: String) -> Double? {
        guard let info = readKeyInfo(key) else { return nil }
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        
        input.key = fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 5 // SMC_CMD_READ_BYTES
        
        let status = callStructMethod(input: &input, output: &output)
        guard status == kIOReturnSuccess && output.result == 0 else { return nil }
        
        let mirror = Mirror(reflecting: output.bytes)
        var bytes: [UInt8] = []
        for child in mirror.children {
            if let byte = child.value as? UInt8 {
                bytes.append(byte)
            }
        }
        let dataBytes = Array(bytes.prefix(Int(info.dataSize)))
        let type = info.dataType
        
        if type == "sp78" && dataBytes.count >= 2 {
            let intVal = Int16(bitPattern: (UInt16(dataBytes[0]) << 8) | UInt16(dataBytes[1]))
            return Double(intVal) / 256.0
        } else if (type == "fpe2" || type == "fhs") && dataBytes.count >= 2 {
            let intVal = (UInt16(dataBytes[0]) << 8) | UInt16(dataBytes[1])
            return Double(intVal) / 4.0
        } else if type == "flt" && dataBytes.count >= 4 {
            var val: Float = 0
            let data = Data(dataBytes)
            _ = data.withUnsafeBytes { ptr in
                memcpy(&val, ptr.baseAddress, 4)
            }
            return Double(val)
        } else if type == "ui8" && dataBytes.count >= 1 {
            return Double(dataBytes[0])
        } else if type == "ui16" && dataBytes.count >= 2 {
            let val = (UInt16(dataBytes[0]) << 8) | UInt16(dataBytes[1])
            return Double(val)
        }
        return nil
    }
    
    public func writeBytes(_ key: String, bytes: [UInt8]) -> (status: kern_return_t, result: UInt8) {
        guard let info = readKeyInfo(key) else {
            print("SMCWriter [Error]: Key \(key) not found when attempting write.")
            return (kIOReturnNotFound, 255)
        }
        
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        
        input.key = fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 6 // SMC_CMD_WRITE_BYTES
        
        // Copy bytes into input.bytes tuple
        var tupleBytes = (UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),
                          UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),
                          UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),
                          UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0))
        
        let copyCount = min(bytes.count, Int(info.dataSize), 32)
        withUnsafeMutableBytes(of: &tupleBytes) { ptr in
            for i in 0..<copyCount {
                ptr[i] = bytes[i]
            }
        }
        input.bytes = tupleBytes
        
        let status = callStructMethod(input: &input, output: &output)
        if status != kIOReturnSuccess || output.result != 0 {
            print("SMCWriter [Warn]: writeBytes(\(key)) returned status=0x\(String(status, radix: 16)), result=\(output.result)")
        } else {
            print("SMCWriter [Success]: Wrote bytes to \(key).")
        }
        return (status, output.result)
    }
    
    public func formatTargetRPM(_ speed: Double, dataType: String, dataSize: UInt32) -> [UInt8] {
        if dataType == "fpe2" || dataType == "fhs" {
            let intVal = UInt16(clamping: Int(speed * 4.0))
            return [UInt8((intVal >> 8) & 0xFF), UInt8(intVal & 0xFF)]
        } else if dataType == "flt" && dataSize >= 4 {
            var val = Float(speed)
            return withUnsafeBytes(of: &val) { Array($0) }
        } else if dataType == "ui16" {
            let val = UInt16(clamping: Int(speed))
            return [UInt8((val >> 8) & 0xFF), UInt8(val & 0xFF)]
        } else if dataType == "sp78" {
            let intVal = Int16(clamping: Int(speed * 256.0))
            let uVal = UInt16(bitPattern: intVal)
            return [UInt8((uVal >> 8) & 0xFF), UInt8(uVal & 0xFF)]
        }
        // Default fallback 2-byte big-endian
        let val = UInt16(clamping: Int(speed))
        return [UInt8((val >> 8) & 0xFF), UInt8(val & 0xFF)]
    }
    
    public func setFanMode(fanID: Int, mode: Int, speed: Double) -> (success: Bool, message: String?) {
        guard isConnected else {
            return (false, "SMC not connected.")
        }
        
        // 1. Determine mode keys to write (0 = auto, 1 = forced)
        // Check F%dMd, FL0Md/FR0Md, and FS!
        let modeKeys = [
            String(format: "F%dMd", fanID),
            fanID == 0 ? "FL0Md" : (fanID == 1 ? "FR0Md" : "")
        ].filter { !$0.isEmpty }
        
        var modeSuccess = false
        for mKey in modeKeys {
            if let info = readKeyInfo(mKey) {
                let modeBytes: [UInt8] = info.dataSize == 1 ? [UInt8(mode & 0xFF)] : [0, UInt8(mode & 0xFF)]
                let res = writeBytes(mKey, bytes: modeBytes)
                if res.status == kIOReturnSuccess && res.result == 0 {
                    modeSuccess = true
                }
            }
        }
        
        // Also attempt FS! bitmask if present (Intel legacy mode selector)
        if let fsInfo = readKeyInfo("FS! ") {
            var currentMask: UInt16 = 0
            if let val = readDouble("FS! ") {
                currentMask = UInt16(val)
            }
            if mode == 1 {
                currentMask |= (1 << UInt16(fanID))
            } else {
                currentMask &= ~(1 << UInt16(fanID))
            }
            let maskBytes = fsInfo.dataSize == 1 ? [UInt8(currentMask & 0xFF)] : [UInt8((currentMask >> 8) & 0xFF), UInt8(currentMask & 0xFF)]
            _ = writeBytes("FS! ", bytes: maskBytes)
        }
        
        // If switching to Auto mode (0), we don't need to write target speed
        if mode == 0 {
            return (true, "Fan \(fanID + 1) set to Auto mode.")
        }
        
        // 2. Write target speed (speed in RPM)
        let targetKeys = [
            String(format: "F%dTg", fanID),
            fanID == 0 ? "FL0Tg" : (fanID == 1 ? "FR0Tg" : "")
        ].filter { !$0.isEmpty }
        
        var targetSuccess = false
        var targetKeyWritten = ""
        for tKey in targetKeys {
            if let info = readKeyInfo(tKey) {
                let speedBytes = formatTargetRPM(speed, dataType: info.dataType, dataSize: info.dataSize)
                let res = writeBytes(tKey, bytes: speedBytes)
                if res.status == kIOReturnSuccess && res.result == 0 {
                    targetSuccess = true
                    targetKeyWritten = tKey
                    break
                }
            }
        }
        
        if targetSuccess {
            return (true, "Fan \(fanID + 1) target speed set to \(Int(speed)) RPM via \(targetKeyWritten).")
        } else if modeSuccess {
            return (true, "Fan \(fanID + 1) mode updated, but target key not writable directly.")
        } else {
            return (false, "Failed to write SMC fan override keys for Fan \(fanID + 1). Verify root privileges.")
        }
    }
    
    public func resetAllFansToAuto() -> (success: Bool, message: String?) {
        guard isConnected else {
            return (false, "SMC not connected.")
        }
        
        var count = 1
        if let fnum = readDouble("FNum") {
            count = max(1, min(16, Int(fnum)))
        }
        
        var anySuccess = false
        for i in 0..<count {
            let res = setFanMode(fanID: i, mode: 0, speed: 0.0)
            if res.success { anySuccess = true }
        }
        
        if anySuccess {
            return (true, "All fans restored to Automatic cooling mode.")
        } else {
            return (false, "Failed to reset fan modes to Auto.")
        }
    }
}
