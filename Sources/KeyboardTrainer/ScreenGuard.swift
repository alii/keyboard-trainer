import AppKit
import CoreGraphics

/// Decides whether now is a polite moment to pop up.
enum ScreenGuard {
    private typealias WatcherFn = @convention(c) () -> Bool

    /// SkyLight knows when anything is capturing the screen: Zoom, Meet, Teams,
    /// Discord, OBS, QuickTime. It's private API, so we look it up carefully.
    private static let watcherPresent: WatcherFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        for name in ["SLSIsScreenWatcherPresent", "CGSIsScreenWatcherPresent"] {
            if let p = dlsym(h, name) { return unsafeBitCast(p, to: WatcherFn.self) }
        }
        return nil
    }()

    enum Reason: String {
        case sharing = "your screen is being shared"
        case mirroring = "your screen is mirrored"
        case locked = "your screen is locked"
        case away = "you're away"
        case typing = "you're typing"
    }

    static var isScreenShared: Bool { watcherPresent?() ?? false }

    static var isMirrored: Bool {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    static var isLocked: Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? Bool) == true || (d["kCGSSessionOnConsoleKey"] as? Bool) == false
    }

    static func seconds(since type: CGEventType) -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }

    /// Any input at all, not just keys.
    static var secondsSinceAnyInput: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Returns why we should hold off, or nil if it's fine to show up now.
    /// `waited` is how long the drill has already been held back for typing.
    static func blocker(waited: TimeInterval) -> Reason? {
        if isScreenShared { return .sharing }
        if isMirrored { return .mirroring }
        if isLocked { return .locked }
        if secondsSinceAnyInput > 90 { return .away }
        // Wait for a pause in typing so we never swallow half a sentence.
        let quiet = waited > 180 ? 1.2 : 2.5
        if seconds(since: .keyDown) < quiet { return .typing }
        if NSEvent.pressedMouseButtons != 0 { return .typing }
        return nil
    }
}
