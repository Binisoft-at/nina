import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

/// iPhone/iPad: tab bar (a sidebar on iPad) with today's numbers in the bottom accessory.
/// Mac: split view with a sidebar.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        navigation
            .modifier(AppChrome(app: app))
            .modifier(TourPresenter(app: app))
            .modifier(RootCoachRemindersQuestion(app: app))
            .modifier(RootEvents(app: app))
            .task {
                // A notification button tapped on a cold start can answer before this window listens.
                if let url = NotificationScheduler.shared.takePendingURL() { app.open(url) }
                // The tour opens by itself once after install (and as "What's new" after updates).
                try? await Task.sleep(for: .milliseconds(900))
                app.offerTourIfNeeded()
            }
            .task { await showDemoScreen() }
    }

    @ViewBuilder
    private var navigation: some View {
        #if os(macOS)
        MacRoot()
        #else
        PhoneRoot()
        #endif
    }

    /// Screenshot screens handled here (the others are in `AppModel.applyLaunchOptions`): `search`,
    /// and `toast`, a toast like the one after logging, shown again and again so the screenshot
    /// catches it. `banner` is StorageBanner's; the Mac's `settings` is MacRoot's.
    private func showDemoScreen() async {
        guard app.launch.isDemo else { return }
        switch app.launch.screen {
        case "search":
            app.tab = .search
            app.sidebar = .search
        case "toast":
            for _ in 0..<20 {
                app.toasts.show("Added Banana to Breakfast · 105 kcal", symbol: "checkmark.circle.fill") {}
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
            }
        default:
            break
        }
    }
}

/// Links, files and notifications for the window. Links and files go to this window (macOS
/// opens a new one only when none is open); a reminder clicked on the Mac brings it forward (a
/// sheet or the tour opened from the Settings window does too: SettingsWindowContent). A failed
/// save shows a toast, at most once a minute.
private struct RootEvents: ViewModifier {
    let app: AppModel
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    /// A failing store fails on every save: one toast a minute is enough.
    @State private var saveFailureToasts = NinaToastThrottle()

    /// NinaStore posts this when a save fails (observed by its name; NinaStore declares it).
    static let saveFailed = Notification.Name("at.binisoft.nina.saveFailed")

    func body(content: Content) -> some View {
        content
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .onOpenURL { url in app.open(url) }
            .onReceive(NotificationCenter.default.publisher(for: .ninaOpenURL)) { _ in
                // The link a notification asked for: whoever takes it first opens it, so only once.
                guard let url = NotificationScheduler.shared.takePendingURL() else { return }
                bringWindowForward()
                app.open(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: Self.saveFailed)) { _ in
                guard saveFailureToasts.allows(at: Date()) else { return }
                app.toasts.show("Couldn't save your last change – App Log has details.", symbol: "exclamationmark.triangle.fill")
            }
            #if os(macOS)
            .background {
                NinaWindowReader(role: .main)
                    .frame(width: 0, height: 0)
            }
            #endif
    }

    private func bringWindowForward() {
        #if os(macOS)
        MainWindow.bringForward(openWindow: openWindow)
        #endif
    }
}

#if os(iOS)
private struct PhoneRoot: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            Tab("Today", systemImage: "fork.knife", value: AppTab.today) {
                NavigationStack { TodayView() }
                    .storageBannerOnTop()
            }
            Tab("Foods", systemImage: "carrot", value: AppTab.foods) {
                NavigationStack { FoodsHomeView() }
                    .storageBannerOnTop()
            }
            Tab("Plan", systemImage: "calendar.badge.clock", value: AppTab.plan) {
                NavigationStack { PlanView() }
                    .storageBannerOnTop()
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.insights) {
                NavigationStack { ProgressHome() }
                    .storageBannerOnTop()
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { GlobalSearchView() }
                    .storageBannerOnTop()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .minimizingTabBar()
        .tabViewBottomAccessory {
            TodayAccessory()
        }
    }
}
#endif

