import Foundation
import SwiftData

/// An exercise program given by the physiotherapist. The patient may follow several, each on its own days
/// (the knee on Monday, Wednesday and Friday, the back on Tuesday and Thursday).
@Model
final class Program {
    var createdAt: Date
    var sessionsPerWeek: Int
    @Relationship(deleteRule: .cascade) var exercises: [PlannedExercise]
    /// Given by the patient, or empty: the program is then named after its physiotherapist or its date.
    var name: String = ""
    /// Calendar weekdays (1 is Sunday) of the program's sessions. Empty for programs saved before the days
    /// existed: they are then spread over the week from `sessionsPerWeek`.
    var weekdays: [Int] = []
    /// The physiotherapist who prescribed it, when it came from them.
    var prescriber: String? = nil
    /// Selected by the patient: only the followed programs make the day's session, the week and the reminders.
    /// The others stay ready, to pick again later.
    var isActive: Bool = true

    init(createdAt: Date = .now, sessionsPerWeek: Int, exercises: [PlannedExercise], name: String = "",
         weekdays: [Int] = [], prescriber: String? = nil) {
        self.createdAt = createdAt
        self.sessionsPerWeek = sessionsPerWeek
        self.exercises = exercises
        self.name = name
        self.weekdays = weekdays
        self.prescriber = prescriber
    }

    /// The days of its sessions, Monday first.
    var days: [Int] {
        ProgramSchedule.days(weekdays: weekdays, sessionsPerWeek: sessionsPerWeek)
    }

    func isScheduled(on date: Date) -> Bool {
        days.contains(Calendar.current.component(.weekday, from: date))
    }

    /// Its name, or one made from what it works on ("Jambes", "Épaules et dos"), so nothing has to be typed.
    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return ProgramNaming.suggestedName(for: orderedExercises.map { ($0.name, $0.catalogID) })
    }

    var orderedExercises: [PlannedExercise] {
        exercises.sorted { $0.order < $1.order }
    }
}

@Model
final class PlannedExercise {
    /// Catalog entry followed by the camera, or nil for an exercise counted by hand.
    var catalogID: String?
    var name: String
    var sets: Int
    /// Repetitions per set, for an exercise done in repetitions.
    var reps: Int
    /// Seconds to hold per set, for a held exercise (plank…). Nil for repetitions.
    var holdSeconds: Int? = nil
    var order: Int

    init(catalogID: String?, name: String, sets: Int, reps: Int, holdSeconds: Int? = nil, order: Int) {
        self.catalogID = catalogID
        self.name = name
        self.sets = sets
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.order = order
    }

    var catalogExercise: CatalogExercise? {
        guard holdSeconds == nil else { return nil }
        return catalogID.flatMap(CatalogExercise.find)
    }

    var symbol: String {
        if let catalogExercise { return catalogExercise.symbol }
        return holdSeconds == nil ? "figure.cooldown" : "timer"
    }
}
