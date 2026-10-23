# CCSwitcher - macOS Menubar App Build Guide

A step-by-step guide to building a native macOS menubar app with SwiftUI + AppKit.
This documents how CCSwitcher was created from scratch for future reference.

---

## 1. Prerequisites

- macOS 14+ (Sonoma)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (optional, for project generation from CLI)

```bash
brew install xcodegen
```

---

## 2. Project Structure

```
CCSwitcher/
├── project.yml                    # XcodeGen project spec
├── CCSwitcher.xcodeproj/          # Generated Xcode project
├── CCSwitcher/
│   ├── CCSwitcherApp.swift        # @main App entry point with MenuBarExtra
│   ├── AppState.swift             # Central ObservableObject state manager
│   ├── Info.plist                 # App config (LSUIElement for menubar-only)
│   ├── Models/
│   │   ├── Account.swift          # Account model + AIProviderType enum
│   │   └── UsageData.swift        # Usage data models (stats cache, sessions)
│   ├── Views/
│   │   ├── MainMenuView.swift     # Main popover content
│   │   ├── UsageDashboardView.swift  # Usage stats display
│   │   ├── UsageChartView.swift   # Bar chart for daily activity
│   │   ├── AccountSwitcherView.swift # Account list + switching UI
│   │   └── SettingsView.swift     # Settings window (TabView)
│   ├── Services/
│   │   ├── KeychainService.swift  # macOS Keychain read/write
│   │   ├── ClaudeService.swift    # Claude CLI interaction
│   │   └── StatsParser.swift      # Parse ~/.claude/stats-cache.json
│   └── Resources/
│       ├── Assets.xcassets/       # App icon + accent color
│       └── CCSwitcher.entitlements
└── BUILD_GUIDE.md                 # This file
```

---

## 3. Key Concepts

### 3.1 Menubar-Only App (No Dock Icon)

Set `LSUIElement = true` in `Info.plist` to hide the app from the Dock.
The app only appears in the menubar.

```xml
<key>LSUIElement</key>
<true/>
```

### 3.2 MenuBarExtra (macOS 13+)

SwiftUI's `MenuBarExtra` scene creates a native menubar item. Use `.menuBarExtraStyle(.window)` for a popover-style window instead of a dropdown menu.

```swift
@main
struct CCSwitcherApp: App {
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "brain.head.profile")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
```

### 3.3 Settings Window

SwiftUI provides a built-in `Settings` scene. Use `SettingsLink` from your views to open it. On macOS, this opens as a proper Preferences window.

### 3.4 Launch at Login

Use `ServiceManagement.SMAppService` (macOS 13+) for modern launch-at-login:

```swift
import ServiceManagement

// Register
try SMAppService.mainApp.register()

// Unregister
try SMAppService.mainApp.unregister()

// Check status
let enabled = SMAppService.mainApp.status == .enabled
```

---

## 4. macOS Keychain Access

Use the Security framework directly for keychain operations:

```swift
import Security

// Save
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "my-service",
    kSecAttrAccount as String: "my-account",
    kSecValueData as String: "secret".data(using: .utf8)!
]
SecItemAdd(query as CFDictionary, nil)

// Read
let readQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "my-service",
    kSecAttrAccount as String: "my-account",
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne
]
var result: AnyObject?
SecItemCopyMatching(readQuery as CFDictionary, &result)
```

Claude Code stores its OAuth token in the macOS Keychain with service name `claude-code`.

---

## 5. Running Shell Commands from Swift

To interact with CLI tools (like `claude`), use `Process`:

```swift
func runCommand(_ executable: String, args: [String]) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + args
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

---

## 6. Parsing Local JSON Files

Read and parse JSON from the filesystem (e.g., `~/.claude/stats-cache.json`):

```swift
let path = NSHomeDirectory() + "/.claude/stats-cache.json"
if let data = FileManager.default.contents(atPath: path) {
    let stats = try JSONDecoder().decode(StatsCache.self, from: data)
}
```

---

## 7. XcodeGen Project Spec

Instead of manually creating `.xcodeproj`, use XcodeGen with a `project.yml`:

```yaml
name: MyApp
options:
  bundleIdPrefix: com.myapp
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
targets:
  MyApp:
    type: application
    platform: macOS
    sources:
      - path: MyApp
        excludes:
          - "Resources/**"
    resources:
      - path: MyApp/Resources/Assets.xcassets
    settings:
      base:
        INFOPLIST_FILE: MyApp/Info.plist
        GENERATE_INFOPLIST_FILE: false
```

Generate with: `xcodegen generate`

---

## 8. Building from CLI

```bash
# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project CCSwitcher.xcodeproj -scheme CCSwitcher -configuration Debug build

# Find the built app
find ~/Library/Developer/Xcode/DerivedData -name "Tagteam.app" -type d 2>/dev/null | head -1
```

### Notarized release build

`scripts/notarize.sh` builds Release unsigned, signs the widget extension and the app inside-out with the Developer ID (team `37G925A9SS`, hardened runtime, timestamp), zips, notarizes with the `notarytool` keychain profile `TunnelFlares`, staples and validates with `spctl`:

```bash
scripts/notarize.sh                 # output in build/notarize
OUT=/some/dir scripts/notarize.sh   # or choose the output directory
```

It writes `$OUT/Tagteam.app` (stapled) and `$OUT/Tagteam.zip`. The product name and app group are read from the app target via `xcodebuild -showBuildSettings` (so from `project.yml`); the script also checks the signing identity and the notary profile before building, and prints `notarytool log` if notarization fails. The app group (`APP_GROUP_ID`) lives only in `project.yml`: it is expanded into both entitlements and the `AppGroupID` Info.plist key read by `Shared/WidgetData.swift`; the script expands it in the entitlements before signing. Automatic updates (Sparkle) were removed, so there are no nested frameworks to sign.

---

## 9. Swift 6 Concurrency

Swift 6 enforces strict concurrency. Key patterns:

- Mark singleton services as `Sendable` (if they have only `let` properties)
- Use `@MainActor` for UI-related classes (like `AppState`)
- Use `async/await` for CLI interactions
- Use `@StateObject` for owned observable state in SwiftUI views
- Use `@EnvironmentObject` to pass state down the view hierarchy

---

## 10. Architecture Decisions

- **Provider Protocol**: `AIProviderType` enum allows future extension to Gemini, Codex, etc.
- **Account Switching**: Swap keychain tokens for the `claude-code` service entry
- **Usage Data**: Parse `~/.claude/stats-cache.json` directly (no API needed)
- **No Sandbox**: App needs filesystem + keychain access, so sandboxing is disabled
- **Auto-Refresh**: Timer-based polling of stats file (configurable interval)

---

## 11. Adding New Providers (Future)

To add Gemini or Codex support:

1. Add case to `AIProviderType` enum in `Account.swift`
2. Create a new service (e.g., `GeminiService.swift`) following `ClaudeService` pattern
3. Update `StatsParser` to read the new provider's stats format
4. Update `AppState` to handle multi-provider switching
5. Provider-specific views can be added as needed