#if os(macOS)
private struct MacRoot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    /// The section shown last (UserDefaults, this Mac only), opened again at the next launch.
    static let sectionKey = "nina.mac.sidebar"
    /// Restored once per launch, not each time the window opens again.
    private static var restoredSection = false

    var body: some View {
        NavigationSplitView {
            MacSidebar()
        } detail: {
            NavigationStack {
                detail
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear(perform: restoreSection)
        .onChange(of: app.sidebar) { _, item in rememberSection(item) }
        .task { openSettingsForScreenshot() }
    }

    @ViewBuilder
    private var detail: some View {
        switch app.sidebar ?? .today {
        case .search: GlobalSearchView()
        case .today: TodayView()
        case .foods: FoodLibraryView()
        case .recipes: RecipesView()
        case .plan: PlanView()
        case .insights: InsightsView()
        case .body: BodyPageView()
        case .trash: TrashView()
        }
    }

    /// Not for the tour's practice page or the demo (screenshots pick their own section).
    private var remembersSection: Bool { !app.isSandbox && !app.launch.isDemo }

    private func restoreSection() {
        guard remembersSection, !Self.restoredSection else { return }
        Self.restoredSection = true
        guard let raw = UserDefaults.standard.string(forKey: Self.sectionKey),
              let item = SidebarItem(rawValue: raw) else { return }
        app.sidebar = item
    }

    private func rememberSection(_ item: SidebarItem?) {
        guard remembersSection, let item else { return }
        UserDefaults.standard.set(item.rawValue, forKey: Self.sectionKey)
    }

    /// `-DemoScreen settings`: the Settings window, as Mac users see it (not the iPhone's sheet).
    private func openSettingsForScreenshot() {
        guard app.launch.isDemo, app.launch.screen == "settings" else { return }
        app.sheet = nil
        openSettings()
    }
}

/// The sections, with badges for what's due on the body page and what's in Recently Deleted;
/// storage problems and today at a glance underneath.
private struct MacSidebar: View {
    @Environment(AppModel.self) private var app
    @State private var dueCount = 0
    @State private var trashCount = 0

    private static let sections: [SidebarItem] = [.search, .today, .foods, .recipes, .plan, .insights, .body]

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(Self.sections) { item in
                    row(item)
                }
            }
            Section {
                row(.trash)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                StorageBanner()
                MacSidebarSummary()
            }
        }
        .task(id: app.dataVersion) {
            // Once a burst of saves has settled.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            countBadges()
        }
    }

    /// ⌘-click can't empty it: the section shown stays highlighted.
    private var selection: Binding<SidebarItem?> {
        Binding<SidebarItem?>(
            get: { Optional(app.sidebar ?? .today) },
            set: { (item: SidebarItem?) in
                if let item { app.sidebar = item }
            }
        )
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(badge(for: item))
            .tag(item)
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .body: dueCount
        case .trash: trashCount
        default: 0
        }
    }

    private func countBadges() {
        dueCount = app.settings.plan.isSetUp ? CoachContext.load(app: app, day: app.today).dueItems.count : 0
        let context = app.container.mainContext
        var trashed = 0
        trashed += (try? context.fetchCount(FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { $0.deletedAt != nil }))) ?? 0
        trashed += (try? context.fetchCount(FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.deletedAt != nil }))) ?? 0
        trashed += (try? context.fetchCount(FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.deletedAt != nil }))) ?? 0
        trashed += (try? context.fetchCount(FetchDescriptor<WeightEntry>(predicate: #Predicate<WeightEntry> { $0.deletedAt != nil }))) ?? 0
        trashed += (try? context.fetchCount(FetchDescriptor<BodyMeasurement>(predicate: #Predicate<BodyMeasurement> { $0.deletedAt != nil }))) ?? 0
        trashed += (try? context.fetchCount(FetchDescriptor<ProgressPhoto>(predicate: #Predicate<ProgressPhoto> { $0.deletedAt != nil }))) ?? 0
        trashCount = trashed
    }
}

/// Today at a glance under the Mac sidebar, and how iCloud sync is doing.
private struct MacSidebarSummary: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TodaySummaryLine(day: app.today)
                .id(app.today)
            MacSyncLine()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

/// "Synced 2 min. ago" (Settings → iCloud & Data has the details).
private struct MacSyncLine: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TimelineView(.everyMinute) { _ in
            if let text = syncText {
                Label(text, systemImage: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var syncText: String? {
        NinaSyncLine.text(app.sync.state) { date in
            date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        }
    }
}
#endif

/// The sheets any screen can open, toasts and undo. Shared by the window and the tour's practice page.
/// While an app sheet is up, the sheet shows the toasts (SheetToasts.swift): once, and on top. On
/// the Mac the window's toasts stay silent while the Settings window is key (it shows them then).
struct AppChrome: ViewModifier {
    @Bindable var app: AppModel
    /// How far the window's toasts sit above the bottom: on iPhone above the tab bar and Today's
    /// bar with the calories left.
    var toastInset: CGFloat = NinaToastInset.window

    func body(content: Content) -> some View {
        content
            .sheet(item: $app.sheet) { sheet in
                SheetContent(sheet: sheet)
                    .environment(app)
                    .modelContainer(app.container)
            }
            .toasts(windowToasts, bottomPadding: toastInset)
            .undoableChanges(in: app.container.mainContext)
    }

    private var windowToasts: ToastCenter {
        guard app.sheet == nil else { return ToastCenter.silent }
        #if os(macOS)
        if MacWindowState.shared.settingsIsKey { return ToastCenter.silent }
        #endif
        return app.toasts
    }
}

/// Editors that own their NavigationStack (and `.sheetFrame`) are returned bare: the food,
/// recipe, entry and weigh-in editors, `MeasureSheet`, `AssessmentSheet`, `CheckInSheet`,
/// `PhaseSheet`, `PhaseReviewSheet`. Screens that are also pushed elsewhere (`GoalsView`,
/// `PlanEditorView`, `SettingsView` …) are wrapped here. Every sheet shows the toasts – also the
/// Undo of the save that opened it (a full set, then body fat). Mac sheets stay within a 13-inch
/// screen: the kit's sheetFrame asks for 120 pt more than the minimum height.
private struct SheetContent: View {
    let sheet: AppSheet
    @Environment(AppModel.self) private var app

    var body: some View {
        content
            .sheetToasts(sheetToasts)
    }

    /// Silent while the Mac's Settings window is key (it shows them then).
    private var sheetToasts: ToastCenter {
        #if os(macOS)
        if MacWindowState.shared.settingsIsKey { return ToastCenter.silent }
        #endif
        return app.toasts
    }

    @ViewBuilder
    private var content: some View {
        switch sheet {
        case .create:
            NinaCreateSheet()
        case .addFood(let day, let meal):
            FoodSearchView(mode: .log(day: day, meal: meal))
        case .quickCalories(let day, let meal):
            QuickCaloriesView(day: day, meal: meal)
        case .editEntry(let entry):
            EntryEditor(entry: entry)
        case .food(let record):
            NavigationStack {
                FoodDetailView(record: record, mode: .log(day: app.selectedDay, meal: nil), showsDone: true)
            }
            .sheetFrame(minWidth: 560, minHeight: 560)
        case .newFood(let draft):
            FoodEditor(food: nil, draft: draft)
        case .editFood(let food):
            FoodEditor(food: food, draft: nil)
        case .recipe(let recipe, let kind):
            RecipeEditor(recipe: recipe, kind: kind)
        case .saveAsMeal(let entries):
            SaveAsMealView(entries: entries)
        case .planRule(let rule, let recipe):
            PlanRuleEditor(rule: rule, recipe: recipe)
        case .weight(let entry):
            WeighInSheet(entry: entry)
        case .measure(let mode, let record):
            MeasureSheet(mode: mode, record: record)
        case .assessment(let record):
            AssessmentSheet(record: record)
        case .checkIn(let week):
            CheckInSheet(week: week)
        case .phase(let id):
            PhaseSheet(phaseID: id)
        case .phaseReview(let id):
            PhaseReviewSheet(phaseID: id)
        case .plan:
            NavigationStack { PlanEditorView(showsDone: true) }
                .sheetFrame(minWidth: 580, minHeight: 560)
        case .planGoal:
            NavigationStack { PlanEditorView(showsDone: true, initialRoute: .longTerm) }
                .sheetFrame(minWidth: 580, minHeight: 560)
        case .photos(let sheet):
            BodyPhotoSheetContent(sheet: sheet)
        case .water(let day):
            WaterAmountView(day: day)
        case .scanBarcode(let day, let meal):
            BarcodeLookupView(day: day, meal: meal)
        case .dayNutrition(let day):
            NavigationStack { DayNutritionView(day: day) }
                .sheetFrame(minWidth: 560, minHeight: 540)
        case .copyEntries(let entries):
            CopyEntriesView(entries: entries)
        case .goals:
            NavigationStack { GoalsView(showsDone: true) }
                .sheetFrame(minWidth: 580, minHeight: 560)
        case .importData(let kind):
            ImportView(initialKind: kind)
        case .settings:
            NavigationStack { SettingsView() }
                .sheetFrame(minWidth: 580, minHeight: 560)
        case .trash:
            NavigationStack { TrashView() }
                .sheetFrame(minWidth: 520, minHeight: 520)
        }
    }
}

/// iPhone: "Turn on coach reminders?" once a plan is set up (`AppModel.offerCoachRemindersIfNeeded`),
/// asked again for a look when a sheet closes (a plan may just have been set up there).
private struct RootCoachRemindersQuestion: ViewModifier {
    @Bindable var app: AppModel

    func body(content: Content) -> some View {
        content
            .coachRemindersPrompt(isPresented: $app.askCoachReminders)
            .onChange(of: app.sheet == nil) { _, closed in
                if closed { app.offerCoachRemindersIfNeeded() }
            }
    }
}

/// Full screen on iPhone/iPad, a large sheet on the Mac (within a 1024 × 768 screen).
struct TourPresenter: ViewModifier {
    @Bindable var app: AppModel

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: $app.tour) { request in
            TourView(steps: request.steps, host: app) { app.finishTour() }
                .appearanceFromSettings()
        }
        #else
        content.sheet(item: $app.tour) { request in
            TourView(steps: request.steps, host: app) { app.finishTour() }
                .frame(minWidth: 720, idealWidth: 860, minHeight: 560, idealHeight: 660)
        }
        #endif
    }
}
