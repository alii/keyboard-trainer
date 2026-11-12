import SwiftUI

/// The glass card that floats over whatever you're doing.
struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            content
                .clipShape(shape)
                .background(VisualEffect().clipShape(shape))
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct DrillView: View {
    @ObservedObject var model: DrillModel

    var body: some View {
        GlassCard {
            VStack(spacing: 18) {
                header
                Group {
                    if model.phase == .done { doneView } else { cardView }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(Shake(amount: CGFloat(model.shake)))
        .animation(.spring(response: 0.25, dampingFraction: 0.3), value: model.shake)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(Array(model.items.enumerated()), id: \.offset) { i, _ in
                    Capsule()
                        .fill(i < model.index ? AnyShapeStyle(Palette.good) : i == model.index ? AnyShapeStyle(Color.primary.opacity(0.7)) : AnyShapeStyle(Color.primary.opacity(0.15)))
                        .frame(width: i == model.index ? 22 : 8, height: 6)
                }
            }
            .animation(.spring(response: 0.4), value: model.index)
            Spacer()
            Text(model.phase == .done ? "" : "esc for later")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Card

    @ViewBuilder private var cardView: some View {
        switch model.current {
        case .learn(let t, let r):
            VStack(spacing: 16) {
                prompt(t, badge: "NEW", subtitle: "Type it \(DrillModel.learnReps) times")
                recipeChips(r)
                keyboard
                feedbackLine
            }
        case .review(let t, let r):
            VStack(spacing: 16) {
                prompt(t, badge: nil, subtitle: model.revealed ? "Here's how" : "Type it")
                if model.revealed {
                    recipeChips(r)
                    keyboard
                } else {
                    Button("Show me") { model.revealNow() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(.primary.opacity(0.07)))
                }
                feedbackLine
            }
        case .phrase(let p):
            VStack(spacing: 16) {
                Text("Now type this")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                phraseText(p)
                if model.showKeyboard, let r = model.activeRecipe {
                    recipeChips(r)
                    keyboard
                }
                feedbackLine
            }
        case nil:
            EmptyView()
        }
    }

    private func prompt(_ t: Target, badge: String?, subtitle: String) -> some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(model.phase == .correct ? AnyShapeStyle(Palette.good.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)))
                Text(t.display)
                    .font(.system(size: t.display.count > 1 ? 22 : 54, weight: .bold, design: .rounded))
                    .foregroundStyle(model.phase == .correct ? .white : .primary)
                    .contentTransition(.identity)
                if model.phase == .correct {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white, Palette.good)
                        .offset(x: 40, y: -40)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 104, height: 104)
            .scaleEffect(model.phase == .correct ? 1.05 : 1)

            VStack(alignment: .leading, spacing: 6) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.tap.gradient))
                }
                Text(t.spokenName.capitalizedFirst)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle + (model.hits > 0 && badge != nil ? "  ·  \(model.hits)/\(DrillModel.learnReps)" : ""))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
    }

    private func recipeChips(_ r: Recipe) -> some View {
        let b = model.book
        var parts: [(String, String, Color, Bool)] = []
        if let p = r.layerKey { parts.append(("Hold", b.legend(layer: b.base, p), Palette.layer, false)) }
        if r.shiftKey != nil { parts.append(("Hold", "⇧ Shift", Palette.shift, model.shiftHeld)) }
        if r.altKey != nil { parts.append(("Hold", "⌥ Option", Palette.alt, false)) }
        parts.append(("Tap", b.legend(layer: r.layer, r.tap), Palette.tap, false))

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    if i > 0 {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 6) {
                        Text(part.0).foregroundStyle(.white.opacity(0.75))
                        Text(part.1).foregroundStyle(.white)
                        if part.3 { Image(systemName: "checkmark").foregroundStyle(.white) }
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Capsule().fill(part.2.gradient))
                }
            }
            if let where_ = whereIsLayerKey(r) {
                Text(where_)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func whereIsLayerKey(_ r: Recipe) -> String? {
        guard let p = r.layerKey else { return nil }
        let km = model.book.keymap
        let maxRow = km.keys.map(\.row).max() ?? 0
        let minCol = km.keys.filter { $0.row == p.row }.map(\.col).min() ?? 0
        let maxCol = km.keys.filter { $0.row == p.row }.map(\.col).max() ?? 0
        let vertical = p.row == maxRow ? "bottom" : p.row == 0 ? "top" : nil
        let horizontal = p.col == minCol ? "left" : p.col == maxCol ? "right" : nil
        let name = model.book.layerName(r.layer)
        if let v = vertical, let h = horizontal { return "\(name) is your \(v)-\(h) key. Keep holding it while you press the rest." }
        return "Keep holding \(name) while you press the rest."
    }

    private var keyboard: some View {
        let r = model.activeRecipe
        let b = model.book
        return KeyboardView(
            keymap: b.keymap,
            legend: { p in b.legend(layer: r?.layer ?? b.base, p) },
            role: { p in
                guard let r else { return .idle }
                if p == r.tap { return .tap }
                if p == r.layerKey { return .layer }
                if p == r.shiftKey { return .shift }
                if p == r.altKey { return .alt }
                return .dim
            },
            step: { p in
                guard let r else { return nil }
                let order = r.heldKeys + [r.tap]
                return order.count > 1 ? order.firstIndex(of: p).map { $0 + 1 } : nil
            })
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
    }

    private var feedbackLine: some View {
        Text(model.feedback ?? " ")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(model.feedback?.hasPrefix("Once") == true ? Color.secondary : Palette.bad)
            .frame(height: 16)
            .animation(.easeOut(duration: 0.15), value: model.feedback)
    }

    private func phraseText(_ p: String) -> some View {
        let chars = Array(p)
        return HStack(spacing: 1) {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                let isCurrent = i == model.phraseCursor
                Text(String(ch) == " " ? "␣" : String(ch))
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(i < model.phraseCursor ? Palette.good : isCurrent ? (model.phraseError ? Palette.bad : .primary) : .primary.opacity(String(ch) == " " ? 0.15 : 0.45))
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isCurrent ? (model.phraseError ? Palette.bad.opacity(0.18) : Color.primary.opacity(0.1)) : .clear))
                    .overlay(alignment: .bottom) {
                        if isCurrent {
                            Capsule().fill(model.phraseError ? Palette.bad : Palette.tap).frame(height: 3).offset(y: 4)
                        }
                    }
            }
        }
        .animation(.spring(response: 0.25), value: model.phraseCursor)
    }

    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white, Palette.good)
                .symbolEffect(.bounce, value: model.phase)
            Text("Nice one")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            let cards = model.items.filter { $0.target != nil }.count
            Text("\(model.firstTry) of \(cards) first try. See you in \(model.deck.settings.minutesBetweenDrills) minutes.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(amount * .pi * 4), y: 0))
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
