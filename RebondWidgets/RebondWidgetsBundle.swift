import SwiftUI
import WidgetKit

/// The widgets of Rebond: today's session (Home Screen and Lock Screen), the week's regularity ring
/// (Lock Screen), the Live Activity of the set in progress, and the Control Center button.
@main
struct RebondWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodaySessionWidget()
        RegularityWidget()
        WorkoutLiveActivityWidget()
        StartSessionControl()
    }
}
