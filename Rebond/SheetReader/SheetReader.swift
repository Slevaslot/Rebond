import CoreGraphics
import Foundation
import FoundationModels

/// What the on-device model reads on the exercise sheet.
@Generable
nonisolated struct ProgramDraft: Sendable {
    @Guide(description: "Nombre de séances par semaine demandé par le kiné. 3 si la feuille ne le précise pas.", .range(1...14))
    var sessionsPerWeek: Int

    @Guide(description: "Les exercices de la feuille, dans l'ordre.", .maximumCount(12))
    var exercises: [ExerciseDraft]
}

@Generable
nonisolated struct ExerciseDraft: Sendable {
    @Guide(description: "Nom de l'exercice tel qu'il est écrit ou dessiné sur la feuille, en français.")
    var name: String

    @Guide(description: "« squat » si l'exercice est un squat ou une flexion des genoux debout (accroupissement), sinon « autre ».", .anyOf(["squat", "autre"]))
    var kind: String

    @Guide(description: "Nombre de séries. 3 si la feuille ne le précise pas.", .range(1...10))
    var sets: Int

    @Guide(description: "Nombre de répétitions par série. 10 si la feuille ne le précise pas.", .range(1...50))
    var reps: Int

    /// Catalog entry for the camera, nil when the exercise is counted by hand.
    var catalogID: String? {
        CatalogExercise.find(kind)?.id
    }
}

/// Turns a photo of the physiotherapist's sheet into a program, with the on-device model.
/// Nothing leaves the device.
nonisolated enum SheetReader {
    enum Availability: Equatable {
        case available
        /// Message for the patient, who can still enter the program by hand.
        case unavailable(String)
    }

    static var availability: Availability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.capabilities.contains(.vision)
                ? .available
                : .unavailable(String(localized: "Cet iPhone ne peut pas lire les photos avec Apple Intelligence."))
        case .unavailable(.deviceNotEligible):
            return .unavailable(String(localized: "Cet iPhone ne prend pas en charge Apple Intelligence."))
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(String(localized: "Activez Apple Intelligence dans Réglages pour lire la feuille automatiquement."))
        case .unavailable(.modelNotReady):
            return .unavailable(String(localized: "Apple Intelligence se prépare. Réessayez dans quelques minutes."))
        case .unavailable:
            return .unavailable(String(localized: "La lecture automatique n'est pas disponible."))
        }
    }

    static func read(_ image: CGImage) async throws -> ProgramDraft {
        let session = LanguageModelSession(instructions: """
            Tu lis une feuille d'exercices de rééducation donnée par un kinésithérapeute. \
            Elle peut contenir des dessins, du texte imprimé ou manuscrit. \
            Relève chaque exercice avec son nombre de séries et de répétitions, \
            et le nombre de séances par semaine. N'invente pas d'exercice absent de la feuille.
            """)
        let response = try await session.respond(generating: ProgramDraft.self) {
            "Voici la photo de la feuille d'exercices."
            Attachment(image)
        }
        return response.content
    }
}
