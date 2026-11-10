import Foundation
import IOKit

internal enum SMCKeys: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readKeyInfo = 9
    case readIndex = 8
}

internal struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)
    
    struct vers_t {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }
    
    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    
    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    
    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                             UInt8(0), UInt8(0))
}

internal struct SMCBytes32 {
    var raw: SMCKeyData_t.SMCBytes_t = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    @inline(__always)
    subscript(index: Int) -> UInt8 {
        get {
            Swift.withUnsafeBytes(of: raw) { $0[index] }
        }
        set {
            withUnsafeMutableBytes(of: &raw) { $0[index] = newValue }
        }
    }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        return try Swift.withUnsafeBytes(of: raw, body)
    }
}

internal struct SMCVal_t {
    var key: UInt32 = 0
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var bytes = SMCBytes32()

    init(_ key: UInt32) {
        self.key = key
    }

    init(_ key: String) {
        self.key = FourCharCode(fromString: key)
    }
}

// MARK: - FourCharCode Data Types
private let kSMCTypeUI8: UInt32  = 0x75693820  // 'ui8 '
private let kSMCTypeUI16: UInt32 = 0x75693136  // 'ui16'
private let kSMCTypeUI32: UInt32 = 0x75693332  // 'ui32'
private let kSMCTypeFlt: UInt32  = 0x666C7420  // 'flt '
private let kSMCTypeSP78: UInt32 = 0x73703738  // 'sp78'
private let kSMCTypeIOFT: UInt32 = 0x696F6674  // 'ioft'
private let kSMCTypeFpe2: UInt32 = 0x66706532  // 'fpe2'
private let kSMCTypeSI16: UInt32 = 0x73693136  // 'si16'
private let kSMCTypeSI32: UInt32 = 0x73693332  // 'si32'

extension FourCharCode {
    init(fromString str: String) {
        precondition(str.count == 4)
        self = str.utf8.reduce(0) { sum, character in
            return sum << 8 | UInt32(character)
        }
    }
    
    func toString() -> String {
        let c1 = UnicodeScalar(self >> 24 & 0xff)
        let c2 = UnicodeScalar(self >> 16 & 0xff)
        let c3 = UnicodeScalar(self >> 8  & 0xff)
        let c4 = UnicodeScalar(self       & 0xff)
        if let c1 = c1, let c2 = c2, let c3 = c3, let c4 = c4 {
            return String(describing: c1) + String(describing: c2) + String(describing: c3) + String(describing: c4)
        }
        return "????"
    }
}

extension UInt16 {
    init(bytes: (UInt8, UInt8)) {
        self = UInt16(bytes.0) << 8 | UInt16(bytes.1)
    }
}

extension UInt32 {
    init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
        self = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3)
    }
}

extension Float {
    init?(bytes: SMCBytes32) {
        var fval: Float = 0
        withUnsafeBytes(of: bytes.raw) { buf in
            fval = buf.load(fromByteOffset: 0, as: Float.self)
        }
        self = fval
    }

    init?(_ bytes: [UInt8]) {
        if bytes.count < 4 { return nil }
        self = bytes.withUnsafeBytes {
            return $0.load(fromByteOffset: 0, as: Self.self)
        }
    }
}

// `kIOMainPortDefault` (macOS 12+) was renamed from `kIOMasterPortDefault`.
// Both are 0, the default I/O Kit port. Use a literal so the code builds
// against the macOS 11 deployment target without deprecation warnings on
// newer SDKs.
private let kIOMainPortDefaultCompat: mach_port_t = 0

public class SMC {
    public static let shared = SMC()
    private var conn: io_connect_t = 0
    private var lock = os_unfair_lock_s()
    private var keyInfoCache: [UInt32: SMCKeyData_t.keyInfo_t] = [:]
    private var cachedTempKeys: [String]?
    
