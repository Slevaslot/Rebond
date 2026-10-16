import Foundation
import Testing
@testable import Rebond

@Suite("Commandes de séance")
struct SessionCommandTests {
    private func isIgnored(_ action: SessionAction) -> Bool {
        if case .ignored = action { return true }
        return false
    }

    private func reason(_ action: SessionAction) -> String? {
        if case .ignored(let reason) = action { return reason.key }
        return nil
    }

    // MARK: No session, or nothing left to do with commands

    @Test(arguments: SessionCommand.allCases, [CommandSource.screen, .gesture, .siri, .watch, .liveActivity])
    func nothingHappensWithoutASession(command: SessionCommand, source: CommandSource) {
        #expect(isIgnored(command.resolve(on: .none, from: source)))
    }

    @Test(arguments: SessionCommand.allCases)
    func thePainAndTheSummaryAreAnsweredOnThePhone(command: SessionCommand) {
        #expect(isIgnored(command.resolve(on: .finishing, from: .siri)))
        #expect(isIgnored(command.resolve(on: .finishing, from: .watch)))
    }

    @Test func siriSaysWhyNothingHappened() {
        #expect(reason(SessionCommand.nextSet.resolve(on: .none, from: .siri)) == "Aucune séance en cours")
        #expect(reason(SessionCommand.endSession.resolve(on: .finishing, from: .siri)) == "Indiquez votre douleur sur l'iPhone")
        #expect(SessionCommand.endSession.resolve(on: .none, from: .siri).confirmation == nil)
    }

    // MARK: Pause

    @Test(arguments: [SessionScreen.gettingReady, .exercising, .holding, .resting])
    func pausesWhatIsGoingOn(screen: SessionScreen) {
        #expect(SessionCommand.togglePause.resolve(on: screen, from: .siri) == .pause)
    }

    @Test(arguments: [SessionScreen.paused, .restPaused])
    func resumesWhenPaused(screen: SessionScreen) {
        #expect(SessionCommand.togglePause.resolve(on: screen, from: .watch) == .resume)
        #expect(SessionCommand.togglePause.resolve(on: screen, from: .gesture) == .resume)
    }

    @Test func startsTheTimerOfAHeldSet() {
        #expect(SessionCommand.togglePause.resolve(on: .holdReady, from: .siri) == .startTimer)
    }

    @Test func nothingToPauseDuringTheExampleOrAHandCountedSet() {
        #expect(isIgnored(SessionCommand.togglePause.resolve(on: .example, from: .siri)))
        #expect(isIgnored(SessionCommand.togglePause.resolve(on: .countingByHand, from: .watch)))
    }

    // MARK: Next set, next exercise

    @Test(arguments: [SessionScreen.example, .gettingReady, .exercising, .holdReady, .holding, .countingByHand,
                      .paused, .resting, .restPaused])
    func nextSetFinishesTheSet(screen: SessionScreen) {
        #expect(SessionCommand.nextSet.resolve(on: screen, from: .siri) == .finishSet)
    }

    @Test func theRestEndsOnNextSet() {
        #expect(SessionCommand.nextSet.resolve(on: .resting, from: .watch) == .finishSet)
    }

    @Test func nextExerciseSkipsTheOtherSets() {
        #expect(SessionCommand.nextExercise.resolve(on: .exercising, from: .siri) == .skipExercise)
        #expect(SessionCommand.nextExercise.resolve(on: .resting, from: .gesture) == .skipExercise)
    }

    @Test func nextExerciseOnTheLastOneEndsTheSession() {
        #expect(SessionCommand.nextExercise.resolve(on: .exercising, from: .siri, hasNextExercise: false)
            == .endSession(needsConfirmation: false))
        // Two fingers by accident on the last exercise: asked again, like crossed arms.
        #expect(SessionCommand.nextExercise.resolve(on: .exercising, from: .gesture, hasNextExercise: false)
            == .endSession(needsConfirmation: true))
    }

    // MARK: End

    @Test func endingFromAHandSignIsAskedAgain() {
        #expect(SessionCommand.endSession.resolve(on: .exercising, from: .gesture) == .endSession(needsConfirmation: true))
    }

    @Test(arguments: [CommandSource.screen, .siri, .watch, .liveActivity])
    func endingFromElsewhereIsDirect(source: CommandSource) {
        // Siri asks its own question before sending the command.
        #expect(SessionCommand.endSession.resolve(on: .exercising, from: source) == .endSession(needsConfirmation: false))
        #expect(SessionCommand.endSession.resolve(on: .resting, from: source) == .endSession(needsConfirmation: false))
    }

    @Test func siriConfirmsWhatWasDone() {
        #expect(SessionAction.finishSet.confirmation?.key == "Série suivante")
        #expect(SessionAction.skipExercise.confirmation?.key == "Exercice suivant")
        #expect(SessionAction.endSession(needsConfirmation: false).confirmation?.key == "Séance terminée")
    }

    // MARK: Model

    @Test func theModelGrowsOnlyDuringTheSet() {
        #expect(SessionCommand.expandModel.resolve(on: .exercising, from: .gesture) == .expandModel)
        #expect(SessionCommand.shrinkModel.resolve(on: .exercising, from: .gesture) == .shrinkModel)
        for screen in [SessionScreen.gettingReady, .holding, .paused, .resting, .example] {
            #expect(isIgnored(SessionCommand.expandModel.resolve(on: screen, from: .gesture)))
            #expect(isIgnored(SessionCommand.shrinkModel.resolve(on: screen, from: .gesture)))
        }
    }

    // MARK: Hand signs

    @Test func eachHandSignHasItsCommand() {
        #expect(SessionCommand(.openPalm) == .togglePause)
        #expect(SessionCommand(.thumbsUp) == .nextSet)
        #expect(SessionCommand(.twoFingers) == .nextExercise)
        #expect(SessionCommand(.crossedArms) == .endSession)
    }
}

