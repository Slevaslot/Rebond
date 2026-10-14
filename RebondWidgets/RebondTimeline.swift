import WidgetKit

/// What a widget shows at a given time.
nonisolated struct RebondEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    var doneToday: Bool { snapshot.isDone(on: date) }
    var week: WidgetSnapshot.Week { snapshot.week(containing: date) }
}

/// Reads the snapshot written by the app in the App Group. The data only changes when the app writes it
/// (it then reloads the widgets) or at midnight (a new day, maybe a new week).
nonisolated struct RebondProvider: TimelineProvider {
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
        let now = Date.now
        let midnight = WidgetSnapshot.nextRefresh(after: now)
        let entries = [
            RebondEntry(date: now, snapshot: snapshot),
            RebondEntry(date: midnight, snapshot: snapshot),
        ]
        completion(Timeline(entries: entries, policy: .after(WidgetSnapshot.nextRefresh(after: midnight))))
    }
}
