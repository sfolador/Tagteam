import AppKit
import Foundation

private let log = FileLog("ClaudeDesktop")

// MARK: - Seam

/// A running Claude desktop app (Electron, bundle id `com.anthropic.claudefordesktop`).
struct ClaudeDesktopInstance: Equatable, Sendable {
    let pid: Int32
    let bundleURL: URL
    /// Folder name under `~/Library/Application Support/` the instance runs on
    /// ("Claude" when launched without `--user-data-dir`).
    let dataDir: String
}

/// Desktop-app operations behind a seam so the quit/relaunch sequence can be tested without touching the real app.
protocol ClaudeDesktopControlling: Sendable {
    /// Where Claude.app is installed, nil when it is not.
    func installedAppURL() async -> URL?
    func runningInstances() async -> [ClaudeDesktopInstance]
    /// Politely asks the instance to quit (never a force-kill) and waits up to `timeout` seconds. True when it exited.
    func quit(_ instance: ClaudeDesktopInstance, timeout: TimeInterval) async -> Bool
    /// Opens a NEW instance of the app with exactly these command-line arguments.
    func launch(appURL: URL, arguments: [String]) async throws
}

// MARK: - Service

/// Moves the Claude desktop app onto the login of a Claude Code account.
///
/// The desktop app keeps its own login in its Electron user-data folder
/// (`~/Library/Application Support/<folder>/`), independent of the
/// `Claude Code-credentials` keychain item Tagteam swaps. One folder per
/// account therefore gives each account its own persistent desktop login; the
/// app is pointed at a folder with `--user-data-dir=`. Nothing in a folder
/// other than the `lastKnownAccountUuid` key of `config.json` is ever read.
struct ClaudeDesktopService: Sendable {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"
    /// The folder the app uses when launched without `--user-data-dir`.
    static let defaultDataDir = "Claude"
    /// `Account.claudeDesktopDataDir` value meaning "the user opted this account out".
    static let unmanaged = ""
    static let quitTimeout: TimeInterval = 15

    enum Outcome: Equatable, Sendable {
        /// Claude.app is not installed.
        case notInstalled
        /// The app is closed; nothing was done.
        case notRunning
        /// An instance already runs on the target folder; nothing was done.
        case alreadyOnTarget
        case relaunched
        /// The app did not quit in time; it was left untouched.
        case quitTimedOut
        case launchFailed(String)
    }

    /// An existing `Claude*` user-data folder and the account it last logged in.
    struct Folder: Equatable, Sendable {
        let name: String
        let accountUuid: String?
    }

    let controller: any ClaudeDesktopControlling
    /// `~/Library/Application Support`; injectable for the harness.
    let supportRoot: URL

    init(controller: any ClaudeDesktopControlling = SystemClaudeDesktop(),
         supportRoot: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
        self.controller = controller
        self.supportRoot = supportRoot
    }

    func isInstalled() async -> Bool {
        await controller.installedAppURL() != nil
    }

    // MARK: Switching

    /// Makes the desktop app run on `dataDir`. When it is running elsewhere it is
    /// quit and reopened; when it is closed nothing happens unless `launchIfClosed`.
    func follow(dataDir: String, launchIfClosed: Bool = false) async -> Outcome {
        guard Self.isValidFolderName(dataDir) else { return .launchFailed("invalid folder name") }
        guard let appURL = await controller.installedAppURL() else { return .notInstalled }

        let running = await controller.runningInstances()
        if running.isEmpty {
            guard launchIfClosed else { return .notRunning }
        } else if running.contains(where: { $0.dataDir == dataDir }) {
            return .alreadyOnTarget
        }

        for instance in running {
            log.info("[follow] Quitting desktop app pid \(instance.pid) (folder \(instance.dataDir))")
            guard await controller.quit(instance, timeout: Self.quitTimeout) else {
                log.warning("[follow] Desktop app did not quit within \(Int(Self.quitTimeout))s; skipped")
                return .quitTimedOut
            }
        }

        do {
            try await controller.launch(appURL: appURL, arguments: launchArguments(for: dataDir))
            log.info("[follow] Relaunched desktop app on folder \(dataDir)")
            return .relaunched
        } catch {
            log.error("[follow] Relaunch failed: \(error.localizedDescription)")
            return .launchFailed(error.localizedDescription)
        }
    }

    /// The default folder takes no argument; any other folder an absolute `--user-data-dir=`.
    func launchArguments(for dataDir: String) -> [String] {
        dataDir == Self.defaultDataDir ? [] : ["--user-data-dir=\(supportRoot.appendingPathComponent(dataDir).path)"]
    }

    // MARK: Folders

