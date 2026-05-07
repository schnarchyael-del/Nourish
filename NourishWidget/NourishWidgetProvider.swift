import WidgetKit

struct NourishEntry: TimelineEntry {
    let date: Date
    let snapshot: FeedSnapshot
}

struct NourishProvider: TimelineProvider {
    typealias Entry = NourishEntry

    func placeholder(in context: Context) -> NourishEntry {
        NourishEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NourishEntry) -> Void) {
        let snap = context.isPreview ? FeedSnapshot.placeholder : FeedSnapshot.load()
        completion(NourishEntry(date: .now, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NourishEntry>) -> Void) {
        let snap = FeedSnapshot.load()
        // Generate entries every 30 min over the next 2 hours so the widget
        // has prerendered states even if WidgetCenter.reloadAllTimelines() is
        // missed. Text(date, style: .relative / .timer) auto-updates between
        // entries so the displayed time stays fresh per minute regardless.
        let now = Date.now
        let entries: [NourishEntry] = (0..<5).map { step in
            NourishEntry(
                date: now.addingTimeInterval(TimeInterval(step) * 30 * 60),
                snapshot: snap
            )
        }
        let refreshAt = now.addingTimeInterval(2 * 3600)
        completion(Timeline(entries: entries, policy: .after(refreshAt)))
    }
}
