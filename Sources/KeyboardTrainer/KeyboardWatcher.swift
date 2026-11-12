import Foundation
import IOKit.hid

/// Notices when a Vial keyboard is plugged in over USB and reads its layers.
final class KeyboardWatcher {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let queue = DispatchQueue(label: "keyboard-reader")
    private var reading = false
    var onRead: (Result<Keymap, Error>) -> Void = { _ in }
    private(set) var connected = false

    func start() {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDPrimaryUsagePageKey: 0xFF60,
            kIOHIDPrimaryUsageKey: 0x61,
        ] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, _ in
            let me = Unmanaged<KeyboardWatcher>.fromOpaque(ctx!).takeUnretainedValue()
            me.connected = true
            // Give the keyboard a moment to settle after enumerating.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { me.read() }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            let me = Unmanaged<KeyboardWatcher>.fromOpaque(ctx!).takeUnretainedValue()
            me.connected = false
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func read() {
        guard !reading else { return }
        reading = true
        // The reader spins its own run loop, so give it a thread of its own.
        Thread {
            let result = Result { try Keymap.read(from: try VialReader.open()) }
            DispatchQueue.main.async {
                self.reading = false
                self.onRead(result)
            }
        }.start()
    }
}
