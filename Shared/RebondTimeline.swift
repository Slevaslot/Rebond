import WidgetKit

// Compiled into the iPhone widgets and the watch complications (folder `Shared/`).

/// What a widget shows at a given time.
nonisolated struct RebondEntry: TimelineEntry {
    let date: Date
    /// The snapshot as it reads on `date`: that day's session, or the next one.
    let snapshot: WidgetSnapshot

    init(date: Date, snapshot: WidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot.resolved(on: date)
    }

    var doneToday: Bool { snapshot.isDone(on: date) }
    var week: WidgetSnapshot.Week { snapshot.week(containing: date) }
    /// "Séance du jour", or the next session's day on a rest day.
    var sessionTitle: String { snapshot.sessionTitle(on: date) }
    /// Where a tap leads, matching what is shown: creating a program, the session, or the Accueil page.
    var destination: DeepLink.Destination { snapshot.destination(on: date) }
    var url: URL { destination.url }

    /// Smart Stack of the watch: brought up while the day's session is still to do (not on a rest day).
    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: destination == .session ? 50 : 0)
    }
}

/// Reads the snapshot written by the app in the App Group. The data only changes when the app writes it
/// (it then reloads the widgets) or at midnight (a new day, maybe a new week).
nonisolated struct RebondProvider: TimelineProvider {
    /// Midnights in the timeline: a week, each day's session read from the days to come of the snapshot.
    static let days = 7

    func placeholder(in context: Context) -> RebondEntry {
        RebondEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (RebondEntry) -> Void) {
        // The widget gallery shows an example until the app has a program.
        let stored = WidgetSnapshot.load()
        let snapshot = context.isPreview && stored?.hasProgram != true ? .sample : stored ?? .empty
        completion(RebondEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RebondEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? .empty
        let dates = WidgetSnapshot.timelineDates(from: .now, days: Self.days)
        let entries = dates.map { RebondEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(dates[dates.count - 1])))
    }
}
