import SwiftUI

/// On a wide screen (an unfolded foldable iPhone, an iPhone in landscape), pages keep a comfortable reading width,
/// centred, instead of stretching cards and buttons edge to edge (HIG *Layout*: readable content width).
/// Applied once at the root: scroll views, lists and forms below take the side margins.
struct ReadableWidth: ViewModifier {
    /// About the width of an iPhone Pro Max in portrait, plus some room: wider than that, the content is centred.
    static let maxWidth: CGFloat = 640

    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        Group {
            // On a phone-sized screen, nothing set: a margin of 0 would replace the system's own margins and
            // glue lists and forms (Espace kiné, Réglages) to the screen edges.
            if Self.margin(for: width) > 0 {
                content.contentMargins(.horizontal, Self.margin(for: width), for: .scrollContent)
            } else {
                content
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// The extra margin on each side, nothing on a phone-sized screen.
    nonisolated static func margin(for width: CGFloat) -> CGFloat {
        max(0, (width - maxWidth) / 2)
    }
}

extension View {
    func readableWidth() -> some View {
        modifier(ReadableWidth())
    }
}
