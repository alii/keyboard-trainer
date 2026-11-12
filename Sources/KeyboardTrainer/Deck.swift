import Foundation

/// How a single card is doing. Spaced repetition, a bit like Anki.
struct CardState: Codable {
    var ease: Double = 2.5
    var interval: TimeInterval = 0
    var due: Date = .distantPast
    var reps = 0
    var lapses = 0
    var introduced: Date?
    var lastSeconds: Double?
}

enum Grade {
    case again, hard, good, easy
}

struct Settings: Codable {
    var minutesBetweenDrills: Int = 25
    var pausedUntil: Date?
    var cardsPerDrill = 5
    var newPerDrill = 2
    var sounds = true
}

/// The order we teach things in: the stuff you reach for most comes first.
enum Curriculum {
    static let chars: [String] = [
        "!", "1", "2", "@", "\"", "3", "#", "?", "(", ")", "9", "0", "-", "_", "4", "5",
        "=", "+", "6", "7", "8", "'", ":", "/", "&", "*", "%", "£", "$", "[", "]", "{", "}",
        "<", ">", "~", "|", "\\", "`", "^",
    ]
    static let keys = ["Home", "End", "Page Up", "Page Down"]

    /// Everything worth teaching on this board, in order. Skips things you can already type
    /// the normal way (a plain key on the base layer, where you'd expect it).
    static func targets(in book: RecipeBook) -> [Target] {
        var out: [Target] = []
        for c in chars {
            let t = Target.char(c)
            guard let r = book.recipe(for: t) else { continue }
            if r.layer == book.base && r.shiftKey == nil && ["'", ";", ",", "."].contains(c) { continue }
            out.append(t)
            if c == "-" {
                // Slot the navigation keys in after the first batch of symbols.
                for k in keys {
                    if let (t, _) = book.recipes.first(where: { $0.key.display == k }) { out.append(t) }
                }
            }
        }
        return out
    }

    static let phrases: [String] = [
        "hi!", "what?!", "ali@home.uk", "#1 fan", "\"quote\"", "(a + b) * 2", "x = y - 1", "50% off!",
        "£20 & £5", "snake_case", "[1, 2, 3]", "{ ok: true }", "~/code", "a != b", "me_42@mail.com",
        "10:30", "a < b > c", "#tag @you", "^_^", "*bold*", "x += 1", "x | y", "1 + 1 = 2",
        "it's \"fine\"", "$HOME", "wait... why?", "(hello)", "fn(x) => x * 2", "#[derive]", "a & b",
        "100%!", "@here", "~$ ls -la", "<div>", "C:\\temp", "`code`", "2^8 = 256", "-> ok", "[x]",
    ]
}

/// The deck and everything else we remember between launches.
final class Deck {
    private(set) var cards: [String: CardState] = [:]
    var settings = Settings()
    var lastDrill: Date?

    private struct Stored: Codable {
        var cards: [String: CardState]
        var settings: Settings
        var lastDrill: Date?
    }

    static var url: URL { Keymap.cacheURL.deletingLastPathComponent().appendingPathComponent("progress.json") }

    /// A throwaway deck for demos. Nothing it learns gets saved.
    private var ephemeral = false
    init(ephemeral: Bool) { self.ephemeral = ephemeral }

    init() {
        if let data = try? Data(contentsOf: Self.url),
           let s = try? JSONDecoder().decode(Stored.self, from: data) {
            cards = s.cards
            settings = s.settings
            lastDrill = s.lastDrill
        }
    }

