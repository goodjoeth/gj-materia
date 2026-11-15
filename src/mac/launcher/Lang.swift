// Lang.swift - the launcher's two languages: English (the default) and Thai, chosen in Settings
// and kept in the app's defaults (uiLanguage = "en" | "th"). Every string is written in both at
// its place, L("ไทย", "English"); changing the language reopens the app.
import Foundation
#if os(macOS)
import AppKit
#endif

enum Lang {
    static let key = "uiLanguage"
    static let thai: Bool = UserDefaults.standard.string(forKey: key) == "th"

    /// Switch and reopen the app, so every page (and the overlay) is drawn in the new language.
    static func set(thai: Bool) {
        guard thai != Lang.thai else { return }
        UserDefaults.standard.set(thai ? "th" : "en", forKey: key)
        UserDefaults.standard.synchronize()
        #if os(macOS)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        #endif
    }
}

/// The string in the chosen language.
@inline(__always) func L(_ th: String, _ en: String) -> String { Lang.thai ? th : en }
