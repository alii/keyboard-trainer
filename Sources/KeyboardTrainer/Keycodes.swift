import Carbon
import Foundation

/// Modifier bits as QMK packs them into keycodes.
struct QMKMods: OptionSet, Codable, Hashable {
    let rawValue: UInt8
    static let ctrl = QMKMods(rawValue: 0x01)
    static let shift = QMKMods(rawValue: 0x02)
    static let alt = QMKMods(rawValue: 0x04)
    static let gui = QMKMods(rawValue: 0x08)

    init(rawValue: UInt8) { self.rawValue = rawValue }
    /// QMK uses bit 0x10 to mean "right-hand", which we don't care about.
    init(qmk: Int) { rawValue = UInt8(qmk & 0x0F) }

    var symbols: String {
        var s = ""
        if contains(.ctrl) { s += "⌃" }
        if contains(.alt) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.gui) { s += "⌘" }
        return s
    }
}

/// What a single keycode in the keymap does, decoded from QMK's 16-bit numbers.
enum KeyAction: Hashable {
    case none
    case transparent
    case basic(UInt8)
    case modded(QMKMods, UInt8)
    case modTap(QMKMods, UInt8)
    case layerTap(layer: Int, tap: UInt8)
    case layerMod(layer: Int, mods: QMKMods)
    case momentary(Int)
    case toggle(Int)
    case to(Int)
    case defaultLayer(Int)
    case oneShotLayer(Int)
    case tapToggle(Int)
    case custom(Int)
    case lighting(String)
    case other(UInt16)

    /// Decodes a keycode. Vial protocol 6 and later uses QMK's newer numbering.
    init(_ kc: UInt16, vialProtocol: Int) {
        let k = Int(kc)
        switch k {
        case 0x0000: self = .none
        case 0x0001: self = .transparent
        case 0x0002...0x00FF: self = .basic(UInt8(k))
        case 0x0100...0x1FFF: self = .modded(QMKMods(qmk: k >> 8), UInt8(k & 0xFF))
        case 0x2000...0x3FFF: self = .modTap(QMKMods(qmk: k >> 8), UInt8(k & 0xFF))
        case 0x4000...0x4FFF: self = .layerTap(layer: (k >> 8) & 0x0F, tap: UInt8(k & 0xFF))
        default:
            self = vialProtocol >= 6 ? Self.decodeV6(k) : Self.decodeV5(k)
        }
    }

    private static func decodeV6(_ k: Int) -> KeyAction {
        switch k {
        case 0x5000...0x51FF: return .layerMod(layer: (k >> 5) & 0x0F, mods: QMKMods(qmk: k))
        case 0x5200...0x521F: return .to(k & 0x1F)
        case 0x5220...0x523F: return .momentary(k & 0x1F)
        case 0x5240...0x525F: return .defaultLayer(k & 0x1F)
        case 0x5260...0x527F: return .toggle(k & 0x1F)
        case 0x5280...0x529F: return .oneShotLayer(k & 0x1F)
        case 0x52C0...0x52DF: return .tapToggle(k & 0x1F)
        case 0x7800...0x78FF: return .lighting(lightingName(k & 0xFF))
        case 0x7E00...0x7E3F: return .custom(k - 0x7E00)
        default: return .other(UInt16(k))
        }
    }

    private static func decodeV5(_ k: Int) -> KeyAction {
        switch k {
        case 0x5000...0x50FF: return .to(k & 0x0F)
        case 0x5100...0x51FF: return .momentary(k & 0x0F)
        case 0x5200...0x52FF: return .defaultLayer(k & 0x0F)
        case 0x5300...0x53FF: return .toggle(k & 0x0F)
        case 0x5400...0x54FF: return .oneShotLayer(k & 0x0F)
        case 0x5800...0x58FF: return .tapToggle(k & 0x0F)
        case 0x5F80...0x5FBF: return .custom(k - 0x5F80)
        default: return .other(UInt16(k))
        }
    }

    private static func lightingName(_ low: Int) -> String {
        switch low {
        case 0x20: "RGB"
        case 0x21: "Mode"
        case 0x22: "Mode−"
        case 0x23: "Hue+"
        case 0x24: "Hue−"
        case 0x25: "Sat+"
        case 0x26: "Sat−"
        case 0x27: "Bri+"
        case 0x28: "Bri−"
        case 0x29: "Spd+"
        case 0x2A: "Spd−"
        default: "Light"
        }
    }

    /// The layer this key gives you while held, if any.
    var heldLayer: Int? {
        switch self {
        case .momentary(let l), .layerTap(let l, _), .layerMod(let l, _), .tapToggle(let l), .oneShotLayer(let l): l
        default: nil
        }
    }
}

