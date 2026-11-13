import SwiftUI
import SwiftData
import Charts
import BinisoftKit
import NinaCore

enum InsightRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, year = 365
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .quarter: "3 Months"
        case .year: "Year"
        }
    }
}

/// Everything Insights shows for a period, computed once per data change.
struct InsightData {
    struct DayPoint: Identifiable {
        let day: DayKey
        let date: Date
        let energy: Double
        let target: Double
        let verdict: String
        let logged: Bool
        var id: String { day.rawValue }
    }

    struct WeightPoint: Identifiable {
        let day: DayKey
        let date: Date
        let weight: Double?
        let trend: Double?
        var id: String { day.rawValue }
    }

    let range: InsightRange
    let points: [DayPoint]
    let stats: Insights.PeriodStats
    let streak: (current: Int, best: Int)
    let entries: [EntryFacts]
    let weights: [WeightPoint]
    let maintenance: Insights.Maintenance?
    let targets: DailyTargets

    @MainActor
    static func load(app: AppModel, range: InsightRange) -> InsightData {
        let store = app.store
        let settings = app.settings
        let today = app.today
        let start = today.adding(days: -(range.rawValue - 1))
        let entries = store.entries(from: start, through: today)
        let water = store.water(from: start, through: today)
        let waterByDay = Dictionary(grouping: water, by: \.day).mapValues { $0.map(\.amount).reduce(0, +) }
        let facts = entries.map(\.facts)
        let factsByDay = Dictionary(grouping: facts, by: \.day)
        let days = DayKey.range(start, through: today)
        let totals = days.map { DayTotals(day: $0, entries: factsByDay[$0] ?? [], water: waterByDay[$0.rawValue] ?? 0) }
        var mealTimes: [DayKey: (first: Int, last: Int)] = [:]
        for (day, list) in factsByDay {
            let minutes = list.filter { $0.status == .eaten }.map { ClockTime.minutes(of: $0.time) }
            if let first = minutes.min(), let last = minutes.max() { mealTimes[day] = (first, last) }
        }
        let stats = Insights.stats(totals: totals, targets: { settings.targets(for: $0) }, mealTimes: mealTimes)
        let points = totals.map { total -> DayPoint in
            let target = settings.targets(for: total.day).energy
            let verdict = DayProgress(totals: total, targets: settings.targets(for: total.day)).verdict
            let label: String
            switch verdict {
            case .onTrack: label = "On track"
            case .over: label = "Over"
            case .under: label = "Under"
            }
            return DayPoint(day: total.day, date: total.day.date(), energy: total.eaten.energy, target: target,
                            verdict: total.isLogged ? label : "Not logged", logged: total.isLogged)
        }

        // Logged days for the streak: look back further than the period.
        let streakStart = today.adding(days: -400)
        let streakDays = Set(store.entries(from: streakStart, through: today).filter(\.isEaten).map(\.dayKey))
        let streak = Insights.streaks(logged: streakDays, today: today)

        var weightsByDay = app.health.weights
        for entry in store.weights() { weightsByDay[entry.dayKey] = entry.kilograms }
        let trend = Insights.weightTrend(weightsByDay, through: today)
        let weights = trend.filter { $0.day >= start }.map {
            WeightPoint(day: $0.day, date: $0.day.date(), weight: $0.weight.isNaN ? nil : $0.weight, trend: $0.trend)
        }
        let longStart = today.adding(days: -27)
        let longTotals: [DayTotals]
        if start <= longStart {
            longTotals = totals.filter { $0.day >= longStart }
        } else {
            let more = store.entries(from: longStart, through: today).map(\.facts)
            let byDay = Dictionary(grouping: more, by: \.day)
            longTotals = DayKey.range(longStart, through: today).map { DayTotals(day: $0, entries: byDay[$0] ?? []) }
        }
        let maintenance = Insights.maintenance(totals: longTotals, weights: weightsByDay, today: today)
        return InsightData(range: range, points: points, stats: stats, streak: streak, entries: facts.filter { $0.status == .eaten },
                           weights: weights, maintenance: maintenance, targets: settings.targets)
    }
}

