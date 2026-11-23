import SwiftUI
import SwiftData
import TipKit
import UniformTypeIdentifiers
import BinisoftKit
import NinaCore

/// The diary of the selected day. Rebuilt per day so its queries only load that day.
struct TodayView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        DayView(day: app.selectedDay)
            .id(app.selectedDay)
    }
}

struct DayView: View {
    let day: DayKey

    @Environment(AppModel.self) private var app
    @Query private var entries: [LogEntry]
    @Query private var water: [WaterLog]
    @State private var selection = Set<UUID>()
    @State private var showCalendar = false
    @State private var pickedDate = Date()
    /// The coach parts of the day (chip, checks strip, card, week average, protein rule).
    @State private var coach = TodayCoachState.empty
    /// Ticks every few minutes so time-bound coach parts (the weigh-in until the morning cutoff,
    /// the check-in card from it) update without a data change.
    @State private var clock = 0
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #else
    /// The diary's width, so a wide Mac window keeps it readable (`macSideMargin`).
    @State private var listWidth: CGFloat = 0
    #endif

    init(day: DayKey) {
        self.day = day
        let key = day.rawValue
        _entries = Query(filter: #Predicate<LogEntry> { $0.day == key && $0.deletedAt == nil },
                         sort: [SortDescriptor(\LogEntry.time), SortDescriptor(\LogEntry.sortOrder)])
        _water = Query(filter: #Predicate<WaterLog> { $0.day == key && $0.deletedAt == nil }, sort: \WaterLog.time)
    }

    private var settings: NinaSettings { app.settings }

    private var totals: DayTotals {
        DayTotals(day: day, entries: entries.map(\.facts), water: water.map(\.amount).reduce(0, +))
    }

    private var progress: DayProgress {
        let bonus = day == app.today ? app.health.activeEnergyToday * settings.activityBonusShare : 0
        return DayProgress(totals: totals, targets: settings.targets(for: day), activityBonus: bonus)
    }

    /// The person's meals, plus any meal id used by an entry but no longer configured.
    private var slots: [MealSlot] {
        var result = settings.meals
        for id in Set(entries.map(\.meal)) where !result.contains(where: { $0.id == id }) {
            result.append(settings.meal(id))
        }
        return result
    }

    private var selectedEntries: [LogEntry] {
        entries.filter { selection.contains($0.uuid) }
    }

    /// Protein by meal for the meal-header pills; nil without a protein rule.
    private var proteinDay: ProteinMeals.Day? {
        guard let rule = coach.proteinRule else { return nil }
        return ProteinMeals.day(day, entries: entries.map(\.facts), rule: rule)
    }

    private var coachKey: String { "\(app.dataVersion)-\(day.rawValue)-\(clock)" }

    /// The day-type chip, straight from the settings (the same chip as the board's): it is there
    /// on the first frame of a day and always matches the targets on the card.
    private var chip: CoachBoard.Chip? {
        settings.todayCoachChip(for: day, today: app.today)
    }

    var body: some View {
        let protein = proteinDay
        List(selection: $selection) {
            summarySection(protein: protein)

            coachCardSection

            if entries.isEmpty, day == app.today {
                Section {
                    TipView(NinaTips.TypeItTip())
                        .listRowBackground(Color.clear)
                }
            }

            ForEach(slots) { slot in
                MealSection(slot: slot, day: day, entries: entries.filter { $0.meal == slot.id },
                            protein: protein?.meal(slot.id))
            }

            Section {
                WaterCard(day: day, logs: water, goal: settings.targets(for: day).water, glass: settings.waterGlass)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                Button {
                    app.sheet = .dayNutrition(day)
                } label: {
                    Label("All nutrients of the day", systemImage: "list.bullet.rectangle")
                }
                if !entries.isEmpty {
                    Menu {
                        dayActions
                    } label: {
                        Label("Copy or plan this day", systemImage: "doc.on.doc")
                    }
                }
                if !coach.dayChecks.isEmpty {
                    Menu {
                        pastChecks
                    } label: {
                        Label("Checks of this day", systemImage: "checklist")
                    }
                }
            }

            if coach.offersIncompleteLog, !entries.isEmpty || coach.isIncompleteLog {
                incompleteLogSection
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        #else
        .listStyle(.inset)
        .contentMargins(.horizontal, macSideMargin, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            listWidth = width
        }
        .onDeleteCommand(perform: deleteSelection)
        .onCopyCommand(perform: copySelection)
        .onPasteCommand(of: [UTType.plainText], perform: pasteEntries)
        #endif
        .contextMenu(forSelectionType: UUID.self) { ids in
            selectionMenu(ids)
        } primaryAction: { ids in
            guard ids.count == 1, let id = ids.first, let entry = entries.first(where: { $0.uuid == id }) else { return }
            app.sheet = .editEntry(entry)
        }
        .navigationTitle(Fmt.dayTitle(day, today: app.today))
        .toolbar { toolbar }
        .onChange(of: entries.map(\.uuid)) { _, ids in
            selection = selection.intersection(ids)
        }
        .task(id: coachKey) {
            coach = TodayCoachState.load(app: app, day: day)
        }
        .task {
            await tickClock()
        }
    }

    // MARK: Summary and coach

    /// The week strip, then today's phase line, the summary card (day-type chip, week average,
    /// protein meals) and the checks strip under it.
    private func summarySection(protein: ProteinMeals.Day?) -> some View {
        Section {
            WeekStrip(selected: day)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            VStack(alignment: .leading, spacing: 0) {
                if let line = coach.phaseLine {
                    TodayCoachPhaseLineView(line: line)
                        .padding(.bottom, 8)
                }
                summaryCard(protein: protein)
                #if os(macOS)
                if day == app.today, settings.activityBonusShare > 0 {
                    activityBonusNote
                }
                #endif
                TodayCoachStrip(day: day, input: coach.stripInput)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
    }

    #if os(macOS)
    /// The activity bonus comes from Apple Health, which only the iPhone reads: the Mac's budget
    /// leaves it out.
    private var activityBonusNote: some View {
        Text("Activity bonus shows on iPhone.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .padding(.horizontal, 18)
    }

    /// Side margins that keep the diary about 840 pt wide and centred in a wide window; nil keeps
    /// the list's own margins.
    private var macSideMargin: CGFloat? {
        listWidth >= 880 ? (listWidth - 840) / 2 : nil
    }

    /// ⌫ and Edit → Delete: the selected entries go to Recently Deleted (with Undo).
    private func deleteSelection() {
        let chosen = selectedEntries
        guard !chosen.isEmpty else { return }
        app.trash(chosen)
        selection = []
    }

    /// ⌘C: the selected entries as readable lines; ⌘V on any day copies them there.
    private func copySelection() -> [NSItemProvider] {
        TodayEntryClipboard.providers(for: selectedEntries, unit: app.energyUnit)
    }

    /// ⌘V: copies the entries Nina put on the pasteboard to this day (Undo in the toast).
    private func pasteEntries(_ providers: [NSItemProvider]) {
        app.todayPaste(TodayEntryClipboard.pastedIDs(), on: day)
    }
    #endif

    private func summaryCard(protein: ProteinMeals.Day?) -> some View {
        let unit = settings.energyUnit
        // Protein meals count what was eaten, so a day still ahead shows none.
        let proteinMeals: String? = day <= app.today ? TodayCoachState.proteinMealsText(protein) : nil
        return DaySummaryCard(day: day, progress: progress, focus: settings.focus, unit: unit,
                              isTrainingDay: settings.isTrainingDay(day), chip: chip,
                              weekAverage: coach.weekAverageText(unit: unit), proteinMeals: proteinMeals)
            .simultaneousGesture(daySwipe)
    }

    /// "Log Is Incomplete": the day stays out of check-ins and adherence (with a plan, up to today,
    /// once something is logged).
    private var incompleteLogSection: some View {
        Section {
            Toggle(isOn: incompleteLog) {
                Label("Log Is Incomplete", systemImage: "exclamationmark.circle")
            }
        } footer: {
            Text("Days with an incomplete log are left out of your weekly check-in.")
        }
    }

    private var incompleteLog: Binding<Bool> {
        Binding<Bool>(
            get: { coach.isIncompleteLog },
            set: { (isOn: Bool) in
                // Shown at once; the reload after the save confirms it.
                coach.isIncompleteLog = isOn
                app.setIncompleteLog(isOn, on: day)
            }
        )
    }

    /// At most one coach card above the meals (only on today).
    @ViewBuilder
    private var coachCardSection: some View {
        if let card = coach.board.card {
            Section {
                TodayCoachCard(card: card, day: day, targets: coach.cardTargets)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listSectionSeparator(.hidden)
        }
    }

    /// Bumps `clock` every 5 minutes while the day is shown.
    private func tickClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { return }
            clock += 1
        }
    }

    // MARK: Gestures

    /// Swipe the summary card left/right for the next/previous day.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > 70, abs(horizontal) > abs(value.translation.height) * 1.5 else { return }
                withAnimation(.snappy) {
                    app.selectedDay = day.adding(days: horizontal < 0 ? 1 : -1)
                }
            }
    }

    // MARK: Menus

    @ViewBuilder
    private func selectionMenu(_ ids: Set<UUID>) -> some View {
        let chosen = entries.filter { ids.contains($0.uuid) }
        if !chosen.isEmpty {
            EntryActions(entries: chosen, day: day)
        }
    }

    @ViewBuilder
    private var dayActions: some View {
        Button("Copy to Today", systemImage: "doc.on.doc") { app.copy(entries.filter(\.isEaten), to: app.today) }
            .disabled(day == app.today)
        Button("Plan Tomorrow Like This", systemImage: "calendar.badge.plus") {
            app.copy(entries.filter { $0.entryStatus != .skipped }, to: app.today.adding(days: 1), status: .planned)
        }
        Button("Copy to Another Day…", systemImage: "calendar") { app.todayOpenDaySheet(entries, move: false) }
        Button("Save Day as Meal…", systemImage: "square.and.arrow.down.on.square") { app.sheet = .saveAsMeal(entries) }
    }

    /// A past day's daily checks: a tap marks one done (or open again), with Undo.
    @ViewBuilder
    private var pastChecks: some View {
        ForEach(coach.dayChecks) { check in
            Button {
                _ = app.toggleCheck(check.id, on: day)
            } label: {
                Label(check.title, systemImage: check.symbol)
            }
        }
    }

    private var logFoodButton: some View {
        Button {
            app.sheet = .addFood(day: day, meal: nil)
        } label: {
            Label("Log Food", systemImage: "plus")
        }
        .popoverTip(NinaTips.LogTip())
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(iOS)
        // While selecting, a visible Done takes the + button's place.
        if editMode.isEditing {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { withAnimation { editMode = .inactive; selection = [] } }
            }
        } else {
            ToolbarItem(placement: .primaryAction) { logFoodButton }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                pickedDate = day.date()
                showCalendar = true
            } label: {
                Label("Choose Day", systemImage: "calendar")
            }
            .popover(isPresented: $showCalendar) {
                calendarPicker
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                if editMode.isEditing {
                    Button("Done Selecting", systemImage: "checkmark") { withAnimation { editMode = .inactive; selection = [] } }
                } else {
                    Button("Select Entries", systemImage: "checkmark.circle") { withAnimation { editMode = .active } }
                }
                Button("Create…", systemImage: "plus.square.on.square") { app.sheet = .create }
                Button("Nutrients of the Day", systemImage: "list.bullet.rectangle") { app.sheet = .dayNutrition(day) }
                Divider()
                Button("Goals & Plan", systemImage: "target") { app.sheet = .goals }
                if !app.isSandbox {
                    Button("\(AppInfo.name) Tour", systemImage: "graduationcap") { app.startTour() }
                }
                Button("Settings", systemImage: "gear") { app.sheet = .settings }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
        if editMode.isEditing, !selection.isEmpty {
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    EntryActions(entries: selectedEntries, day: day)
                } label: {
                    Label("\(selection.count) Selected", systemImage: "checklist")
                }
            }
        }
        #else
        ToolbarItem(placement: .primaryAction) { logFoodButton }
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 2) {
                Button { app.selectedDay = day.adding(days: -1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous day (⌘[)")
                Button("Today") { app.selectedDay = app.today }
                    .disabled(day == app.today)
                Button { app.selectedDay = day.adding(days: 1) } label: { Image(systemName: "chevron.right") }
                    .help("Next day (⌘])")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                pickedDate = day.date()
                showCalendar = true
            } label: {
                Label("Choose Day", systemImage: "calendar")
            }
            .popover(isPresented: $showCalendar) { calendarPicker }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                app.sheet = .create
            } label: {
                Label("Create", systemImage: "square.grid.2x2")
            }
            .help("Create (⇧⌘N)")
        }
        #endif
    }

    private var calendarPicker: some View {
        VStack(spacing: 12) {
            DatePicker("Day", selection: $pickedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Button("Today") {
                    app.selectedDay = app.today
                    showCalendar = false
                }
                Spacer()
                Button("Show") {
                    app.selectedDay = DayKey(date: pickedDate)
                    showCalendar = false
                }
                .primaryActionStyle()
            }
        }
        .padding()
        .frame(minWidth: 320)
        .presentationCompactAdaptation(.popover)
    }
}

/// Everything you can do with one or more entries (context menu, selection menu).
struct EntryActions: View {
    let entries: [LogEntry]
    let day: DayKey

