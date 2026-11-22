import SwiftUI

@main
struct SidekickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var prompter = Prompter.shared

    init() {
        Prefs.register()
        FontLoader.registerBundledFonts()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(prompter)
        } label: {
            Image(systemName: "text.bubble")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            notch = NotchController(prompter: .shared)
            HotKeys.registerDefaults(for: .shared)
            WindowPrivacy.startObserving()
            MainWindowController.shared.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { MainWindowController.shared.show() }
        return true
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var prompter: Prompter
    @AppStorage(Prefs.hideFromCapture) private var hideFromCapture = true

    var body: some View {
        Button(primaryTitle) { prompter.primaryAction() }
            .keyboardShortcut("p", modifiers: [.command, .option])
        Button("Restart from Top") { prompter.restart() }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!prompter.isPresenting)
        Button("Stop") { prompter.stop() }
            .keyboardShortcut(".", modifiers: [.command, .option])
            .disabled(!prompter.isPresenting)
        Divider()
        Toggle("Hide from Screen Recordings", isOn: $hideFromCapture)
        Divider()
        Button("Open Sidekick…") {
            MainWindowController.shared.show()
        }
        Button("Quit Sidekick") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var primaryTitle: String {
        if !prompter.isPresenting { return "Start in Notch" }
        return prompter.isListening ? "Pause" : "Resume"
    }
}

/// Owns the main window in AppKit (rather than a SwiftUI `Window` scene, which always reuses
/// the same NSWindow) so it can be swapped for a fresh one when privacy is re-enabled.
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private lazy var host: NSView = NSHostingView(rootView: MainView().environmentObject(Prompter.shared))

    private init() {
        WindowPrivacy.onRehide { [weak self] in self?.rebuildIfCapturable() }
    }

    func show() {
        let window = self.window ?? makeWindow(frame: nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow(frame: NSRect?) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Sidekick"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Theme.canvas)
        window.sharingType = WindowPrivacy.sharingType
        window.contentView = host
        if let frame { window.setFrame(frame, display: false) } else { window.center() }
        self.window = window
        return window
    }

    private func rebuildIfCapturable() {
        guard let old = window, WindowPrivacy.isCapturable(old) else { return }
        let wasVisible = old.isVisible
        let wasKey = old.isKeyWindow
        old.contentView = nil
        old.orderOut(nil)
        let fresh = makeWindow(frame: old.frame)
        if wasKey { fresh.makeKeyAndOrderFront(nil) } else if wasVisible { fresh.orderFront(nil) }
    }
}
