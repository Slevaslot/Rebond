import AppIntents
import Foundation

/// "Combien de séances cette semaine ?": answers with one sentence, without opening the app.
/// Reads the snapshot the app shares with its widgets, so it answers like the Aujourd'hui page.
struct WeekProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Séances de la semaine"
    static let description = IntentDescription("Indique combien de séances vous avez faites cette semaine, et si celle du jour est faite.")
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        guard let snapshot = WidgetSnapshot.load(), snapshot.hasProgram else {
            return .result(value: 0, dialog: "Vous n'avez pas encore de programme. Ouvrez Rebond pour ajouter celui de votre kiné.")
        }
        let now = Date.now
        let week = snapshot.week(containing: now)
        let dialog: IntentDialog = switch (week.isComplete, snapshot.isDone(on: now)) {
        case (true, true):
            "Objectif de la semaine atteint : \(week.done) séances sur \(week.planned). Votre séance du jour est faite."
        case (true, false):
            "Objectif de la semaine atteint : \(week.done) séances sur \(week.planned). Votre séance du jour reste à faire."
        case (false, true):
            "Cette semaine : \(week.done) séances sur \(week.planned). Votre séance du jour est faite."
        case (false, false):
            "Cette semaine : \(week.done) séances sur \(week.planned). Votre séance du jour reste à faire."
        }
        return .result(value: week.done, dialog: dialog)
    }
}