    @Environment(AppModel.self) private var app

    var body: some View {
        let planned = entries.filter { !$0.isEaten }
        if entries.count == 1, let entry = entries.first {
            Button("Edit…", systemImage: "pencil") { app.sheet = .editEntry(entry) }
        }
        if !planned.isEmpty {
            Button("Mark as Eaten", systemImage: "checkmark.circle") { app.confirm(planned) }
        }
        Button("Log Again Now", systemImage: "arrow.clockwise") { app.logAgain(entries) }
        Menu("Move to Meal", systemImage: "arrow.left.arrow.right") {
            ForEach(app.settings.meals) { slot in
                Button("\(slot.emoji) \(slot.name)") { app.move(entries, to: slot.id) }
            }
        }
        Button("Move to Day…", systemImage: "calendar") { app.todayOpenDaySheet(entries, move: true) }
        Menu("Copy to", systemImage: "doc.on.doc") {
            Button("Today") { app.copy(entries, to: app.today) }
            Button("Tomorrow (planned)") { app.copy(entries, to: app.today.adding(days: 1), status: .planned) }
            Button("Another Day…") { app.todayOpenDaySheet(entries, move: false) }
        }
        Button("Save as Meal…", systemImage: "square.and.arrow.down.on.square") { app.sheet = .saveAsMeal(entries) }
        if entries.count == 1, let entry = entries.first, let record = app.library.record(entry.ref) {
            Button(record.isFavorite ? "Remove from Favorites" : "Add Food to Favorites", systemImage: record.isFavorite ? "star.slash" : "star") {
                app.toggleFavorite(record)
            }
            Button("Food Details", systemImage: "info.circle") { app.sheet = .food(record) }
        }
        if entries.contains(where: \.isEaten) {
            Button("Mark as Planned", systemImage: "circle.dashed") { app.setStatus(entries, .planned) }
        }
        Divider()
        Button(entries.count == 1 ? "Delete" : "Delete \(entries.count) Entries", systemImage: "trash", role: .destructive) {
            app.trash(entries)
        }
    }
}
