import WidgetKit
import SwiftUI
import NinaCore

/// Today's numbers on the Home Screen, Lock Screen and watch face. Widgets only read the small
/// snapshots the app writes to the shared App Group (WidgetBridge) – never the diary itself.
/// The same source builds the iPhone widget extension and the watch complications; the coach
/// widget and the controls (Control Center, Lock Screen, Action button) are iPhone only.
@main
struct NinaWidgets: WidgetBundle {
    var body: some Widget {
        #if os(iOS)
        TodayWidget()
        CoachWidget()
        NinaLogFoodControl()
        NinaWeighInControl()
        NinaAddWaterControl()
        #else
        TodayWidget()
        #endif
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
        let now = Date()
        let snapshot = context.isPreview ? TodaySnapshot.placeholder : stored.current(now: now)
        completion(TodayEntry(date: now, snapshot: snapshot))
    }

    /// The app reloads timelines when the numbers change. In between, the "next planned" line moves
    /// on at each planned time, and the day changes when the diary's day starts (Settings → Day
    /// starts at), not at midnight (`TodaySnapshot.timeline`).
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let snapshot = stored
        let entries = snapshot.timeline(now: now).map { TodayEntry(date: $0.date, snapshot: $0.snapshot) }
        let reload = snapshot.nextDayStart(after: now).addingTimeInterval(60)
        completion(Timeline(entries: entries, policy: .after(reload)))
    }

    /// What the app wrote last; before its first write an empty day with sample goals.
    private var stored: TodaySnapshot {
        WidgetBridge.read() ?? TodaySnapshot.placeholder
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NinaToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Calories left with today's day type, protein, carbs, fat and water.")
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
    /// Always kcal (`TodaySnapshot.unit`).
    private var unit: EnergyUnit { snapshot.unit }
    private var remaining: Double { snapshot.remaining }
    /// "1,240" left or "120" over – the word next to it says which.
    private var amountText: String {
        Fmt.number(abs(remaining).rounded(), decimals: 0)
    }
    /// For faces without a word: "+120" when over.
    private var signedText: String {
        remaining >= 0 ? amountText : "+" + amountText
    }
    /// The plan's day type in front of the numbers ("🏋️ "); "" without day types.
    private var dayPrefix: String { snapshot.dayTypePrefix }
    /// "🏋️ 1,240 kcal left" / "🏋️ 120 kcal over".
    private var leftLine: String {
        remaining >= 0 ? "\(dayPrefix)\(amountText) \(unit.symbol) left" : "\(dayPrefix)\(amountText) \(unit.symbol) over"
    }

    var body: some View {
        #if os(watchOS)
        if family == .accessoryCorner {
            Text(dayPrefix + signedText)
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
                circularLabel
            } currentValueLabel: {
                Text(signedText).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(leftLine)
                    .font(.headline)
                    .widgetAccentable()
                Text("P \(Fmt.number(snapshot.protein))/\(Fmt.number(snapshot.proteinGoal)) · C \(Fmt.number(snapshot.carbs)) · F \(Fmt.number(snapshot.fat))")
                    .font(.caption)
                if let next = snapshot.nextPlanned {
                    Text(next).font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Text(leftLine)
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

    /// The circular complication's label: the day type's emoji, else a fork and knife.
    @ViewBuilder
    private var circularLabel: some View {
        if let emoji = snapshot.dayTypeEmoji, !emoji.isEmpty {
            Text(emoji)
        } else {
            Image(systemName: "fork.knife")
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
                    // No amount: the app adds the glass size from Settings.
                    Link(destination: URL(string: "\(AppInfo.urlScheme)://water")!) {
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
                if let emoji = snapshot.dayTypeEmoji, !emoji.isEmpty {
                    Text(emoji).font(.caption)
                }
                Text(amountText)
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
