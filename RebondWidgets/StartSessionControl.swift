import AppIntents
import SwiftUI
import WidgetKit

/// "Ma séance" in Control Center, on the Lock Screen or on the Action button: opens Rebond on the session.
struct StartSessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.rebond.app.start-session") {
            ControlWidgetButton(action: StartSessionIntent()) {
                Label("Ma séance", systemImage: "figure.cooldown")
            }
        }
        .displayName("Démarrer ma séance")
        .description("Ouvre Rebond et lance la séance du jour.")
    }
}
