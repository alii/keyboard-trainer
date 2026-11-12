import Foundation

struct KeyPos: Hashable, Codable {
    let row: Int
    let col: Int
}

/// How to type one thing: which keys to hold, then which key to tap.
struct Recipe: Hashable {
    let layer: Int
    /// The key that you hold to reach `layer` (nil on the base layer).
    let layerKey: KeyPos?
    let shiftKey: KeyPos?
    let altKey: KeyPos?
    let tap: KeyPos
    /// Modifiers already baked into the tapped key (like a key mapped to ⇧1).
    let builtInMods: QMKMods
    let cost: Double

    var heldKeys: [KeyPos] { [layerKey, shiftKey, altKey].compactMap { $0 } }
    var stepCount: Int { heldKeys.count + 1 }
}

/// Something worth learning.
enum Target: Hashable, Codable {
    case char(String)
    case key(name: String, usage: UInt8)

    var id: String {
        switch self {
        case .char(let c): "c:" + c
        case .key(let n, _): "k:" + n
        }
    }

    var display: String {
        switch self {
        case .char(let c): c
        case .key(let n, _): n
        }
    }

    var spokenName: String {
        switch self {
        case .char(let c): Self.names[c] ?? c
        case .key(let n, _): n
        }
    }

    static let names: [String: String] = [
        "!": "exclamation mark", "\"": "double quote", "@": "at sign", "#": "hash", "£": "pound sign",
        "$": "dollar", "%": "percent", "^": "caret", "&": "ampersand", "*": "asterisk",
        "(": "open bracket", ")": "close bracket", "-": "minus", "_": "underscore", "=": "equals",
        "+": "plus", "[": "open square bracket", "]": "close square bracket", "{": "open brace",
        "}": "close brace", ";": "semicolon", ":": "colon", "'": "apostrophe", "~": "tilde",
        "`": "backtick", "¬": "not sign", "\\": "backslash", "|": "pipe", ",": "comma", ".": "full stop",
        "/": "slash", "?": "question mark", "<": "less than", ">": "greater than", "€": "euro",
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
        "6": "six", "7": "seven", "8": "eight", "9": "nine",
    ]
}

/// Works out the easiest way to type everything on the current keymap and input source.
struct RecipeBook {
    let keymap: Keymap
    let translator: LayoutTranslator
    let base: Int
    private(set) var recipes: [Target: Recipe] = [:]
    /// What each key types on each layer, for drawing keycaps.
    private(set) var legends: [Int: [KeyPos: String]] = [:]
    /// Layers you can reach from the base layer, and the key that gets you there.
    private(set) var layerKeys: [Int: KeyPos] = [:]

    init(keymap: Keymap, translator: LayoutTranslator = LayoutTranslator(), base: Int = 0) {
        self.keymap = keymap
        self.translator = translator
        self.base = base
        build()
    }

    func recipe(for t: Target) -> Recipe? { recipes[t] }

    func legend(layer: Int, _ p: KeyPos) -> String {
        // While you hold a layer key, that key still means "this layer", so label it that way.
        if layer != base, layerKeys[layer] == p { return layerName(layer) }
        return legends[layer]?[p] ?? ""
    }

    func layerName(_ l: Int) -> String {
        if l == base { return "Base" }
        let reachable = layerKeys.keys.sorted()
        if reachable.count == 1 { return "Fn" }
        return ["Lower", "Raise", "Adjust", "Layer 4", "Layer 5"][min(4, reachable.firstIndex(of: l) ?? 4)]
    }

