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

        // When a session or sleep is active we want the widget to pick up
        // pause/resume/switch/end state changes quickly. iOS schedules
        // reloads cooperatively, but if a `reloadAllTimelines()` call is
        // throttled or coalesced, the next natural `getTimeline` is our
        // safety net — so emit a much shorter timeline while active.
        if snap.isActuallyActive || snap.isBabySleeping {
            var entries: [NourishEntry] = []
            for minutes in 0...5 {
                let date = now.addingTimeInterval(TimeInterval(minutes) * 60)
                entries.append(NourishEntry(date: date, snapshot: snap))
            }
            completion(Timeline(entries: entries, policy: .atEnd))
            return
        }

        // Idle: long timeline with 1-min entries for the first hour (so the
        // "X min ago" label stays fresh) then 5-min entries out to 2h. iOS
        // re-asks for a new timeline after 2h or when we explicitly reload.
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
