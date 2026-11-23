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

/// Everything Insights shows for a period, computed once per data change. Averages, the
/// balance, day types, protein meals, rhythm and the measured maintenance count finished days
/// only: today counts once it's over, and days marked "Log Is Incomplete" never do. The chart
/// and the consistency grid show every day.
struct InsightData {
    struct DayPoint: Identifiable {
        let day: DayKey
        let date: Date
        let energy: Double
        let target: Double
        /// "On track", "Over", "Under", "Today" (logged, not over yet) or "Not logged".
        let verdict: String
        let logged: Bool
        var id: String { day.rawValue }
        var isToday: Bool { verdict == InsightVerdict.today }
    }

    /// The weight card's header: the 7-day average of the morning weights, as Body, Today and the
    /// check-in show it, else the trend.
    struct WeightHeader {
        let hasWeighIns: Bool
        let average: Double?
        let trend: Double?
    }

    let range: InsightRange
    let points: [DayPoint]
    /// Over the finished days.
    let stats: Insights.PeriodStats
    /// Every logged day of the period, today included (the consistency grid).
    let loggedDays: Int
    let streak: (current: Int, best: Int)
    let entries: [EntryFacts]
    let weight: WeightHeader
    let maintenance: Insights.Maintenance?
    /// The targets averaged over the finished days (each day with its own day type's grams).
    let targets: DailyTargets
    /// "Protein meals 21 of 28" over the finished days (nil without a per-meal minimum).
    let proteinMeals: ProgressProteinMeals?
    /// Eaten vs. target per day type (plans with 2 or more day types).
    let typeAverages: [ProgressTypeAverage]
    /// The long-term body goal, compact (nil without one).
    let goal: BodyPageGoal?

    /// Today is logged (its bar shows in the "Today" style).
    var showsToday: Bool { points.contains { $0.isToday } }

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
        let incomplete = store.incompleteDays(from: start, through: today)
        let unfinished = Insights.unfinishedDays(totals, today: today, incomplete: incomplete)
        let finished = totals.filter { !unfinished.contains($0.day) }
        let stats = Insights.stats(totals: totals, targets: { settings.targets(for: $0) }, mealTimes: mealTimes,
                                   excluding: unfinished)
        let points = totals.map { point(for: $0, today: today, settings: settings) }
        let signal = store.weightSignal(adding: app.healthWeightReadings, settings: settings)
        return InsightData(range: range, points: points, stats: stats, loggedDays: totals.filter(\.isLogged).count,
                           streak: Insights.streaks(logged: streakDays(store: store, through: today), today: today),
                           entries: facts.filter { $0.status == .eaten },
                           weight: WeightHeader(hasWeighIns: !signal.days.isEmpty || !signal.others.isEmpty,
                                                average: signal.average(on: today).value, trend: signal.trend(on: today)),
                           maintenance: measuredMaintenance(app: app, signal: signal, start: start, totals: totals),
                           targets: stats.averageTargets,
                           proteinMeals: ProgressInsights.proteinMeals(totals: finished, settings: settings, incomplete: incomplete),
                           typeAverages: ProgressInsights.typeAverages(totals: finished, settings: settings, incomplete: incomplete),
                           goal: ProgressInsights.goal(app: app))
    }

    private static func point(for total: DayTotals, today: DayKey, settings: NinaSettings) -> DayPoint {
        let targets = settings.targets(for: total.day)
        let verdict: String
        if !total.isLogged {
            verdict = InsightVerdict.notLogged
        } else if total.day >= today {
            verdict = InsightVerdict.today
        } else {
            switch DayProgress(totals: total, targets: targets).verdict {
            case .onTrack: verdict = InsightVerdict.onTrack
            case .over: verdict = InsightVerdict.over
            case .under: verdict = InsightVerdict.under
            }
        }
        return DayPoint(day: total.day, date: total.day.date(), energy: total.eaten.energy, target: targets.energy,
                        verdict: verdict, logged: total.isLogged)
    }

    /// The days with something eaten in the 400 days through `today` (the streak), read without
    /// the entries' nutrients.
    @MainActor
    private static func streakDays(store: NinaStore, through today: DayKey) -> Set<DayKey> {
        let first = today.adding(days: -400).rawValue, last = today.rawValue
        let eaten = EntryStatus.eaten.rawValue
        var descriptor = FetchDescriptor<LogEntry>(
            predicate: #Predicate<LogEntry> { $0.day >= first && $0.day <= last && $0.deletedAt == nil && $0.status == eaten }
        )
        descriptor.propertiesToFetch = [\.day, \.time]
        let entries = (try? store.context.fetch(descriptor)) ?? []
        return Set(entries.map(\.dayKey))
    }

    /// Measured maintenance as the coach reads it: the morning weights (typed and live Apple
    /// Health), the 28 days through yesterday, without days marked "Log Is Incomplete" or paused.
    @MainActor
    private static func measuredMaintenance(app: AppModel, signal: WeightSignal, start: DayKey,
                                            totals: [DayTotals]) -> Insights.Maintenance? {
        let store = app.store
        let plan = app.settings.plan
        let yesterday = app.today.adding(days: -1)
        let longStart = yesterday.adding(days: -27)
        let longTotals: [DayTotals]
        if start <= longStart {
            longTotals = totals.filter { $0.day >= longStart && $0.day <= yesterday }
        } else {
            let more = store.entries(from: longStart, through: yesterday).map(\.facts)
            let byDay = Dictionary(grouping: more, by: \.day)
            longTotals = DayKey.range(longStart, through: yesterday).map { DayTotals(day: $0, entries: byDay[$0] ?? []) }
        }
        let paused = Set(longTotals.map(\.day).filter { plan.isPaused(on: $0) })
        let excluded = store.incompleteDays(from: longStart, through: yesterday).union(paused)
        return Insights.maintenance(totals: longTotals, weights: signal.morningWeights, today: yesterday, excluding: excluded)
    }
}

