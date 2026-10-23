import SwiftUI

/// Settings tab for the Codex CLI: status, accounts, and login.
struct CodexSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("showFullEmail") private var showFullEmail = false
    @AppStorage("codexRestartAppServer") private var restartAppServer = true
    @State private var binaryPath: String?
    @State private var appServerRunning: Bool?
    @State private var pendingRemoval: Account?

    private var codexHome: String {
        CodexService.shared.codexHome().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var body: some View {
        Form {
            Section("Codex CLI") {
                LabeledContent("Status") {
                    if appState.codexAvailable {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not found", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                if let binaryPath {
                    LabeledContent("Binary") {
                        Text(binaryPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                LabeledContent("Codex home") {
                    Text(codexHome)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !appState.codexAvailable {
                    Text("Install the Codex CLI (for example `npm i -g @openai/codex`) to add Codex accounts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                let accounts = appState.accounts(for: .codex)
                if accounts.isEmpty {
                    Text("No Codex accounts yet. Log in a new account, or import the one the Codex CLI is already using.")
                        .foregroundStyle(.secondary)
                }
                ForEach(accounts) { account in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(account.effectiveDisplayName(obfuscated: !showFullEmail))
                                if appState.activeCodexAccount?.id == account.id {
                                    Text("Live")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(.green.opacity(0.2)))
                                        .foregroundStyle(.green)
                                }
                            }
                            HStack(spacing: 4) {
                                Text(account.displayEmail(obfuscated: !showFullEmail))
                                if let plan = account.displaySubscriptionType {
                                    Text("· \(plan)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { pendingRemoval = account } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove account")
                    }
                }
            } header: {
                Text("Accounts")
            }

            Section {
                HStack {
                    if appState.isLoggingInCodex {
                        ProgressView().controlSize(.small)
                        Text("Waiting for browser login…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { appState.cancelCodexLogin() }
                    } else {
                        Button("Log in new account") {
                            Task { await appState.loginNewCodexAccount() }
                        }
                        Button("Import current Codex login") {
                            Task { await appState.importCurrentCodexLogin() }
                        }
                    }
                }
                .disabled(!appState.codexAvailable && !appState.isLoggingInCodex)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Switching accounts rewrites ~/.codex/auth.json. Running Codex sessions keep the previous account until they are restarted.")
                    if appState.runningCodexSessions > 0 {
                        Label("\(appState.runningCodexSessions) Codex session(s) running now", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("App-server") {
                    switch appServerRunning {
                    case .some(true): Label("Running", systemImage: "circle.fill").foregroundStyle(.green)
                    case .some(false): Label("Not running", systemImage: "circle").foregroundStyle(.secondary)
                    case .none: ProgressView().controlSize(.small)
                    }
                }
                Toggle("Restart the Codex app-server when switching", isOn: $restartAppServer)
            } footer: {
                Text("ChatGPT.app and Codex clients keep the login in memory through this background service. Restarting it interrupts Codex tasks that are running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            binaryPath = await CodexService.shared.codexBinaryPath()
            appServerRunning = await CodexService.shared.isAppServerDaemonRunning()
        }
        .confirmationDialog(
            "Remove Codex account?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { account in
            Button("Remove", role: .destructive) {
                appState.removeAccount(account)
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { _ in
            Text("The stored credentials for this account are deleted from CCSwitcher.")
        }
    }
}
