import AppKit

/// Keeps every Sidekick window out of screen recordings, screenshots and screen sharing
/// (`NSWindow.sharingType = .none`) unless the user turns that off in Settings.
@MainActor
enum WindowPrivacy {
    private static var observers: [NSObjectProtocol] = []

    static var isHidden: Bool { Prefs.defaults.bool(forKey: Prefs.hideFromCapture) }

    static var sharingType: NSWindow.SharingType { isHidden ? .none : .readOnly }

    private static var appliedType: NSWindow.SharingType?
    private static var rebuilders: [() -> Void] = []

    static func apply() {
        let type = sharingType
        let changed = type != appliedType
        appliedType = type
        for window in NSApp.windows where changed || window.sharingType != type {
            window.sharingType = type
        }
        // macOS 26 ignores `.none` for a window that has already been switched from `.none`
        // to `.readOnly`, so windows still capturable after re-enabling are rebuilt.
        if changed, type == .none {
            DispatchQueue.main.async { MainActor.assumeIsolated { rebuilders.forEach { $0() } } }
        }
    }

    /// Registers a handler that swaps in a fresh window when `isCapturable` stays true.
    static func onRehide(_ rebuild: @escaping () -> Void) {
        rebuilders.append(rebuild)
    }

    /// The WindowServer's sharing state, which is what capture tools actually honour.
    static func isCapturable(_ window: NSWindow) -> Bool {
        guard window.windowNumber > 0,
              let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]],
              let state = info.first?[kCGWindowSharingState as String] as? Int else { return false }
        return state != NSWindow.SharingType.none.rawValue
    }

    static func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UserDefaults.didChangeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didChangeScreenNotification,
            NSApplication.didUpdateNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { apply() }
            })
        }
        apply()
    }
}
