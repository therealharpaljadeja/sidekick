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
        Window("Sidekick", id: "main") {
            MainView()
                .environmentObject(prompter)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

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
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var prompter: Prompter
    @Environment(\.openWindow) private var openWindow
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
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Sidekick") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var primaryTitle: String {
        if !prompter.isPresenting { return "Start in Notch" }
        return prompter.isListening ? "Pause" : "Resume"
    }
}
