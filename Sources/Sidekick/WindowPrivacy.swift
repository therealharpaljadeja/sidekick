import AppKit

/// Keeps every Sidekick window out of screen recordings, screenshots and screen sharing
/// (`NSWindow.sharingType = .none`) unless the user turns that off in Settings.
@MainActor
enum WindowPrivacy {
    private static var observers: [NSObjectProtocol] = []

    static var isHidden: Bool { Prefs.defaults.bool(forKey: Prefs.hideFromCapture) }

    static var sharingType: NSWindow.SharingType { isHidden ? .none : .readOnly }

    static func apply() {
        let type = sharingType
        for window in NSApp.windows where window.sharingType != type {
            window.sharingType = type
        }
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
