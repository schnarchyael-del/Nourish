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
        let now = Date.now

        // Each entry's `date` doubles as the "reference now" for the static
        // strings the widget renders ("X min ago" for feeds, "Xh Ym" sleep
        // elapsed). 1-min spacing for the first hour gives clean per-minute
        // feed-ago updates; 5-min spacing extends the prerendered set for the
        // sleep elapsed counter (per spec) without overstuffing the timeline.
        var entries: [NourishEntry] = []
        for minutes in 0...60 {
            let date = now.addingTimeInterval(TimeInterval(minutes) * 60)
            entries.append(NourishEntry(date: date, snapshot: snap))
        }
        for step in 1...12 {
            let date = now.addingTimeInterval(TimeInterval(60 + step * 5) * 60)
            entries.append(NourishEntry(date: date, snapshot: snap))
        }

        let refreshAt = now.addingTimeInterval(2 * 3600)
        completion(Timeline(entries: entries, policy: .after(refreshAt)))
    }
}
