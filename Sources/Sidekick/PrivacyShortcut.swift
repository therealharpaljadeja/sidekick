import AppKit
import Carbon.HIToolbox

/// The editable global shortcut that flips "Hide from screen recordings".
@MainActor
enum PrivacyShortcut {
    struct Combo: Equatable {
        var keyCode: Int
        var modifiers: Int
        var label: String
    }

    nonisolated static let defaultCombo = Combo(
        keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey | cmdKey, label: "⌃⌥⌘H"
    )

    private static var hotKeyID: UInt32?

    /// `nil` when the user cleared the shortcut.
    static var combo: Combo? {
        let defaults = Prefs.defaults
        let keyCode = defaults.integer(forKey: Prefs.privacyKeyCode)
        guard keyCode >= 0 else { return nil }
        return Combo(
            keyCode: keyCode,
            modifiers: defaults.integer(forKey: Prefs.privacyModifiers),
            label: defaults.string(forKey: Prefs.privacyLabel) ?? ""
        )
    }

    /// Saves and registers `combo`. Returns false (keeping the old one) if it's already taken.
    @discardableResult
    static func set(_ new: Combo?) -> Bool {
        let old = combo
        store(new)
        register()
        if new != nil, hotKeyID == nil {
            store(old)
            register()
            return false
        }
        return true
    }

    static func register() {
        suspend()
        guard let combo else { return }
        hotKeyID = HotKeyCenter.shared.register(keyCode: combo.keyCode, modifiers: combo.modifiers) {
            MainActor.assumeIsolated { toggle() }
        }
    }

    /// Releases the hot key, e.g. while recording a new one.
    static func suspend() {
        if let hotKeyID { HotKeyCenter.shared.unregister(hotKeyID) }
        hotKeyID = nil
    }

    static func toggle() {
        Prefs.defaults.set(!WindowPrivacy.isHidden, forKey: Prefs.hideFromCapture)
    }

    /// A shortcut from a key press; needs ⌘, ⌥ or ⌃ so it can't swallow normal typing.
    static func combo(from event: NSEvent) -> Combo? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        var modifiers = 0
        var label = ""
        if flags.contains(.control) { modifiers |= controlKey; label += "⌃" }
        if flags.contains(.option) { modifiers |= optionKey; label += "⌥" }
        if flags.contains(.shift) { modifiers |= shiftKey; label += "⇧" }
        if flags.contains(.command) { modifiers |= cmdKey; label += "⌘" }
        return Combo(keyCode: Int(event.keyCode), modifiers: modifiers, label: label + keyName(event))
    }

    private static func store(_ combo: Combo?) {
        let defaults = Prefs.defaults
        defaults.set(combo?.keyCode ?? -1, forKey: Prefs.privacyKeyCode)
        defaults.set(combo?.modifiers ?? 0, forKey: Prefs.privacyModifiers)
        defaults.set(combo?.label ?? "", forKey: Prefs.privacyLabel)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(_ event: NSEvent) -> String {
        if let name = specialKeys[Int(event.keyCode)] { return name }
        let character = event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        return character.isEmpty ? "Key \(event.keyCode)" : character
    }
}
