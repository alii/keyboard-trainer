import AppKit
import Carbon
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let deck = Deck()
    private let watcher = KeyboardWatcher()
    private var keymap: Keymap? = Keymap.loadCached()
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel?
    private var drill: DrillModel?
    private var cheat: CheatSheetModel?
    private var tick: Timer?
    private var waitingSince: Date?
    private var lastBlocker: ScreenGuard.Reason?
    private var readNote: String?
    private var hotKeys: [EventHotKeyRef?] = []

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "Keyboard Trainer")
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Trainer")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        watcher.onRead = { [weak self] result in self?.didRead(result) }
        watcher.start()

        // Check a few times a minute. It's a cheap check, and it keeps the timer honest across sleep.
        tick = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        tick?.tolerance = 1
        registerHotKeys()

        if let i = CommandLine.arguments.firstIndex(of: "--demo"), let km = keymap {
            let which = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : "drill"
            tick?.invalidate()
            Demo.run(which, keymap: km)
            return
        }
        if CommandLine.arguments.contains("--drill") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.startDrill(force: true) }
        }
        if CommandLine.arguments.contains("--map") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showCheatSheet() }
        }
    }

    private func didRead(_ result: Result<Keymap, Error>) {
        switch result {
        case .success(let km):
            km.save()
            keymap = km
            readNote = nil
        case .failure(let e):
            readNote = "\(e)"
        }
    }

    // MARK: - Scheduling

    private func check() {
        guard panel == nil, keymap != nil else { return }
        let now = Date()
        guard now >= deck.nextDrill else { waitingSince = nil; return }
        if waitingSince == nil { waitingSince = now }
        lastBlocker = ScreenGuard.blocker(waited: now.timeIntervalSince(waitingSince!))
        if lastBlocker == nil { startDrill(force: false) }
    }

    private func book() -> RecipeBook? {
        keymap.map { RecipeBook(keymap: $0) }
    }

    func startDrill(force: Bool) {
        guard panel == nil, let book = book() else { return }
        let items = deck.buildDrill(book: book, force: force)
        guard !items.isEmpty else {
            deck.lastDrill = Date()
            deck.save()
            return
        }
        let model = DrillModel(book: book, deck: deck, items: items)
        let panel = FloatingPanel(DrillView(model: model))
        panel.onKeyDown = { [weak model] e in model?.keyDown(e) ?? false }
        panel.onFlags = { [weak model] e in model?.flagsChanged(e) }
        // Clicking away counts as "later". Your click still lands where you aimed it.
        panel.onResign = { [weak model] in model?.finish(completed: false) }
        model.onFinish = { [weak self] completed in
            guard let self else { return }
            if completed || model.index > 0 {
                self.deck.lastDrill = Date()
            } else {
                // Snoozed: try again in ten minutes.
                self.deck.lastDrill = Date().addingTimeInterval(-Double(self.deck.settings.minutesBetweenDrills * 60) + 600)
            }
            self.deck.save()
            self.closePanel()
        }
        self.drill = model
        self.panel = panel
        panel.present()
    }

    private func closePanel() {
        let p = panel
        panel = nil
        drill = nil
        cheat = nil
        waitingSince = nil
        p?.dismiss()
    }

    func showCheatSheet() {
        if cheat != nil { closePanel(); return }
        guard panel == nil, let book = book() else { return }
        let model = CheatSheetModel(book: book, deck: deck)
        let panel = FloatingPanel(CheatSheetView(model: model))
        panel.onKeyDown = { [weak self, weak model] e in
            guard let model else { return false }
            if e.keyCode == 0x35 { self?.closePanel(); return true }
            if let c = e.characters, !c.isEmpty, c.unicodeScalars.allSatisfy({ $0.value >= 0x21 }) {
                withAnimation(.spring(response: 0.3)) {
                    model.search = c
                    if let r = model.book.recipe(for: .char(c)) { model.layer = r.layer }
                }
            }
            return true
        }
        panel.onFlags = { [weak model] e in model?.shift = e.modifierFlags.contains(.shift) }
        panel.onResign = { [weak self] in self?.closePanel() }
        cheat = model
        self.panel = panel
        panel.present()
    }

    // MARK: - Global hot keys (⌃⌥K for the map, ⌃⌥D to drill now)

    private func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async {
                let app = NSApp.delegate as! AppDelegate
                if id.id == 1 { app.showCheatSheet() } else { app.startDrill(force: true) }
            }
            return noErr
        }, 1, &spec, nil, nil)
        for (i, key) in [(1, kVK_ANSI_K), (2, kVK_ANSI_D)] {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey),
                                EventHotKeyID(signature: OSType(0x4B425452), id: UInt32(i)),
                                GetApplicationEventTarget(), 0, &ref)
            hotKeys.append(ref)
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let book = book()

        if let km = keymap, let book {
            let p = deck.progress(book: book)
            menu.addItem(header(km.name, "\(p.learned) of \(p.total) learned"))
        } else {
            menu.addItem(header("No keyboard yet", "Plug your Vial keyboard in with USB once"))
        }
        menu.addItem(.separator())

        menu.addItem(item("Practise now", "play.fill", "d", [.control, .option], #selector(practise)))
        menu.addItem(item("Show my layers", "square.grid.3x3.square", "k", [.control, .option], #selector(map)))
        menu.addItem(disabled(statusLine()))
        menu.addItem(.separator())

        let every = NSMenuItem(title: "Every…", action: nil, keyEquivalent: "")
        every.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let sub = NSMenu()
        for m in [10, 15, 25, 45, 60] {
            let i = NSMenuItem(title: "\(m) minutes", action: #selector(setEvery(_:)), keyEquivalent: "")
            i.tag = m
            i.target = self
            i.state = deck.settings.minutesBetweenDrills == m ? .on : .off
            sub.addItem(i)
        }
        every.submenu = sub
        menu.addItem(every)

        if let p = deck.settings.pausedUntil, p > Date() {
            menu.addItem(item("Resume", "play.circle", "", [], #selector(resume)))
        } else {
            menu.addItem(item("Pause for an hour", "pause.circle", "", [], #selector(pause)))
        }
        let sounds = item("Sounds", "speaker.wave.2", "", [], #selector(toggleSounds))
        sounds.state = deck.settings.sounds ? .on : .off
        menu.addItem(sounds)
        let login = item("Open at login", "power", "", [], #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let read = item(watcher.connected ? "Read layers from keyboard" : "Read layers (plug in USB)", "arrow.triangle.2.circlepath", "", [], #selector(readNow))
        read.isEnabled = watcher.connected
        menu.addItem(read)
        if let km = keymap {
            let f = RelativeDateTimeFormatter()
            menu.addItem(disabled("Layers read \(f.localizedString(for: km.readAt, relativeTo: Date()))"))
        }
        if let readNote { menu.addItem(disabled(readNote)) }
        menu.addItem(item("Edit layers in Vial…", "slider.horizontal.3", "", [], #selector(openVial)))
        menu.addItem(.separator())
        menu.addItem(item("Quit", nil, "q", [.command], #selector(quit)))
    }

    private func statusLine() -> String {
        if let p = deck.settings.pausedUntil, p > Date() {
            return "Paused until \(p.formatted(date: .omitted, time: .shortened))"
        }
        let next = deck.nextDrill
        if next <= Date() {
            if let b = lastBlocker { return "Waiting because \(b.rawValue)" }
            return "Next drill any moment"
        }
        let mins = Int(ceil(next.timeIntervalSinceNow / 60))
        return "Next drill in \(mins) min"
    }

    private func header(_ title: String, _ subtitle: String) -> NSMenuItem {
        let i = NSMenuItem()
        let s = NSMutableAttributedString(string: title + "\n", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        s.append(NSAttributedString(string: subtitle, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        i.attributedTitle = s
        i.isEnabled = false
        return i
    }

    private func disabled(_ t: String) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func item(_ t: String, _ symbol: String?, _ key: String, _ mods: NSEvent.ModifierFlags, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: sel, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = self
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    @objc private func practise() { startDrill(force: true) }
    @objc private func map() { showCheatSheet() }
    @objc private func setEvery(_ s: NSMenuItem) { deck.settings.minutesBetweenDrills = s.tag; deck.save() }
    @objc private func pause() { deck.settings.pausedUntil = Date().addingTimeInterval(3600); deck.save() }
    @objc private func resume() { deck.settings.pausedUntil = nil; deck.save() }
    @objc private func toggleSounds() { deck.settings.sounds.toggle(); deck.save() }
    @objc private func readNow() { watcher.read() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister() } else { try s.register() }
        } catch {
            readNote = "Couldn't change login item: \(error.localizedDescription)"
        }
    }

    @objc private func openVial() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.vial.vial") ??
            ["/Applications/Vial.app", NSHomeDirectory() + "/Applications/Vial.app"]
            .map(URL.init(fileURLWithPath:)).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://vial.rocks")!)
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
