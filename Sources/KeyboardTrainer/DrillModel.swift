import AppKit
import SwiftUI

/// Runs one drill: a handful of cards, then a short phrase.
@MainActor
final class DrillModel: ObservableObject {
    enum Phase: Equatable { case asking, correct, done }

    let book: RecipeBook
    let deck: Deck
    let items: [DrillItem]
    var onFinish: (_ completed: Bool) -> Void = { _ in }

    @Published private(set) var index = 0
    @Published private(set) var phase: Phase = .asking
    @Published private(set) var mistakes = 0
    @Published private(set) var revealed = false
    @Published private(set) var hits = 0
    @Published private(set) var feedback: String?
    @Published private(set) var shake = 0
    @Published private(set) var shiftHeld = false
    @Published private(set) var phraseCursor = 0
    @Published private(set) var phraseError = false
    @Published private(set) var firstTry = 0

    private var started = Date()
    private var revealTask: Task<Void, Never>?

    init(book: RecipeBook, deck: Deck, items: [DrillItem]) {
        self.book = book
        self.deck = deck
        self.items = items
        begin()
    }

    var current: DrillItem? { index < items.count ? items[index] : nil }

    /// How many times a new card must be typed before it counts.
    static let learnReps = 2

    var showKeyboard: Bool {
        switch current {
        case .learn: true
        case .review: revealed
        case .phrase: phraseError
        case nil: false
        }
    }

    /// The recipe on screen right now. For phrases it's the next character's.
    var activeRecipe: Recipe? {
        switch current {
        case .learn(_, let r), .review(_, let r): return r
        case .phrase(let p):
            guard phraseCursor < p.count else { return nil }
            return book.recipe(for: .char(String(Array(p)[phraseCursor])))
        case nil: return nil
        }
    }

    // MARK: - Input

    func flagsChanged(_ e: NSEvent) {
        shiftHeld = e.modifierFlags.contains(.shift)
    }

    func setShift(_ held: Bool) { shiftHeld = held }

    /// Returns true if we used the key.
    func keyDown(_ e: NSEvent) -> Bool {
        if e.keyCode == 0x35 { finish(completed: phase == .done || index > 0); return true }
        if e.isARepeat { return true }
        guard phase == .asking, let item = current else { return true }
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) { return false }

        switch item {
        case .learn(let t, _), .review(let t, _):
            if matches(t, e) { correct(t) } else { wrong(t, e) }
        case .phrase(let p):
            let chars = Array(p)
            let want = String(chars[phraseCursor])
            if e.characters == want {
                phraseError = false
                feedback = nil
                phraseCursor += 1
                if phraseCursor >= chars.count {
                    play("Glass")
                    advance(after: 0.7)
                }
            } else if let typed = e.characters, !typed.isEmpty {
                phraseError = true
                mistakes += 1
                shake += 1
                feedback = hint(for: .char(want), typed: typed)
                deck.record(.char(want), grade: .again, seconds: 0)
                play("Funk")
            }
        }
        return true
    }

    private func matches(_ t: Target, _ e: NSEvent) -> Bool {
        switch t {
        case .char(let c): return e.characters == c
        case .key(_, let usage):
            return HID.virtualKey(usage, iso: book.translator.isISO) == e.keyCode
        }
    }

    private func correct(_ t: Target) {
        hits += 1
        feedback = nil
        if case .learn = current, hits < Self.learnReps {
            play("Pop")
            withAnimation(.spring(response: 0.3)) { phase = .correct }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(380))
                self.phase = .asking
                self.feedback = "Once more."
            }
            return
        }
        let secs = Date().timeIntervalSince(started)
        let grade: Grade
        if case .learn = current {
            grade = mistakes == 0 ? .good : .again
        } else if mistakes > 0 {
            grade = .again
        } else if revealed {
            grade = .hard
        } else {
            grade = secs < 1.8 ? .easy : secs < 5 ? .good : .hard
        }
        if mistakes == 0 && !revealed { firstTry += 1 }
        deck.record(t, grade: grade, seconds: secs)
        play("Pop")
        withAnimation(.spring(response: 0.3)) { phase = .correct }
        advance(after: 0.55)
    }

    private func wrong(_ t: Target, _ e: NSEvent) {
        guard let typed = e.characters, !typed.isEmpty else { return }
        mistakes += 1
        shake += 1
        feedback = hint(for: t, typed: typed)
        play("Funk")
        withAnimation(.spring(response: 0.4)) { revealed = true }
    }

    /// Works out what you probably did wrong, so the hint is useful.
    private func hint(for t: Target, typed: String) -> String {
        guard let r = book.recipe(for: t) else { return "Not quite." }
        let shown = typed.trimmingCharacters(in: .controlCharacters)
        let youTyped = shown.isEmpty ? "Not quite." : "You typed \(shown == " " ? "a space" : shown)."
        let tr = book.translator
        let tapUsage = usage(at: r.tap, layer: r.layer)
        if let u = tapUsage, let vk = HID.virtualKey(u, iso: tr.isISO) {
            if r.shiftKey != nil, typed == tr.character(vk: vk, shift: false, alt: false) {
                return "\(youTyped) Nearly! Hold ⇧ as well."
            }
            if r.layerKey != nil, let bu = usage(at: r.tap, layer: book.base),
               let bvk = HID.virtualKey(bu, iso: tr.isISO),
               typed.lowercased() == tr.character(vk: bvk, shift: false, alt: false) {
                return "\(youTyped) Hold \(book.layerName(r.layer)) first, then press the key."
            }
        }
        return youTyped
    }

    private func usage(at p: KeyPos, layer: Int) -> UInt8? {
        switch book.keymap.action(layer: layer, row: p.row, col: p.col, base: book.base) {
        case .basic(let u), .modded(_, let u), .modTap(_, let u), .layerTap(_, let u): u
        default: nil
        }
    }

    // MARK: - Flow

    func revealNow() {
        withAnimation(.spring(response: 0.4)) { revealed = true }
    }

    private func begin() {
        started = Date()
        mistakes = 0
        hits = 0
        revealed = false
        feedback = nil
        phraseCursor = 0
        phraseError = false
        phase = index < items.count ? .asking : .done
        revealTask?.cancel()
        if case .review = current {
            // If you're stuck, show the answer after a while rather than leaving you hanging.
            revealTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(7))
                if !Task.isCancelled, let self, self.phase == .asking { self.revealNow() }
            }
        }
    }

    private func advance(after seconds: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                self.index += 1
                self.begin()
            }
            if self.phase == .done {
                self.deck.save()
                try? await Task.sleep(for: .seconds(1.8))
                self.finish(completed: true)
            }
        }
    }

    private var finished = false
    func finish(completed: Bool) {
        guard !finished else { return }
        finished = true
        revealTask?.cancel()
        deck.save()
        onFinish(completed)
    }

    private func play(_ name: String) {
        guard deck.settings.sounds, let s = NSSound(named: NSSound.Name(name)) else { return }
        s.volume = 0.25
        s.play()
    }
}
