import Foundation

/// What the patient asks during a session, from wherever they are: a button on screen, a hand sign to the camera,
/// Siri, the Apple Watch or the Live Activity. Every source goes through `SessionCommand.resolve`, so the same
/// command does the same thing whatever asked it, and only what makes sense at that moment.
nonisolated enum SessionCommand: String, Sendable, Equatable, CaseIterable {
    /// Pause, or resume when paused. Before a held set, starts the timer.
    case togglePause
    /// Ends this set with what was done (or the rest, or the example) and goes on.
    case nextSet
    /// Ends this set and skips the exercise's other sets.
    case nextExercise
    /// Ends the session: the pain, then the summary.
    case endSession
    /// The model large in front of the patient, or back in its card.
    case expandModel
    case shrinkModel
}

/// Who asked.
nonisolated enum CommandSource: Sendable, Equatable {
    case screen
    case gesture
    case siri
    case watch
    case liveActivity
}

/// The screen of the session right now, as far as the commands are concerned.
nonisolated enum SessionScreen: Sendable, Equatable {
    /// No session on screen.
    case none
    /// Watching the film of a filmed exercise before doing it.
    case example
    /// Getting in place, the starting position measured, or the model showing the movement once.
    case gettingReady
    /// A set followed by the camera, going on.
    case exercising
    /// A held set before its timer starts, or running.
    case holdReady
    case holding
    /// Counted with the buttons on screen.
    case countingByHand
    /// Any set paused.
    case paused
    /// The set is done: the rest before the next one counts down.
    case resting
    /// The rest countdown is paused: the patient takes their time.
    case restPaused
    /// The pain, then the summary: answered on the phone.
    case finishing
}

/// What a command does on a given screen.
nonisolated enum SessionAction: Sendable, Equatable {
    case pause
    case resume
    /// A held set: starts its timer.
    case startTimer
    /// Ends the set (or the example, or the rest) and goes to the next one.
    case finishSet
    case skipExercise
    /// Ends the session. From a hand sign it is asked again first: crossed arms can happen by accident.
    case endSession(needsConfirmation: Bool)
    case expandModel
    case shrinkModel
    /// Nothing to do now, and why (said to the patient for Siri).
    case ignored(LocalizedStringResource)

    static func == (lhs: SessionAction, rhs: SessionAction) -> Bool {
        switch (lhs, rhs) {
        case (.pause, .pause), (.resume, .resume), (.startTimer, .startTimer), (.finishSet, .finishSet),
             (.skipExercise, .skipExercise), (.expandModel, .expandModel), (.shrinkModel, .shrinkModel),
             (.ignored, .ignored):
            true
        case (.endSession(let a), .endSession(let b)):
            a == b
        default:
            false
        }
    }

    /// Shown and said to confirm a command that didn't come from the screen.
    var confirmation: LocalizedStringResource? {
        switch self {
        case .pause: "Pause"
        case .resume: "On reprend"
        case .startTimer: "C'est parti"
        case .finishSet: "Série suivante"
        case .skipExercise: "Exercice suivant"
        case .endSession(let ask): ask ? "Terminer la séance ? Pouce levé pour confirmer" : "Séance terminée"
        case .expandModel: "Regardez le mouvement"
        case .shrinkModel: "À vous"
        case .ignored: nil
        }
    }

    var symbol: String {
        switch self {
        case .pause: "pause.fill"
        case .resume, .startTimer: "play.fill"
        case .finishSet: "forward.frame.fill"
        case .skipExercise: "forward.end.fill"
        case .endSession: "flag.checkered"
        case .expandModel: "arrow.up.left.and.arrow.down.right"
        case .shrinkModel: "arrow.down.right.and.arrow.up.left"
        case .ignored: "hand.raised.slash"
        }
    }
}

nonisolated extension SessionCommand {
    /// What this command does on this screen.
    /// - Parameter hasNextExercise: Another exercise comes after this one.
    func resolve(on screen: SessionScreen, from source: CommandSource, hasNextExercise: Bool = true) -> SessionAction {
        switch screen {
        case .none:
            return .ignored("Aucune séance en cours")
        case .finishing:
            return .ignored("Indiquez votre douleur sur l'iPhone")
        default:
            break
        }
        switch self {
        case .togglePause:
            switch screen {
            case .gettingReady, .exercising, .holding, .resting: return .pause
            case .paused, .restPaused: return .resume
            case .holdReady: return .startTimer
            case .example: return .ignored("Regardez la vidéo, puis faites un pouce levé")
            case .countingByHand: return .ignored("Cette série se compte sur l'iPhone")
            case .none, .finishing: return .ignored("Aucune série en cours")
            }
        case .nextSet:
            return .finishSet
        case .nextExercise:
            return hasNextExercise ? .skipExercise : .endSession(needsConfirmation: source == .gesture)
        case .endSession:
            return .endSession(needsConfirmation: source == .gesture)
        case .expandModel:
            return screen == .exercising ? .expandModel : .ignored("Le modèle s'agrandit pendant la série")
        case .shrinkModel:
            return screen == .exercising ? .shrinkModel : .ignored("Le modèle s'agrandit pendant la série")
        }
    }
}

nonisolated extension SessionCommand {
    /// The command of each hand sign.
    init(_ gesture: HandGesture) {
        switch gesture {
        case .openPalm: self = .togglePause
        case .thumbsUp: self = .nextSet
        case .twoFingers: self = .nextExercise
        case .crossedArms: self = .endSession
        case .spread: self = .expandModel
        case .pinch: self = .shrinkModel
        }
    }
}
