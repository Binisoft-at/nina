import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// The ring with what's left, eaten / budget and the focus nutrients (the person's priorities).
struct DaySummaryCard: View {
    let day: DayKey
    let progress: DayProgress
    let focus: [Nutrient]
    let unit: EnergyUnit
    var isTrainingDay = false

    @Environment(AppModel.self) private var app

    private var remaining: Double { progress.energyRemaining }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    ProgressRing(progress: progress.energyFraction, lineWidth: 16,
                                 planned: progress.energyBudget > 0 ? progress.totals.projected.energy / progress.energyBudget : 0)
                    VStack(spacing: 0) {
                        Text(Fmt.energy(abs(remaining), unit: unit, showUnit: false))
                            .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                            .contentTransition(.numericText(value: remaining))
                            .minimumScaleFactor(0.6)
                        Text(remaining >= 0 ? "\(unit.symbol) left" : "\(unit.symbol) over")
                            .font(.caption)
                            .foregroundStyle(remaining >= 0 ? Color.secondary : Color.orange)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(width: 138, height: 138)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Fmt.energy(abs(remaining), unit: unit)) \(remaining >= 0 ? "left" : "over")")

                VStack(alignment: .leading, spacing: 10) {
                    StatTile(title: "Eaten", value: Fmt.energy(progress.energyEaten, unit: unit))
                    StatTile(title: progress.activityBonus > 0 ? "Budget incl. activity" : (isTrainingDay ? "Training day goal" : "Goal"),
                             value: Fmt.energy(progress.energyBudget, unit: unit),
                             detail: progress.activityBonus > 0 ? "+\(Fmt.energy(progress.activityBonus, unit: unit)) from Apple Health" : nil)
                    if progress.totals.plannedCount > 0 {
                        Label("\(Fmt.energy(progress.totals.planned.energy, unit: unit)) planned", systemImage: "circle.dashed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 10) {
                ForEach(focus.prefix(4), id: \.self) { nutrient in
                    NutrientBar(nutrient: nutrient, value: progress.totals.eaten.value(nutrient),
                                target: progress.targets.target(for: nutrient) ?? 0, unit: unit)
                }
            }
        }
        .padding(18)
        .background(Color.cardBackground, in: .rect(cornerRadius: 24, style: .continuous))
        .contentShape(.rect)
        .onTapGesture(count: 2) { app.sheet = .dayNutrition(day) }
    }
}

/// Seven days with a tiny ring each; tap a day, swipe or use the arrows for other weeks.
struct WeekStrip: View {
    let selected: DayKey

    @Environment(AppModel.self) private var app
    @Query private var entries: [LogEntry]
    private let days: [DayKey]

