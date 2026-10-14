import Foundation
import FoundationModels
import Testing
@testable import Rebond

/// Real messages a physiotherapist could send, read by the on-device model.
/// Skipped where Apple Intelligence isn't available (CI, unsupported Mac).
@Suite(.enabled(if: SystemLanguageModel.default.isAvailable), .serialized)
struct MessageReaderTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let message: String
        /// Catalog exercises the program must contain (others may be "other").
        let tracked: [ExerciseKind]
        let exerciseCount: Int
        let sessionsPerWeek: Int?
        var testDescription: String { String(message.prefix(40)) }
    }

    static let cases: [Case] = [
        Case(
            message: "Bonjour Mme Durand, comme vu ensemble : squats 3x10, élévations latérales des bras 3x12, gainage 3 fois 30 secondes. À faire 3 fois par semaine. Bon courage !",
            tracked: [.squat, .lateralRaise], exerciseCount: 3, sessionsPerWeek: 3),
        Case(
            message: "Exos genou : se lever d'une chaise et se rasseoir 10 fois, 3 séries. Jambe tendue levée devant 2x15. Pont fessier 3x12. Tous les jours.",
            tracked: [.sitToStand, .legRaise], exerciseCount: 3, sessionsPerWeek: 7),
        Case(
            message: "Épaule droite : lever le bras sur le côté au-dessus de l'épaule 3 x 10, bras en Y pouces vers le haut 3x8, étirement pectoral 30 s x3. 4 séances/semaine",
            tracked: [.shoulderAbduction, .scaption], exerciseCount: 3, sessionsPerWeek: 4),
        Case(
            message: "flexions de genoux 3*15, assis-debout 3*10, gainage ventral 45s x 4, 5j/7",
            tracked: [.squat, .sitToStand], exerciseCount: 3, sessionsPerWeek: 5),
        Case(
            message: "Assis-debout 5 x 10 + marche 15 min tous les jours",
            tracked: [.sitToStand], exerciseCount: 2, sessionsPerWeek: 7),
        Case(
            message: "RDV jeudi 14h au cabinet, pensez à apporter l'ordonnance. Bonne journée",
            tracked: [], exerciseCount: 0, sessionsPerWeek: nil),
    ]

    @Test(arguments: cases)
    func readsMessage(_ example: Case) async throws {
        let draft = try await SheetReader.read(message: example.message)
        let kinds = draft.exercises.map(\.kind)
        print("«\(example.message.prefix(50))» →", draft.exercises.map { "\($0.name) [\($0.kind)] \($0.sets.map(String.init) ?? "-")×\($0.reps.map(String.init) ?? "-")/\($0.holdSeconds.map { "\($0)s" } ?? "-")" }, "séances:", draft.sessionsPerWeek.map(String.init) ?? "-")
        #expect(draft.exercises.count == example.exerciseCount)
        for kind in example.tracked {
            #expect(kinds.contains(kind), "\(kind) manquant")
        }
        #expect(draft.sessionsPerWeek == example.sessionsPerWeek)
    }
}

/// The check against invented exercises, without the model.
struct MessageGroundingTests {
    private func draft(_ exercises: [(String, Int?, Int?)], sessions: Int? = 3) -> ProgramDraft {
        ProgramDraft(sessionsPerWeek: sessions, exercises: exercises.map {
            ExerciseDraft(name: $0.0, kind: .other, sets: $0.1, reps: $0.2, holdSeconds: nil)
        })
    }

    @Test func dropsExercisesNotInTheMessage() {
        let read = SheetReader.grounded(draft([("Squat", 3, 10), ("Pont fessier", 3, 12)]),
                                        in: "RDV jeudi 14h au cabinet, pensez à l'ordonnance")
        #expect(read.exercises.isEmpty)
        #expect(read.sessionsPerWeek == nil)
    }

    @Test(arguments: [("gainage 3 fois 30 secondes", 30), ("gainage ventral 45s x 4", 45), ("étirement 1 min", 60),
                      ("squats 3x10", nil), ("3 séries de 15", nil)] as [(String, Int?)])
    func readsDurations(_ passage: String, seconds: Int?) {
        #expect(SheetReader.heldSeconds(in: passage) == seconds)
    }

    @Test func keepsNamedOrDosedExercises() {
        let read = SheetReader.grounded(draft([("Squats", 3, 15), ("Assis-debout", 3, 10), ("Fente", 2, 8)]),
                                        in: "sq 3*15, se lever d'une chaise 3x10, 5j/7")
        #expect(read.exercises.map(\.name) == ["Squats", "Assis-debout"])
    }
}
