import Foundation
import FoundationModels

/// The patient's instructions for a filmed exercise. The language model only puts the measured plan into words,
/// in bounded fields: it decides nothing about sets, repetitions or what the movement is.
@Generable
nonisolated struct PatientInstructions: Codable, Sendable, Equatable {
    @Guide(description: "Les étapes du mouvement, au vouvoiement, une phrase courte chacune.", .count(2...4))
    var steps: [String]
    @Guide(description: "Un conseil de sécurité court et calme, sans consigne médicale.")
    var caution: String
}

nonisolated enum InstructionWriter {
    /// Instructions without the language model: the plan, plainly.
    static func plain(name: String, plan: SessionPlan) -> PatientInstructions {
        PatientInstructions(
            steps: [
                "Placez-vous comme sur la vidéo, face à l'iPhone.",
                "Faites \(plan.sets) séries de \(plan.reps) répétitions\(plan.perSide ? " de chaque côté" : "").",
                String(format: "Gardez le rythme de la vidéo, environ %.0f secondes par répétition, et reposez-vous %d secondes entre les séries.",
                       plan.tempo.rounded(), plan.rest),
            ],
            caution: "Si la douleur est forte ou inhabituelle, faites une pause et parlez-en à votre kiné."
        )
    }

    /// Put into simple words by the model on the device, with greedy sampling; the plain version otherwise.
    static func write(name: String, summary: String, plan: SessionPlan) async -> PatientInstructions {
        let fallback = plain(name: name, plan: plan)
        guard case .available = SystemLanguageModel.default.availability else { return fallback }
        let session = LanguageModelSession(instructions: """
            Tu reformules des consignes d'exercice de rééducation pour un patient, en français simple, au vouvoiement. \
            Tu ne changes aucun nombre et tu n'ajoutes aucun conseil médical.
            """)
        let prompt = """
            Exercice : \(name). Mouvement mesuré : \(summary).
            Consignes à reformuler : \(fallback.steps.joined(separator: " "))
            """
        do {
            let response = try await session.respond(to: prompt, generating: PatientInstructions.self,
                                                     options: GenerationOptions(samplingMode: .greedy))
            let instructions = response.content
            // The numbers of the plan must survive the rewording.
            let text = instructions.steps.joined(separator: " ")
            guard text.contains("\(plan.reps)"), text.contains("\(plan.sets)") else { return fallback }
            return instructions
        } catch {
            return fallback
        }
    }
}