struct InsightsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("nina.insights.range") private var range: InsightRange = .month
    @State private var data: InsightData?
    @State private var topNutrient: Nutrient? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Period", selection: $range) {
                    ForEach(InsightRange.allCases) { range in Text(range.title).tag(range) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if let data {
                    if data.stats.loggedDays == 0 {
                        ContentUnavailableView("Nothing logged in this period", systemImage: "chart.bar.xaxis",
                                               description: Text("Insights fill up as you log. Importing your history from another app works too."))
                    } else {
                        caloriesCard(data)
                        consistencyCard(data)
                        macrosCard(data)
                        nutrientsCard(data)
                        topFoodsCard(data)
                        rhythmCard(data)
                    }
                    weightCard(data)
                } else {
                    ProgressView().padding(40)
                }
            }
            .padding()
            .readableWidth(920)
        }
        .background(Color.groupedBackground)
        .navigationTitle("Insights")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Log Weight…", systemImage: "scalemass") { app.sheet = .weight(nil) }
                    Button("Goals…", systemImage: "target") { app.sheet = .goals }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .task(id: "\(range.rawValue)-\(app.dataVersion)-\(app.health.weights.count)") {
            data = InsightData.load(app: app, range: range)
        }
    }

    private var unit: EnergyUnit { app.energyUnit }

    // MARK: Cards

    private func caloriesCard(_ data: InsightData) -> some View {
        let logged = data.points.filter(\.logged)
        return CardSection(title: "Calories", symbol: "flame.fill",
                           trailing: "⌀ \(Fmt.energy(data.stats.average.energy, unit: unit))") {
            Chart {
                ForEach(logged) { point in
                    if data.range.rawValue <= 30 {
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Energy", unit.value(fromKilocalories: point.energy)))
                            .foregroundStyle(by: .value("Verdict", point.verdict))
                            .cornerRadius(4)
                    } else {
                        LineMark(x: .value("Day", point.date, unit: .day), y: .value("Energy", unit.value(fromKilocalories: point.energy)))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Brand.accent)
                    }
                }
                RuleMark(y: .value("Goal", unit.value(fromKilocalories: data.stats.averageTarget)))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartForegroundStyleScale(["On track": Brand.accent, "Over": Color.orange, "Under": NutrientStyle.color(.protein).opacity(0.7), "Not logged": Color.gray])
            .chartLegend(data.range.rawValue <= 30 ? .visible : .hidden)
            .frame(height: 200)
            let balance = data.stats.averageBalance
            Text(balance >= 0
                 ? "On average \(Fmt.energy(balance, unit: unit)) above your goal per logged day."
                 : "On average \(Fmt.energy(-balance, unit: unit)) below your goal per logged day.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func consistencyCard(_ data: InsightData) -> some View {
        CardSection(title: "Consistency", symbol: "flame.circle",
                    trailing: "\(data.stats.loggedDays) of \(data.stats.days) days") {
            HStack(spacing: 24) {
                StatTile(title: "Streak", value: "\(data.streak.current) days", tint: Brand.accent)
                StatTile(title: "Best streak", value: "\(data.streak.best) days")
                StatTile(title: "On track", value: Fmt.percent(data.stats.onTrackShare), detail: "within ±10 % of the goal")
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: data.range == .week ? 7 : 15)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(data.points.suffix(data.range == .year ? 105 : data.points.count)) { point in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color(for: point))
                        .aspectRatio(1, contentMode: .fit)
                        .help("\(Fmt.shortDay(point.day)): \(point.logged ? Fmt.energy(point.energy, unit: unit) : "not logged")")
                }
            }
            HStack(spacing: 12) {
                legend("On track", Brand.accent)
                legend("Over", .orange)
                legend("Under", NutrientStyle.color(.protein).opacity(0.7))
                legend("Not logged", Color.secondary.opacity(0.18))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func macrosCard(_ data: InsightData) -> some View {
        let average = data.stats.average
        let shares = data.stats.macroShares
        let slices = [MacroSlice(nutrient: .protein, share: shares.protein), MacroSlice(nutrient: .carbs, share: shares.carbs),
                      MacroSlice(nutrient: .fat, share: shares.fat)]
        return CardSection(title: "Macros", symbol: "chart.pie.fill", trailing: "\(shares.percentText) %") {
            HStack(alignment: .center, spacing: 20) {
                Chart {
                    ForEach(slices) { slice in
                        SectorMark(angle: .value("Share", slice.share), innerRadius: .ratio(0.62), angularInset: 2)
                            .foregroundStyle(NutrientStyle.color(slice.nutrient))
                            .cornerRadius(4)
                    }
                }
                .frame(width: 130, height: 130)
                VStack(spacing: 10) {
                    ForEach(Nutrient.macros, id: \.self) { nutrient in
                        NutrientBar(nutrient: nutrient, value: average.value(nutrient), target: data.targets.target(for: nutrient) ?? 0, unit: unit)
                    }
                }
            }
            let split = data.targets.split
            Text("Your target split is \(split.percentText) % (protein / carbs / fat). Averages are per logged day.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func nutrientsCard(_ data: InsightData) -> some View {
        let average = data.stats.average
        return CardSection(title: "Fiber, sugar, fat & salt", symbol: "leaf.fill") {
            VStack(spacing: 10) {
                NutrientBar(nutrient: .fiber, value: average.value(.fiber), target: data.targets.fiber, unit: unit)
                NutrientBar(nutrient: .sugar, value: average.value(.sugar), target: data.targets.sugarMax, unit: unit)
                NutrientBar(nutrient: .saturatedFat, value: average.value(.saturatedFat), target: data.targets.saturatedFatMax, unit: unit)
                NutrientBar(nutrient: .sodium, value: average.value(.sodium), target: data.targets.sodiumMax, unit: unit)
                NutrientBar(nutrient: .water, value: data.stats.averageWater, target: data.targets.water, unit: unit)
            }
            Text("Sugar, saturated fat and salt are limits (WHO): less is better. Fiber and water are goals.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func topFoodsCard(_ data: InsightData) -> some View {
        let top = Insights.topFoods(data.entries, by: topNutrient, limit: 8)
        return CardSection(title: "Top foods", symbol: "trophy.fill") {
            Picker("Rank by", selection: $topNutrient) {
                Text("Most often").tag(Nutrient?.none)
                Text("Calories").tag(Optional(Nutrient.energy))
                Text("Protein").tag(Optional(Nutrient.protein))
                Text("Sugar").tag(Optional(Nutrient.sugar))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            VStack(spacing: 8) {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, rank in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)
                        CategoryBadge(category: rank.category, size: 28)
                        Text(rank.name).lineLimit(1)
                        Spacer()
                        Text("\(rank.count)×").foregroundStyle(.secondary).monospacedDigit()
                        if let nutrient = topNutrient {
                            Text(Fmt.nutrient(rank.total.value(nutrient), nutrient, unit: unit))
                                .monospacedDigit()
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func rhythmCard(_ data: InsightData) -> some View {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let weekdays = (1...7).map { WeekdayValue(name: names[$0 - 1], value: data.stats.byWeekday[$0] ?? 0) }
        return CardSection(title: "Rhythm", symbol: "clock.fill") {
            HStack(spacing: 24) {
                if let first = data.stats.firstMealMinutes {
                    StatTile(title: "First meal ⌀", value: Fmt.clock(first))
                }
                if let last = data.stats.lastMealMinutes {
                    StatTile(title: "Last meal ⌀", value: Fmt.clock(last))
                }
                if let first = data.stats.firstMealMinutes, let last = data.stats.lastMealMinutes, last > first {
                    StatTile(title: "Eating window", value: "\((last - first) / 60) h \((last - first) % 60) min")
                }
            }
            Chart {
                ForEach(weekdays) { day in
                    BarMark(x: .value("Weekday", day.name), y: .value("Energy", unit.value(fromKilocalories: day.value)))
                        .foregroundStyle(Brand.accent.gradient)
                        .cornerRadius(4)
                }
            }
            .frame(height: 140)
            Text("Average calories per weekday – weekends often look different.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func weightCard(_ data: InsightData) -> some View {
        let measured = data.weights.compactMap(\.weight)
        let trends = data.weights.compactMap(\.trend)
        return CardSection(title: "Weight", symbol: "scalemass.fill", trailing: trends.last.map { Fmt.kilograms($0) }) {
            if measured.isEmpty {
                Text("Log your weight (or allow Apple Health) to see your trend and your measured maintenance calories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Log Weight", systemImage: "plus") { app.sheet = .weight(nil) }
            } else {
                let low = (min(measured.min() ?? 0, trends.min() ?? 0) - 0.5).rounded(.down)
                let high = (max(measured.max() ?? 0, trends.max() ?? 0) + 0.5).rounded(.up)
                Chart {
                    ForEach(data.weights) { point in
                        if let weight = point.weight {
                            PointMark(x: .value("Day", point.date, unit: .day), y: .value("Weight", weight))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                                .symbolSize(18)
                        }
                        if let trend = point.trend {
                            LineMark(x: .value("Day", point.date, unit: .day), y: .value("Trend", trend))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Brand.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                    }
                }
                .chartYScale(domain: low...max(high, low + 1))
                .frame(height: 180)
                if let first = trends.first, let last = trends.last {
                    let change = last - first
                    Text("Trend \(change >= 0 ? "+" : "−")\(Fmt.kilograms(abs(change))) in this period. The line smooths out daily water swings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let maintenance = data.maintenance {
                Divider()
                MaintenanceView(maintenance: maintenance)
            }
            NavigationLink {
                WeightView()
            } label: {
                Label("All weigh-ins", systemImage: "list.bullet")
            }
        }
    }

    private func color(for point: InsightData.DayPoint) -> Color {
        guard point.logged else { return Color.secondary.opacity(0.18) }
        switch point.verdict {
        case "On track": return Brand.accent
        case "Over": return .orange
        default: return NutrientStyle.color(.protein).opacity(0.7)
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }
}

private struct MacroSlice: Identifiable {
    let nutrient: Nutrient
    let share: Double
    var id: String { nutrient.rawValue }
}

private struct WeekdayValue: Identifiable {
    let name: String
    let value: Double
    var id: String { name }
}

/// "Your measured maintenance": what your intake and weight trend say, explained with your numbers.
struct MaintenanceView: View {
    let maintenance: Insights.Maintenance
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Measured maintenance", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Fmt.energy(maintenance.kilocalories, unit: app.energyUnit))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Brand.accent)
            }
            Text("Over \(maintenance.days) days you ate \(Fmt.energy(maintenance.averageIntake, unit: app.energyUnit)) on average and your trend weight changed by \(maintenance.weightChange >= 0 ? "+" : "−")\(Fmt.kilograms(abs(maintenance.weightChange), decimals: 2)). One kg of body weight is about 7,700 kcal, so your body burns about \(Fmt.energy(maintenance.kilocalories, unit: app.energyUnit)) a day. Confidence: \(maintenance.confidence.rawValue) (\(maintenance.loggedDays) logged days).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Use for My Goal…") { app.sheet = .goals }
                .font(.footnote)
        }
    }
}
