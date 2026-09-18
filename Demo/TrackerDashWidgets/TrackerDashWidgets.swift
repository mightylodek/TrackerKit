import WidgetKit
import SwiftUI
import TrackerKit

// MARK: - Entry

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// True when we're showing sample data because nothing real has been
    /// published yet. The view uses it to say so rather than quietly presenting
    /// fiction as fact.
    let isPlaceholder: Bool
}

// MARK: - Provider

struct TrackerDashProvider: TimelineProvider {

    private var store: SharedSnapshotStore {
        SharedSnapshotStore(appGroupIdentifier: TrackerDashIDs.appGroup)
    }

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // One entry, refreshed at midnight.
        //
        // The app pushes a reload on every log, toggle and profile switch, so
        // there is nothing to gain from polling on an interval. The one change
        // the app can't announce is the date rolling over — at midnight every
        // "today" figure resets and every streak becomes a day older, so that is
        // the single scheduled wake-up.
        let entry = currentEntry()
        let midnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) ?? Date.now.addingTimeInterval(3600)

        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    private func currentEntry() -> SnapshotEntry {
        if let snapshot = store.currentSnapshot() {
            return SnapshotEntry(date: .now, snapshot: snapshot, isPlaceholder: false)
        }
        return SnapshotEntry(date: .now, snapshot: .placeholder, isPlaceholder: true)
    }
}

// MARK: - View

struct TrackerDashWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var size: TrackerWidgetSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        default: .large
        }
    }

    var body: some View {
        TrackerWidgetView(
            snapshot: entry.snapshot,
            size: size,
            linksToTrackers: !entry.isPlaceholder
        )
        .trackerTheme(.nocturne)
        // Small has no per-row links, so the whole tile is the target. It opens
        // the tracker most in need of attention, which is the one it's showing.
        .widgetURL(smallWidgetURL)
        .containerBackground(for: .widget) {
            TrackerTheme.nocturne.surface
        }
    }

    private var smallWidgetURL: URL? {
        guard family == .systemSmall, !entry.isPlaceholder,
              let first = entry.snapshot.lines.first
        else { return nil }
        return WidgetDeepLink.tracker(first.id).url
    }
}

// MARK: - Widget

struct TrackerDashWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TrackerDashWidget", provider: TrackerDashProvider()) { entry in
            TrackerDashWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Your streak and the goals that need attention.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct TrackerDashWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrackerDashWidget()
    }
}

// MARK: - Shared identifiers

/// Duplicated from the app target on purpose.
///
/// An extension is a separate binary and cannot see the app's types. Keeping the
/// literal in both places with this note is safer than the alternatives: an App
/// Group that disagrees by one character between targets doesn't error, it just
/// hands back a nil container and the widget shows placeholder data forever.
///
/// If this moves anywhere, move it into TrackerKit itself so both targets read
/// one definition.
enum TrackerDashIDs {
    static let appGroup = "group.com.mightylodek.software.trackerkit"
}
