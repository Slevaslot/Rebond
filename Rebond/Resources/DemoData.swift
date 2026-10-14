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

    /// Three patients with different weeks, for the physiotherapist space: one progressing well, one with high pain
    /// and few sessions, one who hasn't sent a report for ten days. Fixed identifiers, so loading again updates them.
    static func loadPatients(into context: ModelContext) {
        struct DemoPatient {
            let id: String
            let name: String
            let reportDaysAgo: Int
            let sessionsPerWeek: Int
            let days: [Int]
            let pains: [Int]
            let amplitudes: [Double]
            let exercise: CatalogExercise
        }
        let patients = [
            DemoPatient(id: "D3A0F6C2-2B7E-4C51-9C1E-6F0A1B2C3D01", name: "Martine Dubois", reportDaysAgo: 0, sessionsPerWeek: 3,
                        days: [19, 16, 12, 9, 6, 4, 2], pains: [5, 4, 4, 3, 3, 2, 2], amplitudes: [72, 78, 84, 88, 93, 97, 101],
                        exercise: .squat),
            DemoPatient(id: "D3A0F6C2-2B7E-4C51-9C1E-6F0A1B2C3D02", name: "Jean-Pierre Laurent", reportDaysAgo: 1, sessionsPerWeek: 3,
                        days: [20, 15, 13, 8, 3], pains: [5, 6, 6, 7, 8], amplitudes: [80, 81, 79, 76, 73],
                        exercise: .lateralRaise),
            DemoPatient(id: "D3A0F6C2-2B7E-4C51-9C1E-6F0A1B2C3D03", name: "Sofia Rossi", reportDaysAgo: 10, sessionsPerWeek: 2,
                        days: [24, 20, 17, 13, 10], pains: [3, 2, 2, 1, 1], amplitudes: [88, 92, 95, 99, 104],
                        exercise: .squat),
        ]
        for patient in patients {
            let sessions = zip(patient.days, zip(patient.pains, patient.amplitudes)).map { daysAgo, values in
                let (pain, amplitude) = values
                let painful = pain >= WeeklyReport.highPain
                return WeeklyReport.SessionData(
                    date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now,
                    pain: pain,
                    results: [
                        .init(name: String(localized: patient.exercise.name), order: 0, plannedReps: 20, completedReps: painful ? 12 : 19,
                              incompleteReps: painful ? 6 : 1, plannedSeconds: 0, heldSeconds: 0, amplitude: amplitude),
                        .init(name: "Pont fessier", order: 1, plannedReps: 24, completedReps: painful ? 16 : 24,
                              incompleteReps: 0, plannedSeconds: 0, heldSeconds: 0, amplitude: nil),
                        .init(name: "Gainage", order: 2, plannedReps: 0, completedReps: 0, incompleteReps: 0,
                              plannedSeconds: 60, heldSeconds: painful ? 30 : 60, amplitude: nil),
                    ]
                )
            }
            var program = EditableProgram()
            program.sessionsPerWeek = patient.sessionsPerWeek
            program.exercises = [
                .init(name: String(localized: patient.exercise.name), catalogID: patient.exercise.id, sets: 2, reps: 10),
                .init(name: "Pont fessier", catalogID: nil, sets: 2, reps: 12),
                .init(name: "Gainage", catalogID: nil, sets: 2, mode: .hold, reps: 10, holdSeconds: 30),
            ]
            let transfer = ReportTransfer(
                patientID: UUID(uuidString: patient.id) ?? UUID(),
                patientName: patient.name,
                generatedAt: Calendar.current.date(byAdding: .day, value: -patient.reportDaysAgo, to: .now) ?? .now,
                sessionsPerWeek: patient.sessionsPerWeek,
                sessions: sessions.filter { $0.date <= Calendar.current.date(byAdding: .day, value: -patient.reportDaysAgo, to: .now) ?? .now },
                program: ProgramTransfer(program, physiotherapist: nil)
            )
            if let data = try? transfer.encoded() {
                _ = try? TrackedPatient.receive(data, in: context)
            }
        }
    }
}
