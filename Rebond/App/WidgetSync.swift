import SwiftData
import SwiftUI
import WidgetKit

/// Keeps the widgets up to date: whenever the program or the sessions change, wherever it happens
/// (session saved, program scanned, prescribed or edited, demo data), writes the snapshot read by the
/// widgets and the App Intents into the App Group, then reloads the widgets.
/// Applied once, at the root of the app: no view needs to call it.
struct WidgetSync: ViewModifier {
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @Query(filter: Session.programSessions, sort: \Session.date, order: .reverse) private var sessions: [Session]

    func body(content: Content) -> some View {
        content
            .onChange(of: snapshot, initial: true) { _, snapshot in
                Self.publish(snapshot)
            }
            // Spotlight: the programs by name, and the exercises the camera follows.
            .task(id: programs.map { "\($0.title)\($0.exercises.count)" }) {
                await SeanceEntity.index(programs)
            }
            .task { await ExerciseEntity.index() }
    }

    private var snapshot: WidgetSnapshot {
        WidgetSnapshot(programs: programs, sessions: sessions)
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
    /// The day's session (or the next one), and the week's sessions.
    init(programs: [Program], sessions: [Session], now: Date = .now) {
        let exercises = programs.sessionExercises(on: now)
        guard !exercises.isEmpty else {
            self = .empty
            return
        }
        let oldest = Calendar.current.date(byAdding: .day, value: -Self.keptDays, to: now) ?? now
        self.init(
            hasProgram: true,
            sessionsPerWeek: programs.sessionsPerWeek,
            exercises: exercises.map {
                Exercise(name: $0.name, symbol: $0.symbol, sets: $0.sets, reps: $0.reps, holdSeconds: $0.holdSeconds)
            },
            estimatedMinutes: exercises.estimatedMinutes,
            sessionDates: sessions.map(\.date).filter { $0 >= oldest }.sorted(by: >),
            // The exercises are today's, or those of the next day with a session (rest day).
            sessionDay: programs.exercises(on: now).isEmpty ? programs.next(after: now)?.day : now
        )
    }
}
