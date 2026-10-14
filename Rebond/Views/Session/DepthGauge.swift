import SwiftUI

/// Vertical gauge following the movement (downward for a squat, upward for raised arms),
/// with a mark at the target.
struct DepthGauge: View {
    /// 0 at rest, 1 at the target.
    let progress: Double
    var fillsUpward = false

    @ScaledMetric private var width = 16
    /// The gauge goes a bit past the target so going deeper stays visible.
    private let maximum = 1.2

    private var reachedTarget: Bool { progress >= 1 }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: fillsUpward ? .bottom : .top) {
                Capsule()
                    .fill(.white.opacity(0.25))
                Capsule()
                    .fill(reachedTarget ? Color.green : Color.yellow)
                    .frame(height: height * min(progress, maximum) / maximum)
                Capsule()
                    .fill(.white)
                    .frame(width: width * 1.8, height: 4)
                    .offset(y: (fillsUpward ? -1 : 1) * (height / maximum - 2))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: width * 1.8)
        .animation(.easeOut(duration: 0.15), value: progress)
        .accessibilityElement()
        .accessibilityLabel("Amplitude")
        .accessibilityValue(Text(min(progress, 1), format: .percent.precision(.fractionLength(0))))
    }
}
