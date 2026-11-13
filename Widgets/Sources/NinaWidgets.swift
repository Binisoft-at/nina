import WidgetKit
import SwiftUI
import NinaCore

/// Widgets read the small snapshot the app writes to the shared App Group (WidgetBridge).
@main
struct NinaWidgets: WidgetBundle {
    var body: some Widget {
        OpenItemsWidget()
    }
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: ItemSummary
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), summary: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        let summary: ItemSummary = context.isPreview ? .placeholder : (WidgetBridge.read() ?? .placeholder)
        completion(SummaryEntry(date: Date(), summary: summary))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let summary = WidgetBridge.read() ?? ItemSummary(openCount: 0, doneCount: 0, next: [], updatedAt: Date())
        // The app reloads the timeline whenever the summary changes.
        completion(Timeline(entries: [SummaryEntry(date: Date(), summary: summary)], policy: .never))
    }
}

struct OpenItemsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenItems", provider: SummaryProvider()) { entry in
            OpenItemsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Open Items")
        .description("What's next in \(AppInfo.name).")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct OpenItemsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text("\(entry.summary.openCount)")
                    .font(.title2.bold())
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.summary.headline)
                    .font(.headline)
                ForEach(entry.summary.next.prefix(2), id: \.self) { title in
                    Text(title)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.summary.headline)
                    .font(.headline)
                ForEach(entry.summary.next, id: \.self) { title in
                    Label(title, systemImage: "circle")
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
