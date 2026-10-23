import SwiftUI

/// Hover tooltip that works inside NSPopover, where `.help()` doesn't.
/// The one shared tooltip for the popover; use the `String` convenience for
/// plain text and the `@ViewBuilder` form for mixed content.
struct HoverTip<Tip: View, Content: View>: View {
    @ViewBuilder let tip: Tip
    @ViewBuilder let content: Content
    @State private var isHovering = false
    @Environment(\.locale) private var locale

    private static var tipWidth: CGFloat { 240 }

    var body: some View {
        content
            .onHover { isHovering = $0 }
            .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                // A popover content view gets no proposed width: `maxWidth` alone let the
                // text report a huge ideal height. An explicit width makes it wrap.
                // Tips must be pure text built from values captured at creation: the
                // popover does not inherit `appState` / `menuBarConfig`.
                tip
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(width: Self.tipWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .environment(\.locale, locale)
            }
    }
}

extension HoverTip where Tip == Text {
    init(_ text: String, @ViewBuilder content: () -> Content) {
        self.tip = Text(text)
        self.content = content()
    }
}