/// The verdict names of the calories chart and the consistency grid.
private enum InsightVerdict {
    static let onTrack = "On track"
    static let over = "Over"
    static let under = "Under"
    static let today = "Today"
    static let notLogged = "Not logged"
}

struct InsightsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("nina.insights.range") private var range: InsightRange = .month
    /// The tape formula picked on this device (the compact body goal can depend on it).
    @AppStorage(BodyPageKeys.navyFormula) private var navyFormula = ""
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
                    cards(data)
                } else {
                    ProgressView().padding(40)
                }
            }
            .padding()
            .readableWidth(920)
        }
        .background(Color.groupedBackground)
        .navigationTitle(pageTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Log Weight…", systemImage: "scalemass") { app.sheet = .weight(nil) }
                    Button("Goals & Plan…", systemImage: "target") { app.sheet = .goals }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .task(id: loadKey) {
            data = InsightData.load(app: app, range: range)
        }
    }

    private var unit: EnergyUnit { app.energyUnit }

    /// "Nutrition" under Progress on iPhone and iPad (the segment's name); the Mac sidebar calls it Insights.
    private var pageTitle: String {
        #if os(macOS)
        "Insights"
        #else
        "Nutrition"
        #endif
    }

    /// Reload on range and data changes, when Apple Health weights arrive (read live, never
    /// stored) and when a tape formula is picked.
    private var loadKey: String {
        "\(range.rawValue)-\(app.dataVersion)-\(app.health.weights.count)-\(app.health.weightSamples.count)-\(navyFormula)"
    }

    // MARK: Cards

    /// The cards; the ones made of averages wait for a finished day (today counts once it's over).
    @ViewBuilder
    private func cards(_ data: InsightData) -> some View {
        if data.loggedDays == 0 {
            ContentUnavailableView("Nothing logged in this period", systemImage: "chart.bar.xaxis",
                                   description: Text("Insights fill up as you log. Importing your history from another app works too."))
        } else {
            caloriesCard(data)
            if !data.typeAverages.isEmpty {
                ProgressTypeAveragesCard(rows: data.typeAverages, unit: unit)
            }
            consistencyCard(data)
            if data.stats.loggedDays > 0 {
                macrosCard(data)
                nutrientsCard(data)
            }
            topFoodsCard(data)
            if data.stats.loggedDays > 0 {
                rhythmCard(data)
            }
        }
        if let goal = data.goal {
            ProgressGoalCard(goal: goal)
        }
        weightCard(data)
    }

    private func caloriesCard(_ data: InsightData) -> some View {
        let trailing: String? = data.stats.loggedDays > 0 ? "avg \(Fmt.energy(data.stats.average.energy, unit: unit))" : nil
        return CardSection(title: "Calories", symbol: "flame.fill", trailing: trailing) {
            caloriesChart(data)
            Text(balanceText(data))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func caloriesChart(_ data: InsightData) -> some View {
        let logged = data.points.filter(\.logged)
        let isBars = data.range.rawValue <= 30
        let goal = unit.value(fromKilocalories: data.stats.loggedDays > 0 ? data.stats.averageTarget : data.stats.averageTargets.energy)
        let scale = verdictScale(showsToday: data.showsToday)
        return Chart {
            ForEach(logged) { point in
                if isBars {
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Energy", unit.value(fromKilocalories: point.energy)))
                        .foregroundStyle(by: .value("Verdict", point.verdict))
                        .cornerRadius(4)
                } else {
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("Energy", unit.value(fromKilocalories: point.energy)))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Brand.accent)
                }
            }
            RuleMark(y: .value("Goal", goal))
                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .foregroundStyle(.secondary)
        }
        .chartForegroundStyleScale(domain: scale.domain, range: scale.range)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: data.range == .week ? 7 : 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic)
            AxisMarks(position: .leading, values: [goal]) { _ in
                AxisValueLabel("Goal")
            }
        }
        .chartLegend(isBars ? .visible : .hidden)
        .frame(height: 200)
    }

    /// The bar colours: on track, over, under, and today's bar while the day isn't over.
    private func verdictScale(showsToday: Bool) -> (domain: [String], range: [Color]) {
        var domain = [InsightVerdict.onTrack, InsightVerdict.over, InsightVerdict.under]
        var range: [Color] = [Brand.accent, Color.orange, InsightsView.underColor]
        if showsToday {
            domain.append(InsightVerdict.today)
            range.append(InsightsView.todayColor)
        }
        return (domain, range)
    }

    private static var underColor: Color { NutrientStyle.color(.protein).opacity(0.7) }
    private static var todayColor: Color { Brand.accent.opacity(0.3) }

    private func balanceText(_ data: InsightData) -> String {
        let note = data.showsToday ? " Today counts once it's over." : ""
        guard data.stats.loggedDays > 0 else { return "Today counts once it's over." }
        let balance = data.stats.averageBalance
        let text = balance >= 0
            ? "On average \(Fmt.energy(balance, unit: unit)) above your goal per logged day."
            : "On average \(Fmt.energy(-balance, unit: unit)) below your goal per logged day."
        return text + note
    }

    private func consistencyCard(_ data: InsightData) -> some View {
        CardSection(title: "Consistency", symbol: "flame.circle",
                    trailing: "\(data.loggedDays) of \(InsightsView.days(data.points.count))") {
            HStack(spacing: 24) {
                StatTile(title: "Streak", value: InsightsView.days(data.streak.current), tint: Brand.accent)
                StatTile(title: "Best streak", value: InsightsView.days(data.streak.best))
                StatTile(title: "On track", value: Fmt.percent(data.stats.onTrackShare), detail: "within ±10 % of the goal")
            }
            consistencyGrid(data)
            HStack(spacing: 12) {
                legend(InsightVerdict.onTrack, Brand.accent)
                legend(InsightVerdict.over, .orange)
                legend(InsightVerdict.under, InsightsView.underColor)
                legend(InsightVerdict.notLogged, Color.secondary.opacity(0.18))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    /// One square per day; VoiceOver reads the grid as one summary.
    private func consistencyGrid(_ data: InsightData) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: data.range == .week ? 7 : 15)
        let shown = Array(data.points.suffix(data.range == .year ? 105 : data.points.count))
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(shown) { point in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(for: point))
                    .aspectRatio(1, contentMode: .fit)
                    .help("\(Fmt.shortDay(point.day)): \(point.logged ? Fmt.energy(point.energy, unit: unit) : "not logged")")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Logged days")
        .accessibilityValue(gridSummary(shown))
    }

    /// "21 of 30 days logged: 15 on track, 3 over, 3 under."
    private func gridSummary(_ points: [InsightData.DayPoint]) -> String {
        func count(_ verdict: String) -> Int { points.filter { $0.verdict == verdict }.count }
        let logged = points.filter(\.logged).count
        var parts = ["\(count(InsightVerdict.onTrack)) on track", "\(count(InsightVerdict.over)) over",
                     "\(count(InsightVerdict.under)) under"]
        if count(InsightVerdict.today) > 0 { parts.append("today not over yet") }
        return "\(logged) of \(InsightsView.days(points.count)) logged: " + parts.joined(separator: ", ")
    }

    /// "1 day", "12 days".
    private static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
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
            Text("Your target split is \(split.percentText) % (protein / carbs / fat). Averages are per logged day, each day against its own targets.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let protein = data.proteinMeals {
                Divider()
                ProgressProteinMealsRow(protein: protein)
            }
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
                        CategoryBadge(category: rank.category, emoji: FoodEmoji.emoji(for: [rank.name], category: rank.category), size: 28)
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
                    StatTile(title: "First meal, avg", value: Fmt.clock(first))
                }
                if let last = data.stats.lastMealMinutes {
                    StatTile(title: "Last meal, avg", value: Fmt.clock(last))
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

    /// The weight chart lives on the Body page; here the 7-day average (as Body shows it), a way
    /// there and the measured maintenance (it comes from your intake).
    private func weightCard(_ data: InsightData) -> some View {
        CardSection(title: "Weight", symbol: "scalemass.fill", trailing: weightHeader(data.weight)) {
            if !data.weight.hasWeighIns {
                Text("Log your weight (or allow Apple Health) to see your measured maintenance calories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Log Weight", systemImage: "plus") { app.sheet = .weight(nil) }
            } else {
                Text("Your weight chart, measurements and body fat are on the Body page.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Open Body", systemImage: "figure") { app.showProgress(.body) }
            if let maintenance = data.maintenance {
                Divider()
                MaintenanceView(maintenance: maintenance)
            }
        }
    }

    /// "7-day avg 67.1 kg", else "Trend 67.0 kg" while there aren't four morning weigh-ins in the week.
    private func weightHeader(_ weight: InsightData.WeightHeader) -> String? {
        if let average = weight.average { return "7-day avg \(Fmt.kilograms(average))" }
        if let trend = weight.trend { return "Trend \(Fmt.kilograms(trend))" }
        return nil
    }

    private func color(for point: InsightData.DayPoint) -> Color {
        guard point.logged else { return Color.secondary.opacity(0.18) }
        switch point.verdict {
        case InsightVerdict.onTrack: return Brand.accent
        case InsightVerdict.over: return .orange
        case InsightVerdict.today: return InsightsView.todayColor
        default: return InsightsView.underColor
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
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Use for My Goal…") { app.sheet = .goals }
                .font(.footnote)
        }
    }

    /// Up to yesterday, with the weight trend of the morning weigh-ins (the coach's numbers).
    private var explanation: String {
        let unit = app.energyUnit
        let sign = maintenance.weightChange >= 0 ? "+" : "−"
        let change = sign + Fmt.kilograms(abs(maintenance.weightChange), decimals: 2)
        return "Over \(maintenance.days) days up to yesterday you ate \(Fmt.energy(maintenance.averageIntake, unit: unit)) on average "
            + "and the trend of your morning weigh-ins changed by \(change). One kg of body weight is about 7,700 kcal, "
            + "so your body burns about \(Fmt.energy(maintenance.kilocalories, unit: unit)) a day. "
            + "Confidence: \(maintenance.confidence.rawValue) (\(maintenance.loggedDays) logged days; days marked incomplete and paused days left out)."
    }
}
