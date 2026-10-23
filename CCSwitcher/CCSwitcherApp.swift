import SwiftUI
import ServiceManagement

private let log = FileLog("App")

/// UserDefaults key remembering that the user asked for launch at login, so it
/// can be re-registered after the app bundle is renamed or moved.
let launchAtLoginIntentKey = "launchAtLoginIntent"
/// Bundle path the login item was last registered from; re-registration happens once per path.
let launchAtLoginRegisteredPathKey = "launchAtLoginRegisteredPath"

class AppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        // Apply saved language preference before any UI loads
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "auto"
        if lang != "auto" {
            UserDefaults.standard.set([lang], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App starts as agent/accessory due to LSUIElement
        restoreLaunchAtLogin()
    }

    /// A login item is registered per app location, so renaming or moving the bundle
    /// can drop it. Re-register when the user had it on, but only for an installed copy
    /// and at most once per bundle path, so removing the item in System Settings sticks.
    private func restoreLaunchAtLogin() {
        let defaults = UserDefaults.standard
        let status = SMAppService.mainApp.status
        let path = Bundle.main.bundlePath
        guard defaults.object(forKey: launchAtLoginIntentKey) != nil else {
            defaults.set(status == .enabled, forKey: launchAtLoginIntentKey)
            if status == .enabled { defaults.set(path, forKey: launchAtLoginRegisteredPathKey) }
            return
        }
        guard defaults.bool(forKey: launchAtLoginIntentKey), status != .enabled else { return }
        let registeredPath = defaults.string(forKey: launchAtLoginRegisteredPathKey)
        if registeredPath == path {
            // Registered from this very path before, yet not enabled now: the user removed it.
            defaults.set(false, forKey: launchAtLoginIntentKey)
            log.info("Launch at login was removed externally; respecting it (status \(String(describing: status)))")
            return
        }
        guard status == .notRegistered, path.hasPrefix("/Applications/") else { return }
        do {
            try SMAppService.mainApp.register()
            defaults.set(path, forKey: launchAtLoginRegisteredPathKey)
            log.info("Re-registered launch at login for \(path)")
        } catch {
            log.error("Could not re-register launch at login: \(error.localizedDescription)")
        }
    }
}

@main
struct CCSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var menuBarConfig = MenuBarConfig.shared
    @AppStorage("refreshInterval") private var refreshInterval: Double = 300
    @AppStorage("appLanguage") private var appLanguage = "auto"

    @State private var statusItemController = StatusItemController()
    @State private var didBootstrap = false

    var body: some Scene {
        // Hidden 1×1 window to keep SwiftUI's lifecycle alive so `Settings` scene
        // shows the native toolbar tabs even though the UI is AppKit-based.
        WindowGroup("CCSwitcherKeepalive") {
            HiddenWindowView()
                .onAppear {
                    guard !didBootstrap else { return }
                    didBootstrap = true
                    statusItemController.install(
                        appState: appState,
                        config: menuBarConfig,
                        locale: currentLocale
                    )
                    // Kick off background usage tracking immediately upon app start
                    Task {
                        await appState.refresh()
                        appState.startAutoRefresh(interval: refreshInterval)
                    }
                }
                .onChange(of: appLanguage) { _, _ in
                    statusItemController.updateLocale(currentLocale)
                }
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(menuBarConfig)
                .environment(\.locale, currentLocale)
        }
    }

    private var currentLocale: Locale {
        appLanguage == "auto" ? .autoupdatingCurrent : Locale(identifier: appLanguage)
    }
}
