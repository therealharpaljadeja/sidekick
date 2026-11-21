import AppKit
import CoreText
import Speech

enum Prefs {
    static let script = "script"
    static let hideFromCapture = "hideFromCapture"
    static let fontSize = "fontSize"
    static let lineCount = "lineCount"
    static let panelWidth = "panelWidth"
    static let showSpoken = "showSpoken"
    static let localeID = "localeID"

    static func register() {
        UserDefaults.standard.register(defaults: [
            hideFromCapture: true,
            fontSize: 18.0,
            lineCount: 2,
            panelWidth: 620.0,
            showSpoken: false,
            localeID: defaultLocaleID,
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
