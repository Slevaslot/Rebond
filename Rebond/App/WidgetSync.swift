import SwiftData
import SwiftUI
import UIKit
import WidgetKit

/// Keeps the widgets up to date: whenever the program or the sessions change, wherever it happens
/// (session saved, program scanned, prescribed, edited or deleted, demo data), and when the day changes
/// (app back in the foreground, midnight), writes the snapshot read by the widgets and the App Intents into
/// the App Group, then reloads the widgets.
/// Applied once, at the root of the app: no view needs to call it.
struct WidgetSync: ViewModifier {
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @Query(filter: Session.programSessions, sort: \Session.date, order: .reverse) private var sessions: [Session]
    @Environment(\.scenePhase) private var scenePhase
    /// The day of the snapshot: moved on when the app comes back, and at midnight while it is open.
    @State private var now = Date.now

    func body(content: Content) -> some View {
        content
            .onChange(of: snapshot, initial: true) { _, snapshot in
                Self.publish(snapshot)
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active { now = .now }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                now = .now
            }
            // Spotlight: the programs by name, and the exercises the camera follows.
            .task(id: programs.map { "\($0.title)\($0.exercises.count)" }) {
                await SeanceEntity.index(programs)
            }
            .task { await ExerciseEntity.index() }
    }

    private var snapshot: WidgetSnapshot {
        WidgetSnapshot(programs: programs, sessions: sessions, now: now)
    }

    /// Writes the snapshot and reloads the widgets, only if something changed. Also sends it to the Apple Watch,
    /// for its app and complications (WatchConnectivity keeps only the latest).
    static func publish(_ snapshot: WidgetSnapshot) {
        PhoneWatchLink.shared.updateContext(snapshot)
        if snapshot.save() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension WidgetSnapshot {
    /// The day's session (or the next one), the days to come, and the week's sessions.
    init(programs: [Program], sessions: [Session], now: Date = .now) {
        let exercises = programs.sessionExercises(on: now)
        guard !exercises.isEmpty else {
            self = .empty
            return
        }
        let calendar = Calendar.current
        let oldest = calendar.date(byAdding: .day, value: -Self.keptDays, to: now) ?? now
        let today = calendar.startOfDay(for: now)
        self.init(
            hasProgram: true,
            sessionsPerWeek: programs.sessionsPerWeek,
            exercises: exercises.map(Exercise.init),
            estimatedMinutes: exercises.estimatedMinutes,
            sessionDates: sessions.map(\.date).filter { $0 >= oldest }.sorted(by: >),
            // The exercises are today's, or those of the next day with a session (rest day).
            sessionDay: programs.exercises(on: now).isEmpty ? programs.next(after: now)?.day : now,
            upcoming: (0..<Self.upcomingDays).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
                let exercises = programs.exercises(on: day)
                guard !exercises.isEmpty else { return nil }
                return PlannedDay(day: day, exercises: exercises.map(Exercise.init), estimatedMinutes: exercises.estimatedMinutes)
            }
        )
    }
}

extension WidgetSnapshot.Exercise {
    init(_ exercise: PlannedExercise) {
        self.init(name: exercise.name, symbol: exercise.symbol, sets: exercise.sets, reps: exercise.reps,
                  holdSeconds: exercise.holdSeconds)
    }
}
