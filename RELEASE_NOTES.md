## Tagteam 2.0.0

CCSwitcher is now **Tagteam**: one menu-bar app for your Claude Code **and** Codex accounts, grouped into profiles.

### Codex accounts

Add Codex accounts next to your Claude Code ones: log in from the app, or import the login the Codex CLI already uses. Switching an account swaps `~/.codex/auth.json`, and the app restarts what keeps the old login in memory: the Codex app-server and the ChatGPT (Codex) desktop app. Both are closed gracefully and reopened only if they were running. Each Codex account shows its 5-hour and weekly limits.

### Profiles

Group accounts into profiles such as **Personal** and **Work**. Picking a profile makes one Claude Code and one Codex account live at once, and limits the popover and auto-switch to that profile's accounts. An account can be in more than one profile. Manage profiles in Settings → Profiles.

### A new popover

- **Two columns:** accounts on the left, each with its limits, an inline Switch and a ⋯ menu. A compact cost summary and the last 14 days sit on the right.
- **Profiles across the top**, with Settings and Quit as buttons at the bottom.
- **No made-up numbers:** a missing reading shows "—", never 0%.

### Also new

- A new app icon.
- Signed with a Developer ID and notarized by Apple, so it opens without Gatekeeper warnings.
- Automatic updates are removed. Install new versions from the Releases page.

### Upgrading from CCSwitcher

Your accounts and settings carry over. Quit CCSwitcher, move Tagteam to Applications, and delete the old CCSwitcher app. On first launch macOS may ask once to allow keychain access. The widget fills in after the first refresh.

Based on [CCSwitcher](https://github.com/XueshiQiao/CCSwitcher) by Xueshi Qiao. Codex support is modelled on [Codex Switcher](https://github.com/Lampese/codex-switcher) by Lampese.
