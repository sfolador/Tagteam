import SwiftUI

/// Hover tooltip that works inside NSPopover, where `.help()` doesn't.
/// The one shared tooltip for the popover; use the `String` convenience for
/// plain text and the `@ViewBuilder` form for mixed content.
struct HoverTip<Tip: View, Content: View>: View {
    @ViewBuilder let tip: Tip
    @ViewBuilder let content: Content
    @State private var isHovering = false
    @Environment(\.locale) private var locale

    var body: some View {
        content
            .onHover { isHovering = $0 }
            .popover(isPresented: $isHovering, arrowEdge: .bottom) {
                tip
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: 240, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
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
