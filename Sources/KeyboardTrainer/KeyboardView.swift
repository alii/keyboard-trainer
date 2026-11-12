import SwiftUI

/// The role a key plays in what we're showing.
enum KeyRole {
    case idle, dim, layer, shift, alt, tap, pressedHint
}

struct Palette {
    static let tap = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let layer = Color(red: 0.98, green: 0.56, blue: 0.24)
    static let shift = Color(red: 0.62, green: 0.45, blue: 1.0)
    static let alt = Color(red: 0.25, green: 0.80, blue: 0.62)
    static let good = Color(red: 0.30, green: 0.85, blue: 0.50)
    static let bad = Color(red: 1.0, green: 0.38, blue: 0.40)

    static func color(_ r: KeyRole) -> Color {
        switch r {
        case .layer: layer
        case .shift: shift
        case .alt: alt
        case .tap, .pressedHint: tap
        default: .primary
        }
    }
}

/// Draws the board from the keyboard's own layout, with keys lit up by role.
struct KeyboardView: View {
    let keymap: Keymap
    let legend: (KeyPos) -> String
    let role: (KeyPos) -> KeyRole
    var step: (KeyPos) -> Int? = { _ in nil }
    var compact = false

    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / keymap.width
            ZStack(alignment: .topLeading) {
                ForEach(keymap.keys, id: \.self) { k in
                    let p = KeyPos(row: k.row, col: k.col)
                    KeycapView(label: legend(p), role: role(p), step: step(p), unit: unit, pulse: pulse)
                        .frame(width: k.w * unit - gap(unit), height: k.h * unit - gap(unit))
                        .offset(x: k.x * unit + gap(unit) / 2, y: k.y * unit + gap(unit) / 2)
                }
            }
        }
        .aspectRatio(keymap.width / keymap.height, contentMode: .fit)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func gap(_ unit: Double) -> Double { max(3, unit * 0.1) }
}

private struct KeycapView: View {
    let label: String
    let role: KeyRole
    let step: Int?
    let unit: Double
    let pulse: Bool

    var body: some View {
        let lit = role != .idle && role != .dim
        let tint = Palette.color(role)
        ZStack {
            RoundedRectangle(cornerRadius: unit * 0.18, style: .continuous)
                .fill(lit ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(role == .dim ? 0.04 : 0.08)))
            RoundedRectangle(cornerRadius: unit * 0.18, style: .continuous)
                .strokeBorder(Color.white.opacity(lit ? 0.35 : 0.08), lineWidth: 0.75)
            Text(label)
                .font(.system(size: fontSize, weight: lit ? .bold : .medium, design: .rounded))
                .foregroundStyle(lit ? Color.white : Color.primary.opacity(role == .dim ? 0.25 : 0.7))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(.horizontal, 2)
            if let step {
                Text("\(step)")
                    .font(.system(size: unit * 0.22, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(width: unit * 0.3, height: unit * 0.3)
                    .background(Circle().fill(.white))
                    .offset(x: unit * 0.34, y: -unit * 0.34)
            }
        }
        .shadow(color: lit ? tint.opacity(pulse && role == .tap ? 0.75 : 0.35) : .clear, radius: lit ? unit * 0.25 : 0)
        .scaleEffect(role == .tap && pulse ? 1.06 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: role)
    }

    private var fontSize: Double {
        let base = unit * (label.count <= 1 ? 0.42 : label.count <= 3 ? 0.27 : 0.2)
        return max(8, base)
    }
}
