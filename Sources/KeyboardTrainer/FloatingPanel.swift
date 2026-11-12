import AppKit
import SwiftUI

/// A borderless glass panel that takes your keystrokes without pulling your app
/// out of focus, the same trick Spotlight uses.
final class FloatingPanel: NSPanel {
    var onKeyDown: (NSEvent) -> Bool = { _ in false }
    var onFlags: (NSEvent) -> Void = { _ in }
    var onResign: () -> Void = {}

    init<V: View>(_ view: V) {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .none
        // Keep the card out of screenshots and recordings.
        sharingType = ProcessInfo.processInfo.environment["KT_ALLOW_CAPTURE"] == nil ? .none : .readOnly

        // A fixed, mostly see-through window. The card sits at the top and can grow
        // downwards without the window jumping around.
        let host = NSHostingView(rootView: view
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
            .padding(30)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .top))
        host.sizingOptions = []
        contentView = host
    }

    static let size = NSSize(width: 680, height: 720)

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if !onKeyDown(event) { super.keyDown(with: event) }
    }

    override func flagsChanged(with event: NSEvent) {
        onFlags(event)
    }

    override func resignKey() {
        super.resignKey()
        onResign()
    }

    /// Slides in at the top of whichever screen your mouse is on.
    func present(on chosen: NSScreen? = nil) {
        let size = Self.size
        let screen = chosen ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height + 18)
        setFrame(NSRect(origin: origin.applying(.init(translationX: 0, y: 14)), size: size), display: false)
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            animator().alphaValue = 1
            animator().setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }

    func dismiss(_ done: @escaping () -> Void = {}) {
        onResign = {}
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            animator().alphaValue = 0
            animator().setFrame(frame.offsetBy(dx: 0, dy: 10), display: true)
        }, completionHandler: {
            self.orderOut(nil)
            done()
        })
    }
}
