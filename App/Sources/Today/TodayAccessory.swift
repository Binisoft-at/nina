import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

#if os(iOS)
/// The Liquid Glass bar above the tab bar: what's left today, one tap to log or add water.
struct TodayAccessory: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TodayAccessoryContent(day: app.today)
            .id(app.today)
    }
}

private struct TodayAccessoryContent: View {
    let day: DayKey
    @Environment(AppModel.self) private var app
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Query private var entries: [LogEntry]

    init(day: DayKey) {
        self.day = day
        let key = day.rawValue
        _entries = Query(filter: #Predicate<LogEntry> { $0.day == key && $0.deletedAt == nil })
    }

    var body: some View {
        let eaten = NutrientValues.sum(entries.filter(\.isEaten).map(\.values))
        let targets = app.settings.targets(for: day)
        let budget = targets.energy + app.health.activeEnergyToday * app.settings.activityBonusShare
        let remaining = budget - eaten.energy
        let fraction = budget > 0 ? eaten.energy / budget : 0
        HStack(spacing: 12) {
            Button {
                app.show(day: day)
            } label: {
                HStack(spacing: 10) {
                    ProgressRing(progress: fraction, lineWidth: 4)
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(TodayLeftText.text(remaining, unit: app.energyUnit, emoji: app.settings.todayCoachEmoji(for: day)))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(remaining >= 0 ? Color.primary : Color.orange)
                        if placement != .inline, let first = app.settings.focus.first {
                            Text("\(first.shortTitle) \(Fmt.number(eaten.value(first))) of \(Fmt.nutrient(targets.target(for: first), first))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            Button {
                app.addWater(app.settings.waterGlass, day: day)
            } label: {
                Image(systemName: "drop.fill")
                    .foregroundStyle(NutrientStyle.water)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(Fmt.milliliters(app.settings.waterGlass)) water")
            Button {
                app.sheet = .addFood(day: day, meal: nil)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Brand.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log Food")
        }
        .padding(.horizontal, 16)
    }
}
#endif

/// Today in one line (Mac sidebar, compact places).
struct TodaySummaryLine: View {
    let day: DayKey
    @Environment(AppModel.self) private var app
    @Query private var entries: [LogEntry]

    init(day: DayKey) {
        self.day = day
        let key = day.rawValue
        _entries = Query(filter: #Predicate<LogEntry> { $0.day == key && $0.deletedAt == nil })
    }

    var body: some View {
        let eaten = NutrientValues.sum(entries.filter(\.isEaten).map(\.values))
        let targets = app.settings.targets(for: day)
        let remaining = targets.energy - eaten.energy
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProgressRing(progress: targets.energy > 0 ? eaten.energy / targets.energy : 0, lineWidth: 5)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                    Text(TodayLeftText.text(remaining, unit: app.energyUnit, emoji: app.settings.todayCoachEmoji(for: day)))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
            ForEach(app.settings.focus.prefix(3), id: \.self) { nutrient in
                NutrientBar(nutrient: nutrient, value: eaten.value(nutrient), target: targets.target(for: nutrient) ?? 0,
                            unit: app.energyUnit, compact: true)
            }
        }
        .contentShape(.rect)
        .onTapGesture { app.show(day: day) }
    }
}

/// "🏋️ 1,240 kcal left" / "180 kcal over": what's left of the day's target (the plan's day-type
/// target with a plan), with the day type's emoji in front.
private enum TodayLeftText {
    static func text(_ remaining: Double, unit: EnergyUnit, emoji: String?) -> String {
        let amount = remaining >= 0 ? "\(Fmt.energy(remaining, unit: unit)) left" : "\(Fmt.energy(-remaining, unit: unit)) over"
        guard let emoji else { return amount }
        return "\(emoji) \(amount)"
    }
}
