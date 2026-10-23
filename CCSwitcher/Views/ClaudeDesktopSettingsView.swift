import SwiftUI

/// Settings tab: makes the Claude desktop app follow the Claude Code account switch.
struct ClaudeDesktopSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("claudeDesktopFollow") private var follow = true
    @State private var folders: [ClaudeDesktopService.Folder] = []

    private static let autoTag = "__auto__"
    private static let newTag = "__new__"

    private var claudeAccounts: [Account] { appState.accounts(for: .claudeCode) }

    var body: some View {
        Form {
            Section {
                Toggle("Move the Claude desktop app to the account when switching", isOn: $follow)
            } footer: {
                Text("If the desktop app is open it is quit and reopened on the account's own login folder. If it does not quit within 15 seconds it is left alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if follow {
                Section {
                    ForEach(claudeAccounts) { account in
                        Picker(account.effectiveDisplayName(obfuscated: !UserDefaults.standard.bool(forKey: "showFullEmail")), selection: binding(for: account)) {
                            Text("Automatic (new folder on first switch)").tag(Self.autoTag)
                            Divider()
                            ForEach(folderNames(including: account), id: \.self) { name in
                                Text(name).tag(name)
                            }
                            Text("New folder (\(appState.proposedClaudeDesktopFolderName(for: account)))").tag(Self.newTag)
                            Divider()
                            Text("Don't manage").tag(ClaudeDesktopService.unmanaged)
                        }
                    }
                } header: {
                    Text("Desktop login folder per account")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The first launch on a new folder shows the Claude desktop login once.")
                        Text("Launching Claude from the Dock always opens the default folder (Claude). Extensions and settings are kept per folder.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { folders = await appState.discoverClaudeDesktopFolders() }
    }

    /// Existing folders, plus the account's own folder when it has not been created yet.
    private func folderNames(including account: Account) -> [String] {
        var names = folders.map(\.name)
        if let own = account.claudeDesktopDataDir, !own.isEmpty, !names.contains(own) { names.append(own) }
        return names
    }

    private func binding(for account: Account) -> Binding<String> {
        Binding(
            get: { account.claudeDesktopDataDir ?? Self.autoTag },
            set: { choice in
                switch choice {
                case Self.autoTag: appState.setClaudeDesktopDataDir(account, to: nil)
                case Self.newTag: appState.setClaudeDesktopDataDir(account, to: nil, newFolder: true)
                default: appState.setClaudeDesktopDataDir(account, to: choice)
                }
            }
        )
    }
}
