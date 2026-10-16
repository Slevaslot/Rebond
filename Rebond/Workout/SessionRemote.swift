import Foundation
import Observation
import SwiftUI

/// The one way into the session for every command: buttons, hand signs, Siri, the Apple Watch, the Live Activity.
/// The screen on display says what it is (`screen`); a command is resolved for it (`SessionCommand.resolve`) and
/// posted as a `Request` that `WorkoutView` carries out. A command that didn't come from the screen is confirmed
/// on screen (`feedback`) and by voice, so the patient knows from afar that it was understood.
@MainActor @Observable
final class SessionRemote {
    static let shared = SessionRemote()

    struct Request: Equatable {
        let action: SessionAction
        let source: CommandSource
        let id = UUID()
    }

    /// The screen of the session on display, set by that screen.
    var screen = SessionScreen.none
    /// Another exercise comes after the current one.
    var hasNextExercise = true
    /// The last command to carry out.
    private(set) var request: Request?
    /// The last command from afar, to confirm on screen.
    private(set) var feedback: Request?
    /// Ending the session was asked by a hand sign, at this moment: a thumbs up within a few seconds confirms it.
    private(set) var endAskedAt: Date?
    /// How long the question stays open.
    static let confirmationDelay = 8.0

    var isAskingToEnd: Bool {
        endAskedAt.map { Date.now.timeIntervalSince($0) < Self.confirmationDelay } ?? false
    }

    /// Resolves the command for the screen on display and posts it. Returns what it does, for Siri's answer.
    @discardableResult
    func send(_ command: SessionCommand, from source: CommandSource) -> SessionAction {
        // A thumbs up (next) while the end is asked: the patient confirms.
        if command == .nextSet, isAskingToEnd {
            endAskedAt = nil
            return post(.endSession(needsConfirmation: false), from: source)
        }
        endAskedAt = nil
        let action = command.resolve(on: screen, from: source, hasNextExercise: hasNextExercise)
        if case .endSession(true) = action {
            endAskedAt = .now
            feedback = Request(action: action, source: source)
            return action
        }
        return post(action, from: source)
    }

    /// The patient answered the question on screen.
    func cancelEnd() {
        endAskedAt = nil
        feedback = nil
    }

    private func post(_ action: SessionAction, from source: CommandSource) -> SessionAction {
        if case .ignored = action { return action }
        let request = Request(action: action, source: source)
        self.request = request
        if source != .screen { feedback = request }
        return action
    }
}

extension View {
    /// Tells the session's commands which screen is on display.
    func sessionScreen(_ screen: SessionScreen) -> some View {
        onChange(of: screen, initial: true) { SessionRemote.shared.screen = screen }
    }
}
