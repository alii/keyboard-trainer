import SwiftUI

@MainActor
final class CheatSheetModel: ObservableObject {
    let book: RecipeBook
    let deck: Deck
    @Published var layer: Int
    @Published var shift = false
    @Published var search: String?

    init(book: RecipeBook, deck: Deck) {
        self.book = book
        self.deck = deck
        layer = book.base
    }

    var layers: [Int] { [book.base] + book.layerKeys.keys.sorted() }

    /// Symbols this board can't type at all with the current input source.
    var missing: [String] {
        Curriculum.chars.filter { book.recipe(for: .char($0)) == nil }
    }

    func legend(_ p: KeyPos) -> String {
        if shift, case let a = book.keymap.action(layer: layer, row: p.row, col: p.col, base: book.base) {
            switch a {
            case .basic(let u), .modTap(_, let u), .layerTap(_, let u):
                if let vk = HID.virtualKey(u, iso: book.translator.isISO),
                   HID.label(u) == nil,
                   let c = book.translator.character(vk: vk, shift: true, alt: false) {
                    return c
                }
            default: break
            }
        }
        return book.legend(layer: layer, p)
    }
}

/// The whole map at a glance. Pick a layer, hold Shift to see shifted symbols,
/// or type a symbol to see how to get it.
struct CheatSheetView: View {
    @ObservedObject var model: CheatSheetModel

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.book.keymap.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(model.book.translator.isISO ? "ISO" : "ANSI")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.primary.opacity(0.08)))
                    Spacer()
                    let p = model.deck.progress(book: model.book)
                    Text("\(p.learned) of \(p.total) learned")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    ForEach(model.layers, id: \.self) { l in
                        let on = model.layer == l
                        Button {
                            withAnimation(.spring(response: 0.3)) { model.layer = l }
                        } label: {
                            Text(model.book.layerName(l))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(on ? .white : .primary)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(on ? AnyShapeStyle((l == model.book.base ? Palette.tap : Palette.layer).gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Label(model.shift ? "Shift held" : "Hold ⇧ for symbols", systemImage: "shift")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.shift ? Palette.shift : .secondary)
                }

                KeyboardView(
                    keymap: model.book.keymap,
                    legend: model.legend,
                    role: { p in
                        if let s = model.search, let r = model.book.recipe(for: .char(s)) {
                            if p == r.tap { return .tap }
                            if p == r.layerKey { return .layer }
                            if p == r.shiftKey { return .shift }
                            return .dim
                        }
                        if model.layer != model.book.base, p == model.book.layerKeys[model.layer] { return .layer }
                        return .idle
                    })

                HStack {
                    if let s = model.search {
                        if let r = model.book.recipe(for: .char(s)) {
                            Text(describe(s, r))
                        } else {
                            Text("\(s) isn't on your board. You could add it in Vial.")
                        }
                    } else {
                        Text("Type any symbol to see where it lives.")
                    }
                    Spacer()
                    if !model.missing.isEmpty {
                        Text("Not on your board: " + model.missing.joined(separator: " "))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .frame(width: 620)
    }

    private func describe(_ s: String, _ r: Recipe) -> String {
        var steps: [String] = []
        if let p = r.layerKey { steps.append("hold \(model.book.legend(layer: model.book.base, p))") }
        if r.shiftKey != nil { steps.append("hold ⇧") }
        if r.altKey != nil { steps.append("hold ⌥") }
        steps.append("tap \(model.book.legend(layer: r.layer, r.tap))")
        return "\(s)  =  " + steps.joined(separator: ", then ")
    }
}
