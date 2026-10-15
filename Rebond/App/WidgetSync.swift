import SwiftData
import SwiftUI
import WidgetKit

/// Keeps the widgets up to date: whenever the program or the sessions change, wherever it happens
/// (session saved, program scanned, prescribed or edited, demo data), writes the snapshot read by the
/// widgets and the App Intents into the App Group, then reloads the widgets.
/// Applied once, at the root of the app: no view needs to call it.
struct WidgetSync: ViewModifier {
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]

    func body(content: Content) -> some View {
        content
            .onChange(of: snapshot, initial: true) { _, snapshot in
                Self.publish(snapshot)
            }
    }

    private var snapshot: WidgetSnapshot {
        WidgetSnapshot(program: programs.first, sessions: sessions)
    }

    /// Writes the snapshot and reloads the widgets, only if something changed.
    static func publish(_ snapshot: WidgetSnapshot) {
        if snapshot.save() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension WidgetSnapshot {
    init(program: Program?, sessions: [Session], now: Date = .now) {
        guard let program else {
            self = .empty
            return
        }
        let oldest = Calendar.current.date(byAdding: .day, value: -Self.keptDays, to: now) ?? now
        self.init(
            hasProgram: true,
            sessionsPerWeek: program.sessionsPerWeek,
            exercises: program.orderedExercises.map {
                Exercise(name: $0.name, symbol: $0.symbol, sets: $0.sets, reps: $0.reps, holdSeconds: $0.holdSeconds)
            },
            estimatedMinutes: program.estimatedMinutes,
            sessionDates: sessions.map(\.date).filter { $0 >= oldest }.sorted(by: >)
        )
    }
}