    init(selected: DayKey) {
        self.selected = selected
        let start = selected.startOfWeek()
        let end = start.adding(days: 6)
        days = DayKey.range(start, through: end)
        let first = start.rawValue, last = end.rawValue
        _entries = Query(filter: #Predicate<LogEntry> { $0.day >= first && $0.day <= last && $0.deletedAt == nil })
    }

    var body: some View {
        let energyByDay = Dictionary(grouping: entries.filter(\.isEaten), by: \.day).mapValues { $0.map(\.energy).reduce(0, +) }
        HStack(spacing: 4) {
            Button {
                withAnimation(.snappy) { app.selectedDay = selected.adding(days: -7) }
            } label: {
                Image(systemName: "chevron.left").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous week")
            ForEach(days) { day in
                let target = app.settings.targets(for: day).energy
                let fraction = target > 0 ? (energyByDay[day.rawValue] ?? 0) / target : 0
                Button {
                    withAnimation(.snappy) { app.selectedDay = day }
                } label: {
                    VStack(spacing: 4) {
                        Text(Fmt.weekdayLetter(day))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(day == app.today ? Brand.accent : .secondary)
                        ZStack {
                            ProgressRing(progress: fraction, lineWidth: 3.5)
                            Text("\(day.day)")
                                .font(.caption.weight(day == selected ? .bold : .regular).monospacedDigit())
                                .foregroundStyle(day == selected ? Color.white : .primary)
                                .frame(width: 24, height: 24)
                                .background(day == selected ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.clear), in: .circle)
                        }
                        .frame(width: 34, height: 34)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Fmt.dayTitle(day, today: app.today))
            }
            Button {
                withAnimation(.snappy) { app.selectedDay = selected.adding(days: 7) }
            } label: {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Next week")
        }
        .gesture(
            DragGesture(minimumDistance: 25).onEnded { value in
                guard abs(value.translation.width) > 60 else { return }
                withAnimation(.snappy) { app.selectedDay = selected.adding(days: value.translation.width < 0 ? 7 : -7) }
            }
        )
    }
}

/// One meal: header with its total and a + menu, the entries, drop target for moving entries here.
struct MealSection: View {
    let slot: MealSlot
    let day: DayKey
    let entries: [LogEntry]

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<Recipe> { $0.deletedAt == nil }, sort: \Recipe.sortOrder) private var recipes: [Recipe]

    private var eatenEnergy: Double { entries.filter(\.isEaten).map(\.energy).reduce(0, +) }
    private var planned: [LogEntry] { entries.filter(\.isPlanned) }

    var body: some View {
        Section {
            ForEach(entries) { entry in
                EntryRow(entry: entry, unit: app.energyUnit) { app.confirm([entry]) }
                    .tag(entry.uuid)
                    .draggable(entry.uuid.uuidString)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if entry.isPlanned {
                            Button("Eaten", systemImage: "checkmark") { app.confirm([entry]) }
                                .tint(Brand.accent)
                        } else {
                            Button("Again", systemImage: "arrow.clockwise") { app.logAgain([entry]) }
                                .tint(Brand.accent)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", systemImage: "trash", role: .destructive) { app.trash([entry]) }
                        Button("Edit", systemImage: "slider.horizontal.3") { app.sheet = .editEntry(entry) }
                            .tint(.gray)
                    }
            }
            .dropDestination(for: String.self) { ids, _ in
                moveDropped(ids)
            }
            if entries.isEmpty {
                Button {
                    app.sheet = .addFood(day: day, meal: slot.id)
                } label: {
                    Label("Add \(slot.name.lowercased())", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .dropDestination(for: String.self) { ids, _ in
                    moveDropped(ids)
                    return true
                }
            }
        } header: {
            header
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(slot.emoji)
            Text(slot.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
            if !planned.isEmpty {
                Button {
                    app.confirm(planned)
                } label: {
                    Label("Eaten", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .textCase(nil)
                .help("Mark the planned foods of this meal as eaten")
            }
            Spacer()
            if eatenEnergy > 0 {
                Text(Fmt.energy(eatenEnergy, unit: app.energyUnit))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
            Menu {
                Button("Log Food…", systemImage: "magnifyingglass") { app.sheet = .addFood(day: day, meal: slot.id) }
                Button("Quick Calories…", systemImage: "bolt") { app.sheet = .quickCalories(day: day, meal: slot.id) }
                #if os(iOS)
                Button("Scan Barcode…", systemImage: "barcode.viewfinder") { app.sheet = .scanBarcode(day: day, meal: slot.id) }
                #endif
                let meals = recipes.filter { $0.recipeKind == .meal }
                if !meals.isEmpty {
                    Menu("Log a Saved Meal", systemImage: "takeoutbag.and.cup.and.straw") {
                        ForEach(meals) { recipe in
                            Button("\(recipe.symbol) \(recipe.displayName)") { app.logRecipe(recipe, day: day, meal: slot.id) }
                        }
                    }
                }
                Button("Copy from Yesterday", systemImage: "arrow.uturn.down") { copyFromYesterday() }
                if !entries.isEmpty {
                    Divider()
                    Button("Save as Meal…", systemImage: "square.and.arrow.down.on.square") { app.sheet = .saveAsMeal(entries) }
                    Button("Copy to Today", systemImage: "doc.on.doc") { app.copy(entries, to: app.today) }
                        .disabled(day == app.today)
                    Button("Delete All", systemImage: "trash", role: .destructive) { app.trash(entries) }
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Brand.accent)
            } primaryAction: {
                app.sheet = .addFood(day: day, meal: slot.id)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Add to \(slot.name)")
        }
    }

    private func moveDropped(_ ids: [String]) {
        let uuids = Array(Set(ids.compactMap(UUID.init(uuidString:))))
        guard !uuids.isEmpty else { return }
        let descriptor = FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { uuids.contains($0.uuid) })
        let dropped = ((try? app.container.mainContext.fetch(descriptor)) ?? []).filter { $0.meal != slot.id || $0.day != day.rawValue }
        guard !dropped.isEmpty else { return }
        for entry in dropped where entry.day != day.rawValue {
            entry.day = day.rawValue
        }
        app.move(dropped, to: slot.id)
    }

    private func copyFromYesterday() {
        let yesterday = app.store.entries(on: day.adding(days: -1)).filter { $0.meal == slot.id && $0.entryStatus != .skipped }
        guard !yesterday.isEmpty else {
            app.toasts.show("Nothing logged for \(slot.name.lowercased()) yesterday", symbol: "info.circle")
            return
        }
        app.copy(yesterday, to: day)
    }
}

/// One diary entry: category, name, amount, energy and macros at a glance. Planned ones are
/// dimmed with a circle to confirm.
struct EntryRow: View {
    let entry: LogEntry
    let unit: EnergyUnit
    var onConfirm: (() -> Void)?

    var body: some View {
        let values = entry.values
        HStack(spacing: 12) {
            if entry.isPlanned, let onConfirm {
                Button(action: onConfirm) {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(Brand.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Mark as eaten")
            }
            CategoryBadge(category: entry.foodCategory, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.displayName)
                        .lineLimit(1)
                    if !entry.note.isEmpty {
                        Image(systemName: "text.bubble")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    if let amount = entry.amountDescription {
                        Text(amount)
                    }
                    if entry.isPlanned {
                        Text("· planned \(Fmt.time(entry.time))")
                    } else if entry.entryStatus == .skipped {
                        Text("· skipped")
                    }
                    if let tag = entry.tagList.first {
                        Text("· #\(tag)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.energy(values.energy, unit: unit, showUnit: false))
                    .font(.body.monospacedDigit())
                Text("P \(Fmt.number(values.protein)) · C \(Fmt.number(values.carbs)) · F \(Fmt.number(values.fat))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(entry.isEaten ? 1 : 0.55)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Glasses filling up to the goal; tap to add one, hold for other amounts.
struct WaterCard: View {
    let day: DayKey
    let logs: [WaterLog]
    let goal: Double
    let glass: Double

    @Environment(AppModel.self) private var app

    private var total: Double { logs.map(\.amount).reduce(0, +) }
    private var glassCount: Int { max(4, min(14, Int((goal / max(glass, 50)).rounded(.up)))) }
    private var filled: Int { Int((total / max(glass, 50)).rounded(.down)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Water", systemImage: "drop.fill")
                    .font(.headline)
                    .foregroundStyle(NutrientStyle.water)
                Spacer()
                Text("\(Fmt.volume(total)) of \(Fmt.volume(goal))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: total))
            }
            HStack(spacing: 6) {
                ForEach(0..<glassCount, id: \.self) { index in
                    Image(systemName: index < filled ? "waterbottle.fill" : "waterbottle")
                        .font(.title3)
                        .foregroundStyle(index < filled ? NutrientStyle.water : Color.secondary.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            HStack(spacing: 10) {
                Button {
                    app.removeLastWater(on: day)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 36, height: 30)
                }
                .buttonStyle(.bordered)
                .disabled(logs.isEmpty)
                .accessibilityLabel("Remove the last water")
                Menu {
                    ForEach([100.0, 150, 200, 300, 330, 500, 750, 1000], id: \.self) { amount in
                        Button(Fmt.milliliters(amount)) { app.addWater(amount, day: day) }
                    }
                    Button("Other Amount…") { app.sheet = .water(day) }
                } label: {
                    Label("+\(Fmt.milliliters(glass))", systemImage: "drop.fill")
                        .frame(maxWidth: .infinity)
                } primaryAction: {
                    app.addWater(glass, day: day)
                }
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)
                .tint(NutrientStyle.water)
            }
        }
        .padding(16)
        .background(Color.cardBackground, in: .rect(cornerRadius: 22, style: .continuous))
        .sensoryFeedback(.increase, trigger: total)
    }
}

/// "Other amount" of water.
struct WaterAmountView: View {
    let day: DayKey
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = "250"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Amount", text: $text)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text("ml").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Counts towards today's water goal. Coffee, tea and other drinks with calories are better logged as food.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Water")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let amount = NumberText.parse(text), amount > 0 { app.addWater(amount, day: day) }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .sheetFrame(minWidth: 380, minHeight: 240)
    }
}