    /// Only plain folder names: the value ends up in a path and a process argument.
    static func isValidFolderName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        return name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_. ")).contains($0) }
    }

    /// `Claude*` folders that hold a `config.json`, minus the app-derived `*-3p` ones.
    /// Reads nothing but the `lastKnownAccountUuid` key.
    func discoverFolders() async -> [Folder] {
        scanFolders()
    }

    func scanFolders() -> [Folder] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: supportRoot.path) else { return [] }
        return names
            .filter { ($0 == Self.defaultDataDir || $0.hasPrefix("\(Self.defaultDataDir)-")) && !$0.hasSuffix("-3p") }
            .filter { Self.isValidFolderName($0) }
            .sorted()
            .compactMap { name in
                let config = supportRoot.appendingPathComponent(name).appendingPathComponent("config.json")
                guard let data = fm.contents(atPath: config.path) else { return nil }
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                return Folder(name: name, accountUuid: json?["lastKnownAccountUuid"] as? String)
            }
    }

    /// folder per account, matched by UUID. A folder is never given to two accounts,
    /// and folders already claimed (`claimed`) are not offered again.
    static func autoMap(accountUuids: [UUID: String], folders: [Folder], claimed: Set<String>) -> [UUID: String] {
        var taken = claimed
        var result: [UUID: String] = [:]
        // Stable order so the outcome does not depend on dictionary iteration.
        for (accountId, uuid) in accountUuids.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard let folder = folders.first(where: {
                !taken.contains($0.name) && $0.accountUuid?.caseInsensitiveCompare(uuid) == .orderedSame
            }) else { continue }
            taken.insert(folder.name)
            result[accountId] = folder.name
        }
        return result
    }

    /// `Claude-<slug>`, slug from the label or email local-part restricted to `[A-Za-z0-9-]`, unique among `existing`.
    static func newFolderName(label: String?, email: String, existing: Set<String>) -> String {
        let source = (label?.isEmpty == false ? label! : String(email.split(separator: "@").first ?? ""))
        var slug = String(source.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-") ? Character(scalar) : "-"
        })
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "account" }

        let taken = Set(existing.map { $0.lowercased() })
        var candidate = "\(defaultDataDir)-\(slug)"
        var n = 2
        while taken.contains(candidate.lowercased()) || candidate.hasSuffix("-3p") {
            candidate = "\(defaultDataDir)-\(slug)-\(n)"
            n += 1
        }
        return candidate
    }

    // MARK: Detecting the folder of a running instance

    /// Folder name from a `ps -o command=` line. The path may contain spaces
    /// ("Application Support"), so the value runs up to the next ` --` flag.
    /// No flag = the default folder; a path outside `supportRoot` is returned whole.
    static func dataDir(fromCommand command: String, supportRoot: URL) -> String {
        guard let flag = command.range(of: "--user-data-dir=") ?? command.range(of: "--user-data-dir ") else {
            return defaultDataDir
        }
        var value = String(command[flag.upperBound...])
        if let next = value.range(of: " --") { value = String(value[..<next.lowerBound]) }
        value = value.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
        let url = URL(fileURLWithPath: value).standardizedFileURL
        if url.deletingLastPathComponent().path == supportRoot.standardizedFileURL.path {
            return url.lastPathComponent
        }
        return url.path
    }
}

// MARK: - Production controller

/// NSWorkspace implementation; AppKit calls hop to the main actor.
struct SystemClaudeDesktop: ClaudeDesktopControlling {
    func installedAppURL() async -> URL? {
        await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeDesktopService.bundleIdentifier)
        }
    }

    func runningInstances() async -> [ClaudeDesktopInstance] {
        let apps: [(Int32, URL)] = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeDesktopService.bundleIdentifier)
                .compactMap { app in
                    guard !app.isTerminated, let url = app.bundleURL else { return nil }
                    return (app.processIdentifier, url)
                }
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var result: [ClaudeDesktopInstance] = []
        for (pid, url) in apps {
            let command = await Self.commandLine(of: pid)
            result.append(ClaudeDesktopInstance(
                pid: pid,
                bundleURL: url,
                dataDir: ClaudeDesktopService.dataDir(fromCommand: command ?? "", supportRoot: root)
            ))
        }
        return result
    }

    func quit(_ instance: ClaudeDesktopInstance, timeout: TimeInterval) async -> Bool {
        let pid = instance.pid
        let asked = await MainActor.run { NSRunningApplication(processIdentifier: pid)?.terminate() }
        // nil = already gone.
        guard asked != nil else { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let gone = await MainActor.run { NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true }
            if gone { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    func launch(appURL: URL, arguments: [String]) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        _ = try await openApplication(at: appURL, configuration: configuration)
    }

    @MainActor
    private func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication {
        try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// `ps -o command= -p <pid>`; nil when ps fails.
    private static func commandLine(of pid: Int32) async -> String? {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-o", "command=", "-p", String(pid)]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
