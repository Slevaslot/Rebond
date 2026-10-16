import SwiftUI

/// The hand signs that work on a session screen, so the patient knows they can use them from where they stand.
/// The sign just recognized is highlighted a moment, to confirm it from afar.
struct GestureLegend: View {
    struct Item: Identifiable {
        let gesture: HandGesture
        /// What the sign does here, in a few words.
        let title: LocalizedStringKey
        var id: HandGesture { gesture }
    }

    let items: [Item]
    var recognized: HandGesture?

    var body: some View {
        if !items.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { labels }
                VStack(alignment: .leading, spacing: 6) { labels }
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(in: .rect(cornerRadius: 22))
            .animation(.default, value: recognized)
            .accessibilityElement(children: .combine)
        }
    }

    private var labels: some View {
        ForEach(items) { item in
            Label {
                Text(item.title)
            } icon: {
                Image(systemName: item.gesture.symbol)
                    .symbolEffect(.bounce, value: recognized == item.gesture)
            }
            .foregroundStyle(recognized == item.gesture ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .fixedSize()
            .accessibilityLabel(Text("\(Text(item.gesture.signName)) : \(Text(item.title))"))
        }
    }
}

extension HandGesture {
    var symbol: String {
        switch self {
        case .openPalm: "hand.raised.fill"
        case .thumbsUp: "hand.thumbsup.fill"
        // No "V" hand in SF Symbols: the raised finger, the legend names the sign.
        case .twoFingers: "hand.point.up.fill"
        case .crossedArms: "xmark"
        case .spread: "arrow.up.left.and.arrow.down.right"
        case .pinch: "hand.pinch.fill"
        }
    }

    /// The sign in words, for VoiceOver.
    var signName: LocalizedStringResource {
        switch self {
        case .openPalm: "Main ouverte levée"
        case .thumbsUp: "Pouce levé"
        case .twoFingers: "Deux doigts en V"
        case .crossedArms: "Bras croisés devant la poitrine"
        case .spread: "Pouce et index qui s'écartent"
        case .pinch: "Pouce et index qui se rejoignent"
        }
    }
}
