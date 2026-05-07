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
        let entry = NourishEntry(date: .now, snapshot: snap)
        let refreshAt = Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshAt)))
    }
}
