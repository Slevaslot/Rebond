import Foundation
import SwiftData

/// A program the physiotherapist keeps to prescribe again: saved after a prescription, or one of Rebond's.
/// Stored as the same content as the QR code, so it goes back to the editor unchanged.
@Model
final class ProgramTemplate {
    var name: String
    var createdAt: Date
    /// The program, as carried by the QR code (`ProgramTransfer`, JSON).
    var content: Data

    init(name: String, program: EditableProgram, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        content = (try? JSONEncoder().encode(ProgramTransfer(program, physiotherapist: nil))) ?? Data()
    }

    var program: EditableProgram {
        var program = (try? JSONDecoder().decode(ProgramTransfer.self, from: content))?.editableProgram ?? EditableProgram()
        program.name = name
        return program
    }
}

/// Ready-made programs to start from, adjusted by the physiotherapist before prescribing.
nonisolated enum BuiltInTemplate {
    struct Item: Identifiable {
        let id: String
        let name: String
        let program: EditableProgram
    }

    static var all: [Item] {
        [
            item("knee", String(localized: "Genou · reprise"), days: [2, 4, 6], [
                .init(name: "Squat", catalogID: "squat", sets: 3, reps: 10),
                .init(name: "Montée de genou", catalogID: "hurdle-step", sets: 2, reps: 10),
                .init(name: "Élévation de la jambe tendue", catalogID: "leg-raise", sets: 2, reps: 10),
            ]),
            item("shoulder", String(localized: "Épaule · mobilité"), days: [2, 4, 6], [
                .init(name: "Élévation latérale des bras", catalogID: "lateral-raise", sets: 2, reps: 10),
                .init(name: "Élévation des bras en diagonale", catalogID: "scaption", sets: 2, reps: 10),
                .init(name: "Rotation de l'épaule", catalogID: "shoulder-rotation", sets: 2, reps: 10),
            ]),
            item("back", String(localized: "Dos · gainage"), days: [3, 5], [
                hold("Gainage", sets: 3, seconds: 30),
                .init(name: "Pont fessier", catalogID: nil, sets: 3, reps: 12),
                .init(name: "Assis-debout", catalogID: "sit-to-stand", sets: 2, reps: 10),
            ]),
            item("balance", String(localized: "Jambes · équilibre"), days: [2, 5], [
                .init(name: "Fente avant", catalogID: "forward-lunge", sets: 2, reps: 8),
                .init(name: "Fente latérale", catalogID: "side-lunge", sets: 2, reps: 8),
                .init(name: "Assis-debout", catalogID: "sit-to-stand", sets: 3, reps: 10),
            ]),
        ]
    }

    private static func item(_ id: String, _ name: String, days: [Int], _ exercises: [EditableProgram.Exercise]) -> Item {
        var program = EditableProgram()
        program.name = name
        program.weekdays = days
        program.exercises = exercises
        return Item(id: id, name: name, program: program)
    }

    private static func hold(_ name: String, sets: Int, seconds: Int) -> EditableProgram.Exercise {
        var exercise = EditableProgram.Exercise(name: name, catalogID: nil, sets: sets, reps: 10)
        exercise.mode = .hold
        exercise.holdSeconds = seconds
        return exercise
    }
}
