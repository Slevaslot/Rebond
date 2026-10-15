import CoreGraphics
import Foundation
import FoundationModels

/// The final choice by the language model on the device. Its answer can only be one of the candidates or
/// "nonReconnu" (a choice list in the generation schema), with greedy sampling: the same input gives the same answer.
/// Returns nil when Apple Intelligence isn't available: the nearest candidate is then chosen by distance.
nonisolated struct FoundationModelsChooser: RecognitionChooser {
    static let notRecognized = "nonReconnu"
    /// The answer may be "nonReconnu"; off (demo), it must be one of the candidates, which all fit the measures.
    var allowsNotRecognized = false

    func choose(summary: String, candidates: [ExerciseSignature], images: [CGImage]) async -> RecognitionChoice? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability, !candidates.isEmpty else { return nil }

        let ids = candidates.map(\.id).sorted() + (allowsNotRecognized ? [Self.notRecognized] : [])
        let root = DynamicGenerationSchema(name: "Identification", properties: [
            .init(name: "exercice", description: "L'id d'un candidat, ou nonReconnu si aucun ne correspond.",
                  schema: DynamicGenerationSchema(name: "Exercice", anyOf: ids)),
            .init(name: "confiance", description: "De 0 (au hasard) à 100 (certain).",
                  schema: DynamicGenerationSchema(type: Int.self, guides: [.range(0...100)])),
            .init(name: "description", description: "Une phrase courte qui décrit le mouvement vu.",
                  schema: DynamicGenerationSchema(type: String.self)),
        ])
        guard let schema = try? GenerationSchema(root: root, dependencies: []) else { return nil }

        let session = LanguageModelSession(instructions: """
            Tu identifies un exercice de rééducation filmé chez le kinésithérapeute, de face. \
            Tu choisis uniquement parmi les candidats donnés. Regarde d'abord les images (position du corps, \
            jambe ou bras qui bouge, chaise), puis les mesures pour confirmer ; les bras peuvent bouger pendant \
            un exercice de jambes. \
            Si aucun ne correspond vraiment, réponds nonReconnu. Ne devine pas.
            Exemples :
            - « hauteur des hanches 0,5→1,0, genoux, plan sagittal, debout avec descente, les deux côtés » sans chaise \
            → squat ; avec une chaise derrière le patient → sit-to-stand ; un pied devant l'autre → forward-lunge ; \
            un pas sur le côté → side-lunge.
            - « hauteur du poignet, épaule, plan frontal, un côté » bras écarté sur le côté → shoulder-abduction ; \
            bras levé en diagonale, vers l'avant → scaption. En cas de doute entre les deux, choisis \
            shoulder-abduction.
            - Jambe levée devant, un côté : « genou le plus plié » sous 120° (genou plié) → hurdle-step ; \
            au-dessus de 120° (jambe tendue) → leg-raise.
            """)
        // Always in the same order (by id), not nearest first: the model tends to favor the first choice it reads.
        let listed = candidates.sorted { $0.id < $1.id }
        let list = listed.map { "- \($0.id) (\($0.name)) : \($0.summary)" }.joined(separator: "\n")
        let text = """
            Mesures du mouvement filmé : \(summary).
            Candidats :
            \(list)
            Images : début, amplitude maximale, fin.
            """
        let canSee = model.capabilities.contains(.vision) && !images.isEmpty
        do {
            let response = try await session.respond(schema: schema, options: GenerationOptions(samplingMode: .greedy)) {
                text
                if canSee {
                    for image in images.prefix(3) { Attachment(image) }
                }
            }
            let id = try response.content.value(String.self, forProperty: "exercice")
            let confidence = (try? response.content.value(Int.self, forProperty: "confiance")) ?? 0
            let description = (try? response.content.value(String.self, forProperty: "description")) ?? summary
            return RecognitionChoice(id: id == Self.notRecognized ? nil : id,
                                     confidence: Double(confidence) / 100, description: description)
        } catch {
            return nil
        }
    }
}
