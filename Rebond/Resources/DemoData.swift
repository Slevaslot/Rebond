import Foundation
import SwiftData

/// A program and a week of sessions, to show the report during the demo without waiting a week.
enum DemoData {
    static func load(into context: ModelContext) {
        var program = EditableProgram()
        program.sessionsPerWeek = 4
        program.exercises = [
            .init(name: "Squat", catalogID: CatalogExercise.squat.id, sets: 3, reps: 10),
            .init(name: "Élévation latérale des bras", catalogID: nil, sets: 3, reps: 12),
            .init(name: "Pont fessier", catalogID: nil, sets: 3, reps: 15),
        ]
        Program.replaceAll(with: program, in: context)

        // Six days ago to yesterday: amplitude improving, one painful session.
        let days: [(daysAgo: Int, pain: Int, squats: Int, incomplete: Int, amplitude: Double)] = [
            (6, 5, 24, 6, 82),
            (4, 4, 27, 3, 91),
            (3, 7, 18, 5, 88),
            (1, 3, 30, 1, 104),
        ]
        for day in days {
            let date = Calendar.current.date(byAdding: .day, value: -day.daysAgo, to: .now) ?? .now
            context.insert(Session(date: date, pain: day.pain, results: [
                ExerciseResult(exerciseName: "Squat", catalogID: CatalogExercise.squat.id, plannedReps: 30, completedReps: day.squats, incompleteReps: day.incomplete, amplitude: day.amplitude),
                ExerciseResult(exerciseName: "Élévation latérale des bras", catalogID: nil, plannedReps: 36, completedReps: 36, incompleteReps: 0, amplitude: nil),
                ExerciseResult(exerciseName: "Pont fessier", catalogID: nil, plannedReps: 45, completedReps: day.pain >= 7 ? 30 : 45, incompleteReps: 0, amplitude: nil),
            ]))
        }
    }
}
