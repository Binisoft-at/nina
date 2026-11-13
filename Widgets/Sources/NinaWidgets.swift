import WidgetKit
import SwiftUI
import NinaCore

/// Today's numbers on the Home Screen, Lock Screen and watch face. Widgets only read the small
/// snapshot the app writes to the shared App Group (WidgetBridge) – never the diary itself.
/// The same source builds the iPhone widget extension and the watch complications.
@main
struct NinaWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let snapshot = context.isPreview ? TodaySnapshot.placeholder : current()
        completion(TodayEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        // The app reloads timelines when the numbers change; after midnight the day starts empty.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let entries = [
            TodayEntry(date: now, snapshot: current(now: now)),
            TodayEntry(date: midnight, snapshot: current(now: midnight)),
        ]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }

    private func current(now: Date = Date()) -> TodaySnapshot {
        let today = DayKey(date: now)
        guard let stored = WidgetBridge.read() else { return TodaySnapshot.placeholder.emptied(for: today) }
        return stored.current(today: today)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NinaToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Calories left, protein, carbs, fat and water.")
        .supportedFamilies(families)
    }

    private var families: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
        #else
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var snapshot: TodaySnapshot { entry.snapshot }
    private var unit: EnergyUnit { snapshot.unit }
    private var remaining: Double { snapshot.remaining }
    private var leftText: String {
        remaining >= 0 ? Fmt.energy(remaining, unit: unit, showUnit: false) : "+" + Fmt.energy(-remaining, unit: unit, showUnit: false)
    }

    var body: some View {
        #if os(watchOS)
        if family == .accessoryCorner {
            Text(leftText)
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: min(snapshot.fraction, 1)) { Text(unit.symbol) }
                        .tint(Color.accentColor)
                }
        } else {
            familyView
        }
        #else
        familyView
        #endif
    }

    @ViewBuilder
    private var familyView: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(snapshot.fraction, 1)) {
                Image(systemName: "fork.knife")
            } currentValueLabel: {
                Text(leftText).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(remaining >= 0 ? "\(leftText) \(unit.symbol) left" : "\(leftText) \(unit.symbol) over")
                    .font(.headline)
                    .widgetAccentable()
                Text("P \(Fmt.number(snapshot.protein))/\(Fmt.number(snapshot.proteinGoal)) · C \(Fmt.number(snapshot.carbs)) · F \(Fmt.number(snapshot.fat))")
                    .font(.caption)
                if let next = snapshot.nextPlanned {
                    Text(next).font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Text(remaining >= 0 ? "\(leftText) \(unit.symbol) left" : "\(leftText) \(unit.symbol) over")
        default:
            #if os(iOS)
            if family == .systemMedium {
                medium
            } else {
                small
            }
            #else
            small
            #endif
        }
    }

    private var small: some View {
        VStack(spacing: 6) {
            ring
            if let next = snapshot.nextPlanned {
                Text(next).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .widgetURL(URL(string: "\(AppInfo.urlScheme)://add"))
    }

    #if os(iOS)
    /// Home Screen, medium: ring, macros, water and two buttons.
    private var medium: some View {
        HStack(spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 7) {
                bar(.protein, snapshot.protein, snapshot.proteinGoal)
                bar(.carbs, snapshot.carbs, snapshot.carbsGoal)
                bar(.fat, snapshot.fat, snapshot.fatGoal)
                HStack {
                    Label(Fmt.volume(snapshot.water), systemImage: "drop.fill")
                        .font(.caption)
                        .foregroundStyle(NutrientStyle.water)
                    Spacer()
                    #if os(iOS)
                    Link(destination: URL(string: "\(AppInfo.urlScheme)://water?ml=250")!) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(NutrientStyle.water)
                    }
                    Link(destination: URL(string: "\(AppInfo.urlScheme)://add")!) {
                        Image(systemName: "fork.knife.circle.fill").foregroundStyle(Color.accentColor)
                    }
                    #endif
                }
            }
        }
        .widgetURL(URL(string: "\(AppInfo.urlScheme)://today"))
    }
    #endif

    private var ring: some View {
        ZStack {
            ProgressRing(progress: snapshot.fraction, lineWidth: 11)
            VStack(spacing: -2) {
                Text(leftText)
                    .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                    .minimumScaleFactor(0.5)
                Text(remaining >= 0 ? "\(unit.symbol) left" : "\(unit.symbol) over")
                    .font(.caption2)
                    .foregroundStyle(remaining >= 0 ? Color.secondary : Color.orange)
            }
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: 110, maxHeight: 110)
    }

    private func bar(_ nutrient: Nutrient, _ value: Double, _ goal: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(nutrient.shortTitle).font(.caption2.weight(.medium))
                Spacer()
                Text("\(Fmt.number(value))/\(Fmt.number(goal)) g").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Gauge(value: min(goal > 0 ? value / goal : 0, 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(NutrientStyle.color(nutrient))
        }
    }
}