    private mutating func build() {
        for k in keymap.keys {
            let p = KeyPos(row: k.row, col: k.col)
            if let l = keymap.action(layer: base, row: k.row, col: k.col, base: base).heldLayer,
               l != base, l < keymap.layers.count, layerKeys[l] == nil {
                layerKeys[l] = p
            }
        }

        let layers = [base] + layerKeys.keys.sorted()
        for layer in 0..<keymap.layers.count {
            var map: [KeyPos: String] = [:]
            for k in keymap.keys {
                let p = KeyPos(row: k.row, col: k.col)
                map[p] = legendFor(keymap.action(layer: layer, row: k.row, col: k.col, base: base))
            }
            legends[layer] = map
        }

        for layer in layers {
            let layerKey = layer == base ? nil : layerKeys[layer]
            let shift = findMod(layer: layer, avoiding: layerKey, HID.isShift)
            let alt = findMod(layer: layer, avoiding: layerKey, HID.isAlt)
            let layerCost = layer == base ? 0.0 : 1.0

            for k in keymap.keys {
                let p = KeyPos(row: k.row, col: k.col)
                if p == layerKey { continue }
                var usage: UInt8
                var built: QMKMods = []
                var extra = 0.0
                switch keymap.action(layer: layer, row: k.row, col: k.col, base: base) {
                case .basic(let u): usage = u
                case .modded(let m, let u): usage = u; built = m
                case .modTap(_, let u), .layerTap(_, let u): usage = u; extra = 0.2
                default: continue
                }
                if built.contains(.ctrl) || built.contains(.gui) { continue }

                // Keys that don't type a character, like Home or Page Down.
                if let name = Self.namedKeys[usage] {
                    offer(.key(name: name, usage: usage), Recipe(
                        layer: layer, layerKey: layerKey, shiftKey: nil, altKey: nil, tap: p,
                        builtInMods: built, cost: layerCost + extra))
                }

                guard let vk = HID.virtualKey(usage, iso: translator.isISO) else { continue }
                for (wantShift, wantAlt) in [(false, false), (true, false), (false, true), (true, true)] {
                    let needShift = wantShift && !built.contains(.shift)
                    let needAlt = wantAlt && !built.contains(.alt)
                    if needShift && shift == nil { continue }
                    if needAlt && alt == nil { continue }
                    if !wantShift && built.contains(.shift) { continue }
                    if !wantAlt && built.contains(.alt) { continue }
                    guard let ch = translator.character(vk: vk, shift: wantShift, alt: wantAlt),
                          ch != " " else { continue }
                    let cost = layerCost + extra + (needShift ? 1 : 0) + (needAlt ? 1.6 : 0)
                    offer(.char(ch), Recipe(
                        layer: layer, layerKey: layerKey,
                        shiftKey: needShift ? shift : nil, altKey: needAlt ? alt : nil,
                        tap: p, builtInMods: built, cost: cost))
                }
            }
        }
    }

    private mutating func offer(_ t: Target, _ r: Recipe) {
        if let old = recipes[t], old.cost <= r.cost { return }
        recipes[t] = r
    }

    private func findMod(layer: Int, avoiding: KeyPos?, _ test: (UInt8) -> Bool) -> KeyPos? {
        // Prefer the left-most one, since layer keys tend to sit on the left too and
        // a right-hand modifier is easier to combine. Fall back to anything.
        var found: [KeyPos] = []
        for k in keymap.keys {
            let p = KeyPos(row: k.row, col: k.col)
            if p == avoiding { continue }
            if case .basic(let u) = keymap.action(layer: layer, row: k.row, col: k.col, base: base), test(u) {
                found.append(p)
            }
        }
        return found.min { a, b in (a.col, a.row) < (b.col, b.row) }
    }

    private func legendFor(_ a: KeyAction) -> String {
        switch a {
        case .none: return ""
        case .transparent: return "▽"
        case .basic(let u), .modTap(_, let u), .layerTap(_, let u):
            if let l = HID.label(u) { return l }
            if let vk = HID.virtualKey(u, iso: translator.isISO), let c = translator.character(vk: vk, shift: false, alt: false) {
                return c.uppercased()
            }
            return String(format: "%02X", u)
        case .modded(let m, let u):
            if let vk = HID.virtualKey(u, iso: translator.isISO),
               let c = translator.character(vk: vk, shift: m.contains(.shift), alt: m.contains(.alt)),
               !m.contains(.ctrl), !m.contains(.gui) {
                return c
            }
            return m.symbols + (HID.label(u) ?? "?")
        case .momentary(let l): return layerKeys[l] != nil ? "\(layerName(l))" : "MO\(l)"
        case .toggle(let l): return "TG\(l)"
        case .to(let l): return "TO\(l)"
        case .defaultLayer(let l): return "DF\(l)"
        case .oneShotLayer(let l): return "OS\(l)"
        case .tapToggle(let l): return "TT\(l)"
        case .layerMod(let l, let m): return "\(m.symbols)L\(l)"
        case .custom(let i): return i < keymap.customKeycodes.count ? keymap.customKeycodes[i].name : "USER\(i)"
        case .lighting(let n): return n
        case .other: return "•"
        }
    }

    static let namedKeys: [UInt8: String] = [
        0x4A: "Home", 0x4D: "End", 0x4B: "Page Up", 0x4E: "Page Down", 0x4C: "Forward Delete",
    ]
}
