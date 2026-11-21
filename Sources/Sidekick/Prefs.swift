import AppKit
import CoreText

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

    static var defaultLocaleID: String {
        let current = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        return current.hasPrefix("en") ? current : "en-US"
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
