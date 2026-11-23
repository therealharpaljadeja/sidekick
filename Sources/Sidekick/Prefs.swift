import AppKit
import CoreText
import Speech

enum Prefs {
    static let script = "script"
    static let checklist = "checklist"
    static let mode = "mode"
    static let hideFromCapture = "hideFromCapture"
    static let fontSize = "fontSize"
    static let lineCount = "lineCount"
    static let panelWidth = "panelWidth"
    static let localeID = "localeID"
    static let privacyKeyCode = "privacyShortcutKeyCode"
    static let privacyModifiers = "privacyShortcutModifiers"
    static let privacyLabel = "privacyShortcutLabel"

    static func register() {
        UserDefaults.standard.register(defaults: [
            hideFromCapture: true,
            mode: PromptMode.script.rawValue,
            fontSize: 18.0,
            lineCount: 2,
            panelWidth: 620.0,
            localeID: defaultLocaleID,
            privacyKeyCode: PrivacyShortcut.defaultCombo.keyCode,
            privacyModifiers: PrivacyShortcut.defaultCombo.modifiers,
            privacyLabel: PrivacyShortcut.defaultCombo.label,
        ])
    }

    /// The user's locale if speech recognition supports it (e.g. `en_001` isn't), else en-US.
    static var defaultLocaleID: String {
        let supported = Set(SFSpeechRecognizer.supportedLocales().map { $0.identifier.replacingOccurrences(of: "_", with: "-") })
        let current = Locale.current
        let candidates = [
            current.identifier.replacingOccurrences(of: "_", with: "-"),
            [current.language.languageCode?.identifier, current.region?.identifier].compactMap { $0 }.joined(separator: "-"),
        ]
        return candidates.first { $0.hasPrefix("en") && supported.contains($0) } ?? "en-US"
    }

    static var defaults: UserDefaults { .standard }
}

enum PromptMode: String {
    case script
    case checklist
}

enum FontLoader {
    static func registerBundledFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
