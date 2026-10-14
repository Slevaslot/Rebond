import Foundation
import SwiftData

/// A program and three weeks of sessions, to show the progress and the report during the demo.
enum DemoData {
    static func load(into context: ModelContext) {
        try? context.delete(model: Session.self)

        var program = EditableProgram()
        program.sessionsPerWeek = 3
        program.exercises = [
            .init(name: "Squat", catalogID: CatalogExercise.squat.id, sets: 2, reps: 10),
            .init(name: "Élévation latérale des bras", catalogID: CatalogExercise.lateralRaise.id, sets: 2, reps: 10),
            .init(name: "Gainage", catalogID: nil, sets: 2, mode: .hold, reps: 10, holdSeconds: 30),
            .init(name: "Pont fessier", catalogID: nil, sets: 2, reps: 12),
        ]
        Program.replaceAll(with: program, in: context)

        // Three weeks: more regular, amplitude improving, pain going down, with one painful session.
        let days: [(daysAgo: Int, pain: Int, squats: Int, incomplete: Int, squatAmplitude: Double, raises: Int, raiseAmplitude: Double, plank: Int)] = [
            (20, 6, 14, 6, 71, 12, 74, 40),
            (17, 6, 16, 4, 76, 15, 78, 45),
            (13, 5, 18, 3, 82, 16, 83, 50),
            (11, 7, 12, 5, 79, 14, 80, 35),
            (8, 4, 19, 2, 88, 18, 89, 55),
            (6, 4, 20, 1, 93, 19, 92, 60),
            (4, 3, 20, 1, 97, 20, 95, 60),
            (1, 2, 20, 0, 104, 20, 99, 60),
        ]
        for day in days {
            let date = Calendar.current.date(byAdding: .day, value: -day.daysAgo, to: .now) ?? .now
            context.insert(Session(date: date, pain: day.pain, duration: 14 * 60, results: [
                ExerciseResult(exerciseName: "Squat", catalogID: CatalogExercise.squat.id, order: 0, plannedReps: 20,
                               completedReps: day.squats, incompleteReps: day.incomplete, amplitude: day.squatAmplitude),
                ExerciseResult(exerciseName: "Élévation latérale des bras", catalogID: CatalogExercise.lateralRaise.id, order: 1, plannedReps: 20,
                               completedReps: day.raises, incompleteReps: 20 - day.raises, amplitude: day.raiseAmplitude),
                ExerciseResult(exerciseName: "Gainage", catalogID: nil, order: 2, plannedReps: 0, completedReps: 0, incompleteReps: 0,
                               plannedSeconds: 60, heldSeconds: day.plank, amplitude: nil),
                ExerciseResult(exerciseName: "Pont fessier", catalogID: nil, order: 3, plannedReps: 24,
                               completedReps: day.pain >= 7 ? 16 : 24, incompleteReps: 0, amplitude: nil),
            ]))
        }
    }

    /// Three patients with different weeks, for the physiotherapist space.
    static func loadPatients(into context: ModelContext) {
        let patients: [(name: String, pains: [Int], amplitudes: [Double], days: [Int])] = [
            ("Martine D.", [5, 4, 4, 3, 3, 2], [72, 78, 84, 90, 96, 101], [19, 16, 12, 9, 5, 2]),
            ("Jean-Pierre L.", [6, 6, 7, 8], [80, 79, 76, 74], [20, 13, 8, 1]),
            ("Sofia R.", [3, 2, 2, 1, 1, 1, 0], [88, 92, 95, 99, 103, 105, 108], [20, 17, 14, 11, 8, 5, 2]),
        ]
        for patient in patients {
            let sessions = zip(patient.days, zip(patient.pains, patient.amplitudes)).map { daysAgo, values in
                WeeklyReport.SessionData(
                    date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now,
                    pain: values.0,
                    results: [
                        .init(name: "Squat", order: 0, plannedReps: 20, completedReps: values.0 >= 7 ? 12 : 20,
                              incompleteReps: values.0 >= 7 ? 6 : 1, plannedSeconds: 0, heldSeconds: 0, amplitude: values.1),
                        .init(name: "Gainage", order: 1, plannedReps: 0, completedReps: 0, incompleteReps: 0,
                              plannedSeconds: 60, heldSeconds: values.0 >= 7 ? 30 : 60, amplitude: nil),
                    ]
                )
            }
            let transfer = ReportTransfer(patientID: UUID(), patientName: patient.name, sessionsPerWeek: 3, sessions: sessions)
            if let data = try? transfer.encoded() {
                _ = try? TrackedPatient.receive(data, in: context)
            }
        }
    }
}
