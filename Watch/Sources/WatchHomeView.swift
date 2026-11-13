import SwiftUI
import SwiftData
import NinaCore

/// Today on the wrist: what's left, the priorities, water in one tap, planned meals to confirm,
/// and everything logged.
struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        WatchDayView(day: model.today)
            .id(model.today)
    }
}

private struct WatchDayView: View {
    let day: DayKey
    @Environment(WatchModel.self) private var model
    @Query private var entries: [LogEntry]
    @Query private var water: [WaterLog]

    init(day: DayKey) {
        self.day = day
        let key = day.rawValue
        _entries = Query(filter: #Predicate<LogEntry> { $0.day == key && $0.deletedAt == nil }, sort: \LogEntry.time)
        _water = Query(filter: #Predicate<WaterLog> { $0.day == key && $0.deletedAt == nil })
    }

    var body: some View {
        let settings = model.settings
        let targets = settings.targets(for: day)
        let eaten = NutrientValues.sum(entries.filter(\.isEaten).map(\.values))
        let remaining = targets.energy - eaten.energy
        let waterTotal = water.map(\.amount).reduce(0, +)
        let planned = entries.filter(\.isPlanned)
        List {
            Section {
                VStack(spacing: 8) {
                    ZStack {
                        ProgressRing(progress: targets.energy > 0 ? eaten.energy / targets.energy : 0, lineWidth: 10)
                        VStack(spacing: -2) {
                            Text(Fmt.energy(abs(remaining), unit: settings.energyUnit, showUnit: false))
                                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                                .minimumScaleFactor(0.6)
                            Text(remaining >= 0 ? "left" : "over")
                                .font(.caption2)
                                .foregroundStyle(remaining >= 0 ? Color.secondary : Color.orange)
                        }
                    }
                    .frame(width: 104, height: 104)
                    ForEach(settings.focus.prefix(3), id: \.self) { nutrient in
                        WatchBar(nutrient: nutrient, value: eaten.value(nutrient), target: targets.target(for: nutrient) ?? 0)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                NavigationLink {
                    WatchLogView()
                } label: {
                    Label("Log Food", systemImage: "fork.knife")
                        .foregroundStyle(Color.accentColor)
                }
                Button {
                    model.addWater(settings.waterGlass)
                } label: {
                    HStack {
                        Label("+\(Fmt.milliliters(settings.waterGlass))", systemImage: "drop.fill")
                            .foregroundStyle(NutrientStyle.water)
                        Spacer()
                        Text("\(Fmt.volume(waterTotal))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    WatchQuickCaloriesView()
                } label: {
                    Label("Quick Calories", systemImage: "bolt.fill")
                        .foregroundStyle(.orange)
                }
            }

            if !planned.isEmpty {
                Section("Planned") {
                    ForEach(planned) { entry in
                        Button {
                            model.store.confirm([entry])
                            WKHaptics.success()
                        } label: {
                            HStack {
                                Image(systemName: "circle")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading) {
                                    Text(entry.displayName).lineLimit(1)
                                    Text("\(settings.meal(entry.meal).name) · \(Fmt.time(entry.time))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            let eatenEntries = entries.filter(\.isEaten)
            if !eatenEntries.isEmpty {
                Section("Today · \(Fmt.energy(eaten.energy, unit: settings.energyUnit))") {
                    ForEach(eatenEntries.reversed()) { entry in
                        HStack {
                            Text(settings.meal(entry.meal).emoji)
                            VStack(alignment: .leading) {
                                Text(entry.displayName).lineLimit(1)
                                if let amount = entry.amountDescription {
                                    Text(amount).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(Fmt.energy(entry.energy, unit: settings.energyUnit, showUnit: false))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                model.store.trash([entry])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(AppInfo.name)
    }
}

/// A compact nutrient bar for the watch.
struct WatchBar: View {
    let nutrient: Nutrient
    let value: Double
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(nutrient.shortTitle).font(.caption2)
                Spacer()
                Text("\(Fmt.number(value)) / \(Fmt.nutrient(target, nutrient))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Gauge(value: min(target > 0 ? value / target : 0, 1)) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(NutrientStyle.color(nutrient))
        }
    }
}
