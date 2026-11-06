## Tagteam 2.1.0

### The Claude desktop app follows the switch

The Claude desktop app keeps its own login, so switching a Claude Code account used to leave it on the old one. Now each Claude account is linked to a desktop app profile: Tagteam matches them automatically, or you pick one in Settings → Claude Desktop. When you switch, if the desktop app is open on a different account, Tagteam quits it gracefully and reopens it on the new one. If the app doesn't quit within 15 seconds, Tagteam skips that step and tells you; the Claude Code switch still goes through. You can also open the desktop app as any account from the account's ⋯ menu.

Tagteam only reads which account each desktop profile belongs to, never its tokens.

### A Tagteam icon in the menu bar

The menu bar now shows the Tagteam glyph instead of the generic head symbol. It follows light and dark menu bars, and fills in while a double-usage promotion is active. The setting is now called "Show Tagteam icon in menu bar"; your choice carries over.

### Open source under MIT

Tagteam is MIT-licensed, like [CCSwitcher](https://github.com/XueshiQiao/CCSwitcher) by Xueshi Qiao, which it is based on, and [Codex Switcher](https://github.com/Lampese/codex-switcher) by Lampese, which its Codex support is modelled on. The app now includes the license with every copyright notice.

**Full Changelog**: https://github.com/sfolador/Tagteam/compare/v2.0.0...v2.1.0
