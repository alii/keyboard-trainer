import Compression
import Foundation
import IOKit.hid

/// Talks to a VIA/Vial keyboard over its raw HID interface (usage page 0xFF60).
/// Most keyboards only expose this over USB, not Bluetooth.
final class VialReader {
    enum Failure: Error, CustomStringConvertible {
        case noKeyboard
        case openFailed(IOReturn)
        case timeout
        case badDefinition(String)

        var description: String {
            switch self {
            case .noKeyboard: "No VIA or Vial keyboard is plugged in over USB."
            case .openFailed(let r): "Couldn't open the keyboard (IOReturn \(r))."
            case .timeout: "The keyboard didn't answer in time."
            case .badDefinition(let why): "The keyboard sent a layout I couldn't read: \(why)"
            }
        }
    }

    private let device: IOHIDDevice
    private var inputBuffer = [UInt8](repeating: 0, count: 64)
    private var reply: [UInt8]?
    private let reportSize = 32

    let productName: String
    let vendorID: Int
    let productID: Int

    private init(device: IOHIDDevice) {
        self.device = device
        productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Keyboard"
        vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
    }

    /// Finds the first raw HID interface that looks like VIA or Vial.
    static func open() throws -> VialReader {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDPrimaryUsagePageKey: 0xFF60,
            kIOHIDPrimaryUsageKey: 0x61,
        ] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = set.first else {
            throw Failure.noKeyboard
        }
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw Failure.openFailed(r) }
        return VialReader(device: device)
    }

    deinit {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Sends one 32-byte report and waits for the keyboard's 32-byte answer.
    func send(_ bytes: [UInt8]) throws -> [UInt8] {
        var out = bytes + [UInt8](repeating: 0, count: max(0, reportSize - bytes.count))
        out = Array(out.prefix(reportSize))
        reply = nil

        let context = Unmanaged.passUnretained(self).toOpaque()
        inputBuffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(device, buf.baseAddress!, buf.count, { ctx, _, _, _, _, report, length in
                let me = Unmanaged<VialReader>.fromOpaque(ctx!).takeUnretainedValue()
                me.reply = Array(UnsafeBufferPointer(start: report, count: length))
            }, context)
        }
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer { IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) }

        let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, out, out.count)
        guard r == kIOReturnSuccess else { throw Failure.openFailed(r) }

        let deadline = Date().addingTimeInterval(1.0)
        while reply == nil && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }
        guard let reply else { throw Failure.timeout }
        return reply
    }

    // MARK: - VIA commands

    func protocolVersion() throws -> Int {
        let r = try send([0x01])
        return Int(r[1]) << 8 | Int(r[2])
    }

    func layerCount() throws -> Int {
        Int(try send([0x11])[1])
    }

    /// Reads the whole keymap as raw 16-bit keycodes, ordered layer, row, column.
    func keymapBuffer(layers: Int, rows: Int, cols: Int) throws -> [UInt16] {
        let total = layers * rows * cols * 2
        var bytes: [UInt8] = []
        var offset = 0
        while offset < total {
            let size = min(28, total - offset)
            let r = try send([0x12, UInt8(offset >> 8), UInt8(offset & 0xFF), UInt8(size)])
            bytes += r[4..<(4 + size)]
            offset += size
        }
        return stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
    }

    // MARK: - Vial commands

    /// Returns the Vial protocol version, or nil if this is plain VIA.
    func vialProtocol() -> Int? {
        guard let r = try? send([0xFE, 0x00]) else { return nil }
        let v = Int(r[0]) | Int(r[1]) << 8 | Int(r[2]) << 16 | Int(r[3]) << 24
        return (v == 0 || v > 1000) ? nil : v
    }

    /// Downloads the keyboard's own layout file, which Vial stores xz-compressed.
    func vialDefinition() throws -> [String: Any] {
        let sizeReply = try send([0xFE, 0x01])
        let size = Int(sizeReply[0]) | Int(sizeReply[1]) << 8 | Int(sizeReply[2]) << 16 | Int(sizeReply[3]) << 24
        guard size > 0, size < 1_000_000 else { throw Failure.badDefinition("size \(size)") }

        var blob: [UInt8] = []
        var page = 0
        while blob.count < size {
            let r = try send([0xFE, 0x02, UInt8(page & 0xFF), UInt8(page >> 8)])
            blob += r
            page += 1
        }
        blob = Array(blob.prefix(size))

        guard let json = Self.decompressXZ(Data(blob)) else { throw Failure.badDefinition("couldn't decompress") }
        guard let obj = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw Failure.badDefinition("not a JSON object")
        }
        return obj
    }

    static func decompressXZ(_ data: Data) -> Data? {
        let capacity = 1 << 20
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { dst.deallocate() }
        let n = data.withUnsafeBytes { src in
            compression_decode_buffer(dst, capacity, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZMA)
        }
        return n > 0 ? Data(bytes: dst, count: n) : nil
    }
}
