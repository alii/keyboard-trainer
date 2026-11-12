import AppKit
import SwiftUI

/// Plays a scripted drill over a clean backdrop, for README screenshots and GIFs.
/// Run with --demo drill or --demo map. Nothing gets saved. The backdrop stays up
/// until you quit the app, so a recording can never catch the desktop behind it.
@MainActor
enum Demo {
    static var backdrop: NSWindow?
    static var panel: FloatingPanel?

    static var light: Bool { ProcessInfo.processInfo.environment["KT_APPEARANCE"] == "light" }

    static func run(_ which: String, keymap: Keymap) {
        NSApp.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        let screen = NSScreen.screens[0]
        let v = screen.visibleFrame
        let rect = NSRect(x: v.midX - 470, y: v.maxY - 700, width: 940, height: 700)
        showBackdrop(rect)

        // screencapture wants top-left coordinates.
        let top = screen.frame.maxY - rect.maxY
        print("CAPTURE \(Int(rect.minX)),\(Int(top)),\(Int(rect.width)),\(Int(rect.height))")
        fflush(stdout)

        let book = RecipeBook(keymap: keymap)
        if which == "map" { map(book, screen) } else { drill(book, screen) }
    }

    private static func showBackdrop(_ rect: NSRect) {
        let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        w.contentView = NSHostingView(rootView: Wallpaper())
        w.orderFrontRegardless()
        backdrop = w
    }

    private static func key(_ c: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: 0)!
    }

    private static func drill(_ book: RecipeBook, _ screen: NSScreen) {
        let deck = Deck(ephemeral: true)
        let items: [DrillItem] = [
            .learn(.char("!"), book.recipe(for: .char("!"))!),
            .review(.char("#"), book.recipe(for: .char("#"))!),
            .phrase("ali@home.uk!"),
        ]
        let model = DrillModel(book: book, deck: deck, items: items)
        model.onFinish = { _ in panel?.dismiss() }
        let p = FloatingPanel(DrillView(model: model))
        panel = p
        p.present(on: screen)

        var t = 1.6
        func at(_ dt: Double, _ f: @escaping () -> Void) {
            t += dt
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { f() }
        }
        // Learn "!": hold Fn + Shift, tap 1, twice.
        at(0) { model.setShift(true) }
        at(0.8) { _ = model.keyDown(key("!")) }
        at(0.9) { _ = model.keyDown(key("!")) }
        at(0.3) { model.setShift(false) }
        // Review "#": get it wrong first, then right.
        at(2.2) { _ = model.keyDown(key("3")) }
        at(2.6) { _ = model.keyDown(key("#")) }
        // Type a phrase.
        at(1.6) {}
        for ch in "ali@home.uk!" {
            at(ch == "@" || ch == "!" ? 0.45 : 0.16) { _ = model.keyDown(key(String(ch))) }
        }
    }

    private static func map(_ book: RecipeBook, _ screen: NSScreen) {
        let model = CheatSheetModel(book: book, deck: Deck(ephemeral: true))
        let p = FloatingPanel(CheatSheetView(model: model))
        panel = p
        p.present(on: screen)
        let steps: [(Double, () -> Void)] = [
            (2.0, { model.shift = true }),
            (1.6, { model.shift = false; withAnimation(.spring(response: 0.3)) { model.layer = 2 } }),
            (1.8, { withAnimation(.spring(response: 0.3)) { model.search = "("; model.layer = 2 } }),
            (2.2, { withAnimation(.spring(response: 0.3)) { model.search = "@"; model.layer = 0 } }),
            (2.2, { panel?.dismiss() }),
        ]
        var t = 0.0
        for (dt, f) in steps {
            t += dt
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f)
        }
    }
}

/// A soft, colourful backdrop so the glass has something to show off.
private struct Wallpaper: View {
    var body: some View {
        let light = Demo.light
        ZStack {
            LinearGradient(colors: light
                           ? [Color(red: 0.93, green: 0.94, blue: 1.0), Color(red: 0.99, green: 0.92, blue: 0.95)]
                           : [Color(red: 0.10, green: 0.12, blue: 0.30), Color(red: 0.30, green: 0.12, blue: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.98, green: 0.50, blue: 0.30).opacity(light ? 0.45 : 1)).frame(width: 420).blur(radius: 120).offset(x: -300, y: 180)
            Circle().fill(Color(red: 0.30, green: 0.55, blue: 1.0).opacity(light ? 0.45 : 1)).frame(width: 460).blur(radius: 130).offset(x: 320, y: -160)
            Circle().fill(Color(red: 0.62, green: 0.40, blue: 1.0).opacity(light ? 0.4 : 1)).frame(width: 360).blur(radius: 110).offset(x: 120, y: 260)
        }
    }
}
