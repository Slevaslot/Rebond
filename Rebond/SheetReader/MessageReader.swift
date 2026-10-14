import Foundation
import FoundationModels

/// The exercises of a message, as written, before each one is read.
@Generable
nonisolated struct MessageOutline: Sendable {
    @Guide(description: "Nombre de séances par semaine demandé. Vide si le message ne le précise pas.", .range(1...14))
    var sessionsPerWeek: Int?

    @Guide(description: "Chaque exercice prescrit, recopié mot pour mot du message avec sa dose (ex. « squats 3x10 », « gainage 3 fois 30 secondes »).", .maximumCount(12))
    var exercises: [String]
}

/// Turns the physiotherapist's message (text message, email, notes taken during the appointment)
/// into a program, with the on-device model. Nothing leaves the device.
nonisolated extension SheetReader {
    /// Reading text needs the model, not its image input.
    static var messageAvailability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(String(localized: "Cet iPhone ne prend pas en charge Apple Intelligence."))
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(String(localized: "Activez Apple Intelligence dans Réglages pour lire le message automatiquement."), opensSettings: true)
        case .unavailable(.modelNotReady):
            return .unavailable(String(localized: "Apple Intelligence se prépare. Réessayez dans quelques minutes."))
        case .unavailable:
            return .unavailable(String(localized: "La lecture automatique n'est pas disponible."))
        }
    }

    /// Two passes, more reliable than one with the small on-device model: first copy out each exercise
    /// as written, with its dose; then read each one alone (type, sets, repetitions or hold).
    static func read(message: String) async throws -> ProgramDraft {
        let outline = try await LanguageModelSession(instructions: """
            Tu lis le message d'un kinésithérapeute à son patient : SMS, e-mail ou notes prises pendant la séance. \
            Il peut être familier, abrégé, ou mélangé à d'autres informations (rendez-vous, salutations). \
            Recopie mot pour mot chaque exercice prescrit avec sa dose, un par élément. \
            Les exercices tenus (gainage, planche, étirement, maintien) sont aussi des exercices. \
            « Tous les jours » vaut 7 séances par semaine, « 5j/7 » vaut 5. \
            Si le message ne prescrit aucun exercice, la liste est vide. N'invente rien.
            """).respond(generating: MessageOutline.self) {
                "Voici le message du kiné :"
                message
            }.content

        // Each exercise in its own session, all at once, kept in the message's order.
        let passages = Array(outline.exercises.prefix(12))
        let exercises = try await withThrowingTaskGroup(of: (Int, ExerciseDraft).self) { group in
            for (index, passage) in passages.enumerated() {
                group.addTask { (index, try await readExercise(passage)) }
            }
            var read: [(Int, ExerciseDraft)] = []
            for try await item in group { read.append(item) }
            return read.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let draft = ProgramDraft(sessionsPerWeek: outline.sessionsPerWeek, exercises: exercises)
        return grounded(draft, in: message)
    }

    private static func readExercise(_ passage: String) async throws -> ExerciseDraft {
        var exercise = try await LanguageModelSession(instructions: """
            Tu lis un exercice de rééducation prescrit par un kinésithérapeute, écrit en abrégé. \
            Donne son nom en français, le type le plus proche du mouvement, son nombre de séries, \
            et soit son nombre de répétitions, soit sa durée de maintien en secondes. \
            « 3x10 » ou « 3*10 » : 3 séries de 10 répétitions. « 45s x 4 » ou « 3 fois 30 secondes » : \
            un maintien, 4 ou 3 séries. « sq » est un squat, « flexion des genoux » aussi, \
            « se lever d'une chaise » est un assis-debout. Le pont fessier, le gainage, la planche, \
            les étirements et tout exercice allongé ou au sol sont du type other. \
            Laisse vide une valeur absente.
            """).respond(generating: ExerciseDraft.self) {
                "Exercice : \(passage)"
            }.content
        // A duration written in the message ("30 s", "45 secondes") makes it a hold, whatever the model said.
        if let seconds = heldSeconds(in: passage) {
            exercise.holdSeconds = seconds
            exercise.reps = nil
        }
        return exercise
    }

    /// "30 s", "30s", "45 sec", "1 min", "30 secondes" in a passage, in seconds.
    static func heldSeconds(in passage: String) -> Int? {
        let text = passage.lowercased()
        if let match = text.firstMatch(of: /(\d+)\s*(?:s|sec|secs|seconde|secondes|")(?!\p{L})/), let value = Int(match.1) {
            return value
        }
        if let match = text.firstMatch(of: /(\d+)\s*(?:min|minute|minutes)(?!\p{L})/), let value = Int(match.1) {
            return value * 60
        }
        return nil
    }

    /// The model sometimes invents a program for a message without exercises (an appointment reminder):
    /// only exercises whose name is in the message are kept, and the frequency only with at least one exercise.
    static func grounded(_ draft: ProgramDraft, in message: String) -> ProgramDraft {
        let messageWords = Set(words(in: message))
        let messageNumbers = Set(message.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) })
        var draft = draft
        draft.exercises = draft.exercises.filter { exercise in
            // Its name is in the message ("sq" for "squat" too)…
            let named = words(in: exercise.name).contains { word in
                messageWords.contains { $0.hasPrefix(word) || word.hasPrefix($0) }
            }
            // …or the model renamed it, but its dose is written there ("se lever d'une chaise 3x10").
            let dose = [exercise.sets, exercise.reps ?? exercise.holdSeconds].compactMap { $0 }
            let dosed = dose.count == 2 && dose.allSatisfy(messageNumbers.contains)
            return named || dosed
        }
        if draft.exercises.isEmpty { draft.sessionsPerWeek = nil }
        // Names are copied from the message, often in lowercase: "squats" → "Squats".
        for index in draft.exercises.indices {
            let name = draft.exercises[index].name.trimmingCharacters(in: .whitespaces)
            draft.exercises[index].name = name.prefix(1).uppercased() + name.dropFirst()
        }
        return draft
    }

    /// Lowercased words without accents, of at least 2 letters ("sq" counts, "de" too but rarely matters).
    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr"))
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    /// Words found in any message: they don't show an exercise is there.
    private static let stopWords: Set<String> = [
        "de", "des", "du", "la", "le", "les", "un", "une", "et", "en", "au", "aux", "sur", "par", "pour",
        "avec", "vers", "chaque", "fois", "serie", "series", "seconde", "secondes", "exercice", "exercices",
    ]
}
