import CoreGraphics
import Foundation
import FoundationModels

/// What the on-device model reads on the exercise sheet.
/// Values missing from the sheet stay nil, so the review screen can flag what was filled in by default.
@Generable
nonisolated struct ProgramDraft: Sendable {
    @Guide(description: "Nombre de séances par semaine demandé par le kiné. Vide si la feuille ne le précise pas.", .range(1...14))
    var sessionsPerWeek: Int?

    @Guide(description: "Les exercices de la feuille, dans l'ordre.", .maximumCount(12))
    var exercises: [ExerciseDraft]
}

@Generable
nonisolated enum ExerciseKind: Sendable {
    /// Squat, standing knee bend.
    case squat
    /// Both arms raised sideways (shoulder abduction).
    case lateralRaise
    /// One arm raised sideways, above shoulder height.
    case shoulderAbduction
    /// Arms raised forward-diagonally, in the plane of the shoulder blade.
    case scaption
    /// Standing up from a chair and sitting back down.
    case sitToStand
    /// Standing, one leg raised in front with the knee straight.
    case legRaise
    /// Standing, one knee raised bent, as when stepping over a hurdle.
    case hurdleStep
    /// Lunge with one foot in front of the other, going down and back up.
    case forwardLunge
    /// Lunge to one side, the other leg straight.
    case sideLunge
    /// Shoulder rotation with the upper arm out at shoulder height and the elbow bent (90/90).
    case shoulderRotation
    case other

    var catalogID: String? {
        switch self {
        case .squat: CatalogExercise.squat.id
        case .lateralRaise: CatalogExercise.lateralRaise.id
        case .shoulderAbduction: CatalogExercise.shoulderAbduction.id
        case .scaption: CatalogExercise.scaption.id
        case .sitToStand: CatalogExercise.sitToStand.id
        case .legRaise: CatalogExercise.legRaise.id
        case .hurdleStep: CatalogExercise.hurdleStep.id
        case .forwardLunge: CatalogExercise.forwardLunge.id
        case .sideLunge: CatalogExercise.sideLunge.id
        case .shoulderRotation: CatalogExercise.shoulderRotation.id
        case .other: nil
        }
    }
}

@Generable
nonisolated struct ExerciseDraft: Sendable {
    @Guide(description: "Nom de l'exercice tel qu'il est écrit ou dessiné sur la feuille, en français.")
    var name: String

    @Guide(description: "squat pour un squat ou une flexion des genoux debout ; lateralRaise pour une élévation latérale des deux bras ensemble (abduction des épaules) ; shoulderAbduction pour l'élévation latérale d'un seul bras sur le côté, au-dessus de l'épaule ; scaption pour une élévation des bras en avant et en diagonale (en Y, dans le plan de l'omoplate, pouces vers le haut) ; sitToStand pour un assis-debout (se lever d'une chaise puis se rasseoir, lever de chaise) ; legRaise pour une élévation de la jambe tendue vers l'avant, debout ; hurdleStep pour une montée de genou debout, genou plié (enjambement d'un obstacle ou d'une haie, genoux hauts, marche sur place en levant les genoux) ; forwardLunge pour une fente avant (un pied devant l'autre, on descend puis on remonte, fente en ligne) ; sideLunge pour une fente latérale (un pas sur le côté en pliant un genou, l'autre jambe tendue, travail des adducteurs) ; shoulderRotation pour une rotation interne ou externe de l'épaule debout, bras écarté à hauteur d'épaule et coude plié à 90° (position 90/90), l'avant-bras basculant de la verticale vers l'avant ; other pour tout autre exercice, y compris une rotation d'épaule coude collé au corps, ou un exercice allongé ou au sol.")
    var kind: ExerciseKind

    @Guide(description: "Nombre de séries. Vide si la feuille ne le précise pas.", .range(1...10))
    var sets: Int?

    @Guide(description: "Nombre de répétitions par série, pour un exercice en répétitions. Vide pour un maintien ou si la feuille ne le précise pas.", .range(1...50))
    var reps: Int?

    @Guide(description: "Durée de maintien en secondes, pour un exercice tenu (gainage, étirement, position statique). Vide sinon.", .range(5...600))
    var holdSeconds: Int?
}

/// Turns a photo of the physiotherapist's sheet into a program, with the on-device model.
/// Nothing leaves the device.
nonisolated enum SheetReader {
    enum Availability: Equatable {
        case available
        /// Message for the patient, who can still enter the program by hand. `opensSettings` when turning
        /// Apple Intelligence on in Settings would help.
        case unavailable(String, opensSettings: Bool = false)
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
            return .unavailable(String(localized: "Activez Apple Intelligence dans Réglages pour lire la feuille automatiquement."), opensSettings: true)
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
            Relève chaque exercice avec son nombre de séries, et soit son nombre de répétitions, \
            soit sa durée de maintien en secondes. Relève aussi le nombre de séances par semaine. \
            Laisse vide toute valeur absente de la feuille. N'invente pas d'exercice absent de la feuille.
            """)
        let response = try await session.respond(generating: ProgramDraft.self) {
            "Voici la photo de la feuille d'exercices."
            Attachment(image)
        }
        return response.content
    }
}