@MainActor
@Suite("Chemin unique des commandes")
struct SessionRemoteTests {
    private func remote(on screen: SessionScreen) -> SessionRemote {
        let remote = SessionRemote()
        remote.screen = screen
        return remote
    }

    @Test func aCommandIsPostedForTheScreen() {
        let remote = remote(on: .exercising)
        #expect(remote.send(.togglePause, from: .siri) == .pause)
        #expect(remote.request?.action == .pause)
        #expect(remote.request?.source == .siri)
    }

    @Test func aCommandFromAfarIsConfirmedOnScreen() {
        let remote = remote(on: .exercising)
        remote.send(.nextSet, from: .watch)
        #expect(remote.feedback?.action == .finishSet)
        remote.send(.togglePause, from: .screen)
        // The button on screen needs no confirmation: the last one from afar stays.
        #expect(remote.feedback?.action == .finishSet)
        #expect(remote.request?.action == .pause)
    }

    @Test func anIgnoredCommandPostsNothing() {
        let remote = remote(on: .none)
        if case .ignored(let reason) = remote.send(.nextSet, from: .siri) {
            #expect(reason.key == "Aucune séance en cours")
        } else {
            Issue.record("Without a session, the command is ignored")
        }
        #expect(remote.request == nil)
        #expect(remote.feedback == nil)
    }

    @Test func eachCommandIsANewRequest() {
        let remote = remote(on: .exercising)
        remote.send(.nextSet, from: .watch)
        let first = remote.request
        remote.send(.nextSet, from: .watch)
        #expect(remote.request != first)
    }

    @Test func crossedArmsAskBeforeEnding() {
        let remote = remote(on: .exercising)
        #expect(remote.send(.endSession, from: .gesture) == .endSession(needsConfirmation: true))
        #expect(remote.request == nil)
        #expect(remote.isAskingToEnd)
        #expect(remote.feedback?.action == .endSession(needsConfirmation: true))
    }

    @Test func aThumbsUpConfirmsTheEnd() {
        let remote = remote(on: .exercising)
        remote.send(.endSession, from: .gesture)
        #expect(remote.send(.nextSet, from: .gesture) == .endSession(needsConfirmation: false))
        #expect(remote.request?.action == .endSession(needsConfirmation: false))
        #expect(!remote.isAskingToEnd)
    }

    @Test(arguments: [SessionCommand.togglePause, .nextExercise, .expandModel, .shrinkModel])
    func anyOtherCommandCancelsTheEnd(command: SessionCommand) {
        let remote = remote(on: .exercising)
        remote.send(.endSession, from: .gesture)
        remote.send(command, from: .gesture)
        #expect(!remote.isAskingToEnd)
        // The next thumbs up is a plain next set again.
        #expect(remote.send(.nextSet, from: .gesture) == .finishSet)
    }

    @Test func answeringOnScreenCancelsTheEnd() {
        let remote = remote(on: .exercising)
        remote.send(.endSession, from: .gesture)
        remote.cancelEnd()
        #expect(!remote.isAskingToEnd)
        #expect(remote.feedback == nil)
        #expect(remote.send(.nextSet, from: .gesture) == .finishSet)
    }

    @Test func siriEndsDirectly() {
        let remote = remote(on: .resting)
        #expect(remote.send(.endSession, from: .siri) == .endSession(needsConfirmation: false))
        #expect(remote.request?.action == .endSession(needsConfirmation: false))
        #expect(!remote.isAskingToEnd)
    }

    @Test func twoFingersOnTheLastExerciseAskBeforeEnding() {
        let remote = remote(on: .exercising)
        remote.hasNextExercise = false
        #expect(remote.send(.nextExercise, from: .gesture) == .endSession(needsConfirmation: true))
        #expect(remote.isAskingToEnd)
        #expect(remote.send(.nextSet, from: .gesture) == .endSession(needsConfirmation: false))
    }
}