    public init() {
        var result: kern_return_t
        var iterator: io_iterator_t = 0
        let device: io_object_t
        
        let matchingDictionary: CFMutableDictionary = IOServiceMatching("AppleSMC")
        result = IOServiceGetMatchingServices(kIOMainPortDefaultCompat, matchingDictionary, &iterator)
        if result != kIOReturnSuccess {
            return
        }
        
        device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        if device == 0 {
            return
        }
        
        result = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)
        if result != kIOReturnSuccess {
            return
        }
    }
    
    deinit {
        if conn != 0 {
            _ = IOServiceClose(conn)
        }
    }

    /// Reads and caches key info for a 32-bit FourCharCode key with thread safety.
    /// Returns nil if the key does not exist or SMC returns a non-zero result.
    internal func readKeyInfo(_ fourCC: UInt32) -> SMCKeyData_t.keyInfo_t? {
        guard conn != 0 else { return nil }
        os_unfair_lock_lock(&lock)
        if let cached = keyInfoCache[fourCC] {
            os_unfair_lock_unlock(&lock)
            return cached
        }
        os_unfair_lock_unlock(&lock)

        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = fourCC
        input.data8 = SMCKeys.readKeyInfo.rawValue

        let result = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
        guard result == kIOReturnSuccess && output.result == 0 else {
            return nil
        }

        os_unfair_lock_lock(&lock)
        keyInfoCache[fourCC] = output.keyInfo
        os_unfair_lock_unlock(&lock)

        return output.keyInfo
    }

    /// String wrapper for readKeyInfo.
    internal func readKeyInfo(_ key: String) -> SMCKeyData_t.keyInfo_t? {
        guard key.utf8.count == 4 else { return nil }
        return readKeyInfo(FourCharCode(fromString: key))
    }
    
    /// Zero-allocation numeric read for raw UInt32 FourCharCode.
    public func getValue(_ key: UInt32) -> Double? {
        guard conn != 0 else { return nil }
        var val = SMCVal_t(key)
        let result = read(&val)
        guard result == kIOReturnSuccess else {
            return nil
        }
        return decodeValue(val)
    }

    /// Reads numeric SMC key by String name.
    public func getValue(_ key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }
        return getValue(FourCharCode(fromString: key))
    }

    /// Reads numeric SMC key (IEEE 754 'flt ', ui8, ui16, ui32, sp78, ioft, fpe2, si16, si32).
    public func readNumericKey(_ key: String) -> Double? {
        return getValue(key)
    }

    /// Reads numeric SMC key for raw UInt32 FourCharCode.
    public func readNumericKey(_ key: UInt32) -> Double? {
        return getValue(key)
    }

    private func decodeValue(_ val: SMCVal_t) -> Double? {
        guard val.dataSize > 0 else { return nil }
        switch val.dataType {
        case kSMCTypeUI8:
            return Double(val.bytes[0])
        case kSMCTypeUI16:
            return Double(UInt16(bytes: (val.bytes[0], val.bytes[1])))
        case kSMCTypeUI32:
            return Double(UInt32(bytes: (val.bytes[0], val.bytes[1], val.bytes[2], val.bytes[3])))
        case kSMCTypeFlt:
            if val.dataSize >= 4, let fval = Float(bytes: val.bytes) {
                return Double(fval)
            }
        case kSMCTypeSP78:
            // sp78 = signed fixed-point: 1 sign + 8 integer + 7 fractional bits.
            // Bytes are big-endian; use Int16 to sign-extend correctly.
            let raw = Int16(val.bytes[0]) << 8 | Int16(val.bytes[1])
            return Double(raw) / 256.0
        case kSMCTypeIOFT:
            // ioft = Q16.16 signed little-endian float.
            if val.dataSize >= 4 {
                let u32 = UInt32(val.bytes[0]) | (UInt32(val.bytes[1]) << 8) | (UInt32(val.bytes[2]) << 16) | (UInt32(val.bytes[3]) << 24)
                return Double(Int32(bitPattern: u32)) / 65536.0
            }
        case kSMCTypeFpe2:
            // fpe2 = unsigned 14.2 fixed point.
            if val.dataSize >= 2 {
                return Double(UInt16(val.bytes[0]) << 6 | UInt16(val.bytes[1]) >> 2) + Double(val.bytes[1] & 0x03) / 4.0
            }
        case kSMCTypeSI16:
            // si16 = signed 16-bit big-endian integer.
            if val.dataSize >= 2 {
                let raw = Int16(val.bytes[0]) << 8 | Int16(val.bytes[1])
                return Double(raw)
            }
        case kSMCTypeSI32:
            // si32 = signed 32-bit big-endian integer.
            if val.dataSize >= 4 {
                let u32 = UInt32(val.bytes[0]) << 24 | UInt32(val.bytes[1]) << 16 | UInt32(val.bytes[2]) << 8 | UInt32(val.bytes[3])
                return Double(Int32(bitPattern: u32))
            }
        default:
            return nil
        }
        return nil
    }
    
    public func getKeyCount() -> UInt32 {
        guard conn != 0 else { return 0 }
        var val = SMCVal_t("#KEY")
        let result = read(&val)
        guard result == kIOReturnSuccess else {
            return 0
        }
        if val.dataSize == 4, val.dataType == kSMCTypeUI32 {
            return UInt32(bytes: (val.bytes[0], val.bytes[1], val.bytes[2], val.bytes[3]))
        }
        return 0
    }
    
    public func getKeyAtIndex(_ index: UInt32) -> String? {
        guard conn != 0 else { return nil }
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        
        input.data8 = SMCKeys.readIndex.rawValue
        input.data32 = index
        
        let result = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
        if result == kIOReturnSuccess {
            return output.key.toString()
        }
        return nil
    }
    
    public func getAllTemperatureKeys() -> [String] {
        if let cached = cachedTempKeys {
            return cached
        }
        let count = getKeyCount()
        var tempKeys: [String] = []
        tempKeys.reserveCapacity(min(Int(count), 256))
        for i in 0..<count {
            if let key = getKeyAtIndex(i) {
                // T means Temperature in SMC
                if key.hasPrefix("T") {
                    tempKeys.append(key)
                }
            }
        }
        cachedTempKeys = tempKeys
        return tempKeys
    }
    
    private func read(_ value: UnsafeMutablePointer<SMCVal_t>) -> kern_return_t {
        let fourCC = value.pointee.key
        guard let cached = readKeyInfo(fourCC) else {
            return kIOReturnError
        }

        value.pointee.dataSize = UInt32(cached.dataSize)
        value.pointee.dataType = cached.dataType

        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        input.key = fourCC
        input.keyInfo.dataSize = cached.dataSize
        input.data8 = SMCKeys.readBytes.rawValue

        let result = call(SMCKeys.kernelIndex.rawValue, input: &input, output: &output)
        if result != kIOReturnSuccess {
            return result
        }
        
        memcpy(&value.pointee.bytes.raw, &output.bytes, min(Int(value.pointee.dataSize), 32))
        return kIOReturnSuccess
    }
    
    private func call(_ index: UInt8, input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        let result = IOConnectCallStructMethod(conn, UInt32(index), &input, inputSize, &output, &outputSize)
        if result != kIOReturnSuccess {
            return result
        }
        if output.result != 0 {
            return kIOReturnError
        }
        return kIOReturnSuccess
    }
}