/// HID usage IDs that matter for modifiers.
enum HID {
    static let leftCtrl: UInt8 = 0xE0, leftShift: UInt8 = 0xE1, leftAlt: UInt8 = 0xE2, leftGui: UInt8 = 0xE3
    static let rightCtrl: UInt8 = 0xE4, rightShift: UInt8 = 0xE5, rightAlt: UInt8 = 0xE6, rightGui: UInt8 = 0xE7

    /// Maps a HID usage to a macOS virtual key code. `iso` matters for two keys:
    /// macOS swaps the grave key and the extra ISO key on ISO keyboards.
    static func virtualKey(_ usage: UInt8, iso: Bool) -> UInt16? {
        switch usage {
        case 0x35: return iso ? 0x0A : 0x32
        case 0x64: return iso ? 0x32 : 0x0A
        default: return table[usage]
        }
    }

    private static let table: [UInt8: UInt16] = {
        var t: [UInt8: UInt16] = [:]
        let letters: [UInt16] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
                                 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]
        for (i, vk) in letters.enumerated() { t[UInt8(0x04 + i)] = vk }
        let digits: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]
        for (i, vk) in digits.enumerated() { t[UInt8(0x1E + i)] = vk }
        let rest: [UInt8: UInt16] = [
            0x28: 0x24, 0x29: 0x35, 0x2A: 0x33, 0x2B: 0x30, 0x2C: 0x31, 0x2D: 0x1B, 0x2E: 0x18,
            0x2F: 0x21, 0x30: 0x1E, 0x31: 0x2A, 0x32: 0x2A, 0x33: 0x29, 0x34: 0x27, 0x36: 0x2B,
            0x37: 0x2F, 0x38: 0x2C, 0x39: 0x39,
            0x3A: 0x7A, 0x3B: 0x78, 0x3C: 0x63, 0x3D: 0x76, 0x3E: 0x60, 0x3F: 0x61,
            0x40: 0x62, 0x41: 0x64, 0x42: 0x65, 0x43: 0x6D, 0x44: 0x67, 0x45: 0x6F,
            0x49: 0x72, 0x4A: 0x73, 0x4B: 0x74, 0x4C: 0x75, 0x4D: 0x77, 0x4E: 0x79,
            0x4F: 0x7C, 0x50: 0x7B, 0x51: 0x7D, 0x52: 0x7E,
        ]
        t.merge(rest) { a, _ in a }
        return t
    }()

    /// A short label for keys that don't type a character.
    static func label(_ usage: UInt8) -> String? {
        switch usage {
        case 0x28: "⏎"
        case 0x29: "esc"
        case 0x2A: "⌫"
        case 0x2B: "⇥"
        case 0x2C: "space"
        case 0x39: "caps"
        case 0x3A...0x45: "F\(Int(usage) - 0x39)"
        case 0x46: "prt"
        case 0x47: "scrl"
        case 0x48: "pause"
        case 0x49: "ins"
        case 0x4A: "home"
        case 0x4B: "pg↑"
        case 0x4C: "⌦"
        case 0x4D: "end"
        case 0x4E: "pg↓"
        case 0x4F: "→"
        case 0x50: "←"
        case 0x51: "↓"
        case 0x52: "↑"
        case 0x65: "menu"
        case 0x7F, 0xA8: "mute"
        case 0x80, 0xA9: "vol+"
        case 0x81, 0xAA: "vol−"
        case 0xAB: "⏭"
        case 0xAC: "⏮"
        case 0xAE: "⏯"
        case 0xBD: "bri+"
        case 0xBE: "bri−"
        case HID.leftCtrl, HID.rightCtrl: "⌃"
        case HID.leftShift, HID.rightShift: "⇧"
        case HID.leftAlt, HID.rightAlt: "⌥"
        case HID.leftGui, HID.rightGui: "⌘"
        default: nil
        }
    }

    static func isShift(_ u: UInt8) -> Bool { u == leftShift || u == rightShift }
    static func isAlt(_ u: UInt8) -> Bool { u == leftAlt || u == rightAlt }
}

/// Turns virtual keys into characters using whatever input source is active (British-PC, etc).
final class LayoutTranslator {
    private let layoutData: CFData?
    let isISO: Bool

    init() {
        let src = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) {
            layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
        } else {
            layoutData = nil
        }
        // LMGetKbdType is the type of the keyboard you last typed on.
        isISO = KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardISO
    }

    /// Returns the character, or nil when nothing printable comes out (or it's a dead key).
    func character(vk: UInt16, shift: Bool, alt: Bool) -> String? {
        guard let layoutData, let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var mods: UInt32 = 0
        if shift { mods |= UInt32(shiftKey >> 8) }
        if alt { mods |= UInt32(optionKey >> 8) }
        var dead: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, vk, UInt16(kUCKeyActionDown), mods, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        guard status == noErr, dead == 0, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        guard let scalar = s.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F else { return nil }
        return s
    }
}