    func save() {
        if ephemeral { return }
        let s = Stored(cards: cards, settings: settings, lastDrill: lastDrill)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: Self.url, options: .atomic) }
    }

    func state(_ t: Target) -> CardState? { cards[t.id] }

    func isLearned(_ t: Target) -> Bool { cards[t.id]?.introduced != nil }

    var nextDrill: Date {
        let base = lastDrill ?? Date().addingTimeInterval(-Double(settings.minutesBetweenDrills * 60) + 90)
        var next = base.addingTimeInterval(Double(settings.minutesBetweenDrills * 60))
        if let p = settings.pausedUntil, p > next { next = p }
        return next
    }

    /// Picks what to practise: overdue cards first, then a couple of new ones.
    func buildDrill(book: RecipeBook, force: Bool) -> [DrillItem] {
        let all = Curriculum.targets(in: book)
        let now = Date()
        let due = all.filter { t in
            guard let s = cards[t.id], s.introduced != nil else { return false }
            return s.due <= now
        }.sorted { (cards[$0.id]!.due) < (cards[$1.id]!.due) }

        var items: [DrillItem] = []
        for t in due.prefix(settings.cardsPerDrill) {
            if let r = book.recipe(for: t) { items.append(.review(t, r)) }
        }
        if due.count < settings.cardsPerDrill + 2 {
            let fresh = all.filter { !isLearned($0) }.prefix(settings.newPerDrill)
            for t in fresh { if let r = book.recipe(for: t) { items.append(.learn(t, r)) } }
        }
        if items.isEmpty && force {
            // Nothing due: warm up on the shakiest cards.
            let shaky = all.filter(isLearned).sorted { (cards[$0.id]?.interval ?? 0) < (cards[$1.id]?.interval ?? 0) }
            for t in shaky.prefix(4) { if let r = book.recipe(for: t) { items.append(.review(t, r)) } }
        }
        if let p = phrase(book: book, featuring: items.compactMap(\.target)) { items.append(.phrase(p)) }
        return items
    }

    /// A short thing to type that only uses symbols you've met.
    private func phrase(book: RecipeBook, featuring: [Target]) -> String? {
        let known = Set(Curriculum.targets(in: book).filter(isLearned).map(\.display) + featuring.map(\.display))
        guard known.count >= 3 else { return nil }
        let plain = CharacterSet.letters.union(.whitespaces)
        let usable = Curriculum.phrases.filter { p in
            p.allSatisfy { ch in
                let s = String(ch)
                if s.unicodeScalars.allSatisfy(plain.contains) { return true }
                return known.contains(s) || ([",", ".", ";", "'"].contains(s) && book.recipe(for: .char(s)) != nil)
            }
        }
        let wanted = Set(featuring.map(\.display))
        let scored = usable.map { p in (p, p.filter { wanted.contains(String($0)) }.count) }
        let best = scored.map(\.1).max() ?? 0
        return scored.filter { $0.1 == best }.randomElement()?.0
    }

    func record(_ t: Target, grade: Grade, seconds: Double) {
        var s = cards[t.id] ?? CardState()
        let now = Date()
        if s.introduced == nil { s.introduced = now }
        s.reps += 1
        s.lastSeconds = seconds
        switch grade {
        case .again:
            s.lapses += 1
            s.ease = max(1.3, s.ease - 0.2)
            s.interval = 10 * 60
        case .hard:
            s.ease = max(1.3, s.ease - 0.15)
            s.interval = max(10 * 60, s.interval * 1.2)
        case .good:
            s.interval = s.interval == 0 ? 10 * 60 : (s.interval < 3600 ? 3600 : s.interval * s.ease)
        case .easy:
            s.ease += 0.1
            s.interval = s.interval == 0 ? 3600 : max(3 * 3600, s.interval * s.ease * 1.3)
        }
        s.due = now.addingTimeInterval(s.interval)
        cards[t.id] = s
    }

    func progress(book: RecipeBook) -> (learned: Int, total: Int) {
        let all = Curriculum.targets(in: book)
        return (all.filter(isLearned).count, all.count)
    }
}

enum DrillItem: Identifiable {
    case learn(Target, Recipe)
    case review(Target, Recipe)
    case phrase(String)

    var id: String {
        switch self {
        case .learn(let t, _): "learn-" + t.id
        case .review(let t, _): "review-" + t.id
        case .phrase(let p): "phrase-" + p
        }
    }

    var target: Target? {
        switch self {
        case .learn(let t, _), .review(let t, _): t
        case .phrase: nil
        }
    }

    var recipe: Recipe? {
        switch self {
        case .learn(_, let r), .review(_, let r): r
        case .phrase: nil
        }
    }
}
