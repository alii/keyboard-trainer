import Foundation

/// One physical key: where it sits in the matrix and where it sits on the board.
struct PhysicalKey: Codable, Hashable {
    let row: Int
    let col: Int
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

struct CustomKeycode: Codable, Hashable {
    let name: String
    let title: String?
}

/// Everything we know about a keyboard: its shape and what every layer does.
struct Keymap: Codable {
    let name: String
    let vendorID: Int
    let productID: Int
    let vialProtocol: Int
    let rows: Int
    let cols: Int
    let keys: [PhysicalKey]
    /// layers[layer][row * cols + col]
    let layers: [[UInt16]]
    let customKeycodes: [CustomKeycode]
    let readAt: Date

    var width: Double { keys.map { $0.x + $0.w }.max() ?? 0 }
    var height: Double { keys.map { $0.y + $0.h }.max() ?? 0 }

    func raw(layer: Int, row: Int, col: Int) -> UInt16 {
        layers[layer][row * cols + col]
    }

    /// What a key does on a layer, falling through transparent keys like the firmware does.
    func action(layer: Int, row: Int, col: Int, base: Int = 0) -> KeyAction {
        var l = layer
        while true {
            let a = KeyAction(raw(layer: l, row: row, col: col), vialProtocol: vialProtocol)
            if case .transparent = a, l != base { l = base; continue }
            return a
        }
    }

    // MARK: - Reading from a keyboard

    static func read(from reader: VialReader) throws -> Keymap {
        guard let vial = reader.vialProtocol() else {
            throw VialReader.Failure.badDefinition("This keyboard speaks VIA but not Vial, so it can't tell me its shape.")
        }
        let def = try reader.vialDefinition()
        guard let matrix = def["matrix"] as? [String: Any],
              let rows = matrix["rows"] as? Int, let cols = matrix["cols"] as? Int,
              let layouts = def["layouts"] as? [String: Any],
              let kle = layouts["keymap"] as? [Any] else {
            throw VialReader.Failure.badDefinition("missing matrix or layout")
        }
        let layerCount = try reader.layerCount()
        let flat = try reader.keymapBuffer(layers: layerCount, rows: rows, cols: cols)
        let perLayer = rows * cols
        let layers = (0..<layerCount).map { Array(flat[($0 * perLayer)..<(($0 + 1) * perLayer)]) }
        let customs = (def["customKeycodes"] as? [[String: Any]] ?? []).map {
            CustomKeycode(name: $0["name"] as? String ?? "?", title: $0["title"] as? String)
        }
        return Keymap(
            name: def["name"] as? String ?? reader.productName,
            vendorID: reader.vendorID, productID: reader.productID,
            vialProtocol: vial, rows: rows, cols: cols,
            keys: parseKLE(kle), layers: layers, customKeycodes: customs, readAt: Date())
    }

    /// Parses a keyboard-layout-editor layout, where each key's first label is "row,col".
    /// Keys in alternative layout options (label 4 like "0,1") are dropped unless they're option 0.
    static func parseKLE(_ rows: [Any]) -> [PhysicalKey] {
        var keys: [PhysicalKey] = []
        var y = 0.0
        var rx = 0.0, ry = 0.0
        for case let row as [Any] in rows {
            var x = rx
            var w = 1.0, h = 1.0
            for item in row {
                if let props = item as? [String: Any] {
                    if let v = props["rx"] as? Double { rx = v; x = v }
                    if let v = props["ry"] as? Double { ry = v; y = v }
                    if let v = props["x"] as? Double { x += v }
                    if let v = props["y"] as? Double { y += v }
                    if let v = props["w"] as? Double { w = v }
                    if let v = props["h"] as? Double { h = v }
                } else if let label = item as? String {
                    let parts = label.split(separator: "\n", omittingEmptySubsequences: false)
                    let rc = parts.first.map { $0.split(separator: ",") } ?? []
                    var keep = true
                    if parts.count > 3 {
                        let option = parts[3].split(separator: ",")
                        if option.count == 2, option[1] != "0" { keep = false }
                    }
                    if keep, rc.count == 2, let r = Int(rc[0]), let c = Int(rc[1]) {
                        keys.append(PhysicalKey(row: r, col: c, x: x, y: y, w: w, h: h))
                    }
                    x += w
                    w = 1; h = 1
                }
            }
            y += 1
            _ = ry
        }
        return keys
    }

    // MARK: - Cache

    static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keyboard Trainer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("keymap.json")
    }

    static func loadCached() -> Keymap? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Keymap.self, from: data)
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: Self.cacheURL, options: .atomic) }
    }
}
