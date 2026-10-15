import CoreGraphics
import Foundation
import FoundationModels

/// The final choice by the language model on the device. Its answer can only be one of the candidates or
/// "nonReconnu" (a choice list in the generation schema), with greedy sampling: the same input gives the same answer.
/// Returns nil when Apple Intelligence isn't available: the nearest candidate is then chosen by distance.
nonisolated struct FoundationModelsChooser: RecognitionChooser {
    static let notRecognized = "nonReconnu"

    func choose(summary: String, candidates: [ExerciseSignature], images: [CGImage]) async -> RecognitionChoice? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability, !candidates.isEmpty else { return nil }

        let ids = candidates.map(\.id) + [Self.notRecognized]
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
            Tu choisis uniquement parmi les candidats donnés, d'après les mesures et les images. \
            Si aucun ne correspond vraiment, réponds nonReconnu. Ne devine pas.
            Exemples :
            - « hauteur des hanches 0,5→1,0, genoux, plan sagittal, debout avec descente, les deux côtés » sans chaise \
            → squat ; avec une chaise derrière le patient → sit-to-stand.
            - « hauteur du poignet, épaule, plan frontal, un côté » bras écarté sur le côté → shoulder-abduction ; \
            bras levé en diagonale, vers l'avant → scaption.
            - « hauteur du genou, genou plié, un côté » → hurdle-step ; jambe tendue → leg-raise.
            """)
        let list = candidates.map { "- \($0.id) (\($0.name)) : \($0.summary)" }.joined(separator: "\n")
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
