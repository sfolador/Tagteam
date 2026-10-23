import SwiftUI

/// Below this width the two columns collapse into one stacked scroll column.
private let stackedLayoutThreshold: CGFloat = 680

/// The main popover content shown when clicking the menubar icon.
///
/// Fixed size: `StatusItemController` sets the popover's content size
/// (`AppStyle.popoverWidth` × `popoverHeight`, capped to the screen) and this view
/// fills it. The header and footer are pinned; the two columns scroll on their own.
struct MainMenuView: View {
    @EnvironmentObject private var appState: AppState

    private let topAnchor = "popover-column-top"

    var body: some View {
        GeometryReader { geo in
            let outer = AppStyle.popoverOuterPadding
            let stacked = geo.size.width < stackedLayoutThreshold
            let available = geo.size.width - 2 * outer - AppStyle.columnSpacing
            let leftWidth = (available * AppStyle.accountsColumnFraction).rounded()
            let rightWidth = available - leftWidth

            VStack(spacing: AppStyle.groupSpacing) {
                ProfileBarView()

                if stacked {
                    column {
                        VStack(spacing: AppStyle.groupSpacing) {
                            AccountsColumnView()
                            StatsColumnView()
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: AppStyle.columnSpacing) {
                        column { AccountsColumnView() }
                            .frame(width: leftWidth)
                        column { StatsColumnView() }
                            .frame(width: rightWidth)
                    }
                    .frame(maxHeight: .infinity)
                }

                if let message = appState.errorMessage {
                    PopoverErrorBanner(message: message) { appState.errorMessage = nil }
                }

                HStack(spacing: AppStyle.columnSpacing) {
                    PopoverActionButton("Settings", systemImage: "gearshape") {
                        SettingsDeepLink.open()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    PopoverActionButton("Quit", systemImage: "power") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: .command)
                }
            }
            .padding(outer)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(.ultraThinMaterial)
    }

    /// One independent vertical scroller. Scrolls to the top when a profile is
    /// activated; an ordinary refresh keeps the position.
    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let body = content()
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(topAnchor)
                    body
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            .onChange(of: appState.activeProfileId) { _, _ in
                proxy.scrollTo(topAnchor, anchor: .top)
            }
        }
    }
}
