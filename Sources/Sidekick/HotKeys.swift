import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts via Carbon hot keys (no Accessibility permission needed).
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> UInt32? {
        installHandlerIfNeeded()
        let id = nextID
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x5344_4B4B), id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        handlers[id] = handler
        nextID += 1
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

enum HotKeys {
    struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { keys }
    }

    static let shortcuts: [Shortcut] = [
        Shortcut(keys: "⌥⌘P", action: "Start · pause · resume"),
        Shortcut(keys: "⌥⌘R", action: "Restart from the top"),
        Shortcut(keys: "⌥⌘←", action: "Back one sentence"),
        Shortcut(keys: "⌥⌘→", action: "Skip to next sentence"),
        Shortcut(keys: "⌥⌘.", action: "Stop and hide"),
    ]

    @MainActor
    static func registerDefaults(for prompter: Prompter) {
        let mods = cmdKey | optionKey
        let center = HotKeyCenter.shared
        center.register(keyCode: kVK_ANSI_P, modifiers: mods) { MainActor.assumeIsolated { prompter.primaryAction() } }
        center.register(keyCode: kVK_ANSI_R, modifiers: mods) { MainActor.assumeIsolated { prompter.restart() } }
        center.register(keyCode: kVK_LeftArrow, modifiers: mods) { MainActor.assumeIsolated { prompter.previousSentence() } }
        center.register(keyCode: kVK_RightArrow, modifiers: mods) { MainActor.assumeIsolated { prompter.nextSentence() } }
        center.register(keyCode: kVK_ANSI_Period, modifiers: mods) { MainActor.assumeIsolated { prompter.stop() } }
        PrivacyShortcut.register()
    }
}
