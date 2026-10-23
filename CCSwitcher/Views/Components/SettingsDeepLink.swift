import AppKit

/// One place for "open Settings on section X" from the popover.
/// Valid sections: general, profiles, menuBar, claudeCLI, codex, about
/// (`SettingsView.sectionIds`).
@MainActor
enum SettingsDeepLink {
    static func open(_ section: String = "general") {
        UserDefaults.standard.set(section, forKey: "settingsSection")
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .ccswitcherOpenSettings, object: nil)
    }
}
