import Foundation

private let log = FileLog("CodexStore")

/// Backup store for Codex `auth.json` files: ONE generic-password item holding
/// a JSON dictionary `[accountId: rawAuthJSON]`, accessed through the
/// `/usr/bin/security` CLI. Going through the CLI (instead of `SecItem*`)
/// keeps the item's ACL on Apple's `security` binary, so rebuilding the app
/// never triggers a per-build keychain prompt.
///
/// The raw auth.json text is stored verbatim so unknown top-level keys survive
/// a capture → switch round trip.
final class CodexCredentialStore: Sendable {
    static let shared = CodexCredentialStore()

    /// Result of reading the single item that holds every backup. `empty`
    /// (item does not exist) and `failed` (it may exist but could not be read
    /// or decoded) must stay distinct: saving a mutated copy after a failed
    /// load would replace every account's credentials with one entry.
    enum Load {
        case loaded([String: String])
        case empty
        case failed(String)
    }

    enum Lookup {
        case found(String)
        case missing
        case storeUnavailable
    }

    private let service: String
    private let account: String
    /// All accounts share one item, so every mutation is load → mutate → save
    /// and must not interleave with another.
    private let storeLock = NSLock()

    init(service: String = "CCSwitcher-codex-backups", account: String = "all-accounts") {
        self.service = service
        self.account = account
    }

    // MARK: - Public API

    func lookup(_ accountId: String) -> Lookup {
        storeLock.lock(); defer { storeLock.unlock() }
        switch load() {
        case .loaded(let store):
            guard let raw = store[accountId] else {
                log.error("[lookup] No backup for accountId=\(accountId)")
                return .missing
            }
            return .found(raw)
        case .empty:
            log.error("[lookup] No backup for accountId=\(accountId) (store is empty)")
            return .missing
        case .failed(let reason):
            log.error("[lookup] Store unreadable (\(reason)); \(accountId) unavailable until it recovers")
            return .storeUnavailable
        }
    }

    /// Every stored backup. Keeps the loaded / empty / failed distinction so a
    /// caller can tell "nobody owns this" from "could not look".
    func loadAll() -> Load {
        storeLock.lock(); defer { storeLock.unlock() }
        return load()
    }

    func has(_ accountId: String) -> Bool {
        if case .found = lookup(accountId) { return true }
        return false
    }

    /// Returns false (and writes nothing) when the store cannot be read.
    @discardableResult
    func save(rawAuth: String, forAccountId accountId: String) -> Bool {
        storeLock.lock(); defer { storeLock.unlock() }
        var store: [String: String]
        switch load() {
        case .loaded(let dict): store = dict
        case .empty: store = [:]
        case .failed(let reason):
            log.error("[save] REFUSED: store unreadable (\(reason)); writing now would destroy the other accounts' backups")
            return false
        }
        store[accountId] = rawAuth
        let ok = write(store)
        log.info("[save] accountId=\(accountId) result=\(ok)")
        return ok
    }

    @discardableResult
    func remove(_ accountId: String) -> Bool {
        storeLock.lock(); defer { storeLock.unlock() }
        var store: [String: String]
        switch load() {
        case .loaded(let dict): store = dict
        case .empty: return true
        case .failed(let reason):
            log.error("[remove] REFUSED: store unreadable (\(reason))")
            return false
        }
        guard store.removeValue(forKey: accountId) != nil else { return true }
        return write(store)
    }

    /// Delete the whole item. Used by tests against a throwaway service name.
    @discardableResult
    func deleteStore() -> Bool {
        storeLock.lock(); defer { storeLock.unlock() }
        return runSecurity(["delete-generic-password", "-s", service, "-a", account]).status == 0
    }

    // MARK: - Item I/O (storeLock held)

    private func load() -> Load {
        let result = runSecurity(["find-generic-password", "-s", service, "-a", account, "-w"])
        // 44 = errSecItemNotFound as reported by the security CLI.
        if result.status == 44 { return .empty }
        guard result.status == 0 else {
            log.error("[load] security exited \(result.status)")
            return .failed("security exit \(result.status)")
        }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Self.decodePayload(text),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            log.error("[load] Item exists (\(text.count) chars) but did not decode")
            return .failed("undecodable store data")
        }
        return .loaded(dict)
    }

    /// `security -w` prints the password as text, but falls back to hex when
    /// the data is not printable. Accept both.
    private static func decodePayload(_ text: String) -> Data? {
        if text.hasPrefix("{") { return text.data(using: .utf8) }
        guard !text.isEmpty, text.count % 2 == 0,
              text.allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes = [UInt8]()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private func write(_ store: [String: String]) -> Bool {
        // Compact single-line JSON: a newline would make `security -w` hex-encode on read.
        guard let data = try? JSONEncoder().encode(store),
              let text = String(data: data, encoding: .utf8) else {
            log.error("[write] Encoding failed")
            return false
        }
        // -U updates in place, so the item is never absent between delete and add.
        let result = runSecurity(["add-generic-password", "-U", "-s", service, "-a", account, "-w", text])
        if result.status != 0 { log.error("[write] security exited \(result.status)") }
        return result.status == 0
    }

    private func runSecurity(_ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Drain before waiting so a large payload cannot fill the pipe and deadlock.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            log.error("[runSecurity] Launch failed: \(error.localizedDescription)")
            return (-1, "")
        }
    }
}
