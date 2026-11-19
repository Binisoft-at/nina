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
            .onOpenURL { url in app.open(url) }
            .onReceive(NotificationCenter.default.publisher(for: .ninaOpenURL)) { _ in
                // The link a notification asked for: whoever takes it first opens it, so only once.
                if let url = NotificationScheduler.shared.takePendingURL() { app.open(url) }
            }
            .task {
                // A notification button tapped on a cold start can answer before this window listens.
                if let url = NotificationScheduler.shared.takePendingURL() { app.open(url) }
                // The tour opens by itself once after install (and as "What's new" after updates).
                try? await Task.sleep(for: .milliseconds(900))
                app.offerTourIfNeeded()
            }
    }

    @ViewBuilder
    private var navigation: some View {
        #if os(macOS)
        MacRoot()
        #else
        PhoneRoot()
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
            }
            Tab("Foods", systemImage: "carrot", value: AppTab.foods) {
                NavigationStack { FoodsHomeView() }
            }
            Tab("Plan", systemImage: "calendar.badge.clock", value: AppTab.plan) {
                NavigationStack { PlanView() }
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.insights) {
                NavigationStack { ProgressHome() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { GlobalSearchView() }
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

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(selection: $app.sidebar) {
                Section {
                    ForEach([SidebarItem.today, .foods, .recipes, .plan, .insights, .body]) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                Section {
                    Label(SidebarItem.trash.title, systemImage: SidebarItem.trash.symbol).tag(SidebarItem.trash)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MacSidebarSummary()
            }
        } detail: {
            NavigationStack {
                switch app.sidebar ?? .today {
                case .today: TodayView()
                case .foods: FoodLibraryView()
                case .recipes: RecipesView()
                case .plan: PlanView()
                case .insights: InsightsView()
                case .body: BodyPageView()
                case .trash: TrashView()
                }
            }
        }
    }
}

/// Today at a glance under the Mac sidebar.
private struct MacSidebarSummary: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TodaySummaryLine(day: app.today)
            .id(app.today)
            .padding(12)
            .background(.bar)
    }
}
#endif

/// The sheets any screen can open, toasts and undo. Shared by the window and the tour's practice page.
/// While an app sheet is up, the sheet shows the toasts (SheetToasts.swift): once, and on top.
struct AppChrome: ViewModifier {
    @Bindable var app: AppModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $app.sheet) { sheet in
                SheetContent(sheet: sheet)
                    .environment(app)
                    .modelContainer(app.container)
            }
            .toasts(app.sheet == nil ? app.toasts : ToastCenter.silent)
            .undoableChanges(in: app.container.mainContext)
    }
}

/// Editors that own their NavigationStack (and `.sheetFrame`) are returned bare: the food,
/// recipe, entry and weigh-in editors, `MeasureSheet`, `AssessmentSheet`, `CheckInSheet`,
/// `PhaseSheet`, `PhaseReviewSheet`. Screens that are also pushed elsewhere (`GoalsView`,
/// `PlanEditorView`, `SettingsView` …) are wrapped here. Every sheet shows the toasts – also the
/// Undo of the save that opened it (a full set, then body fat).
private struct SheetContent: View {
    let sheet: AppSheet
    @Environment(AppModel.self) private var app

    var body: some View {
        content
            .sheetToasts(app.toasts)
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
            .sheetFrame(minWidth: 560, minHeight: 680)
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
                .sheetFrame(minWidth: 580, minHeight: 700)
        case .planGoal:
            NavigationStack { PlanEditorView(showsDone: true, initialRoute: .longTerm) }
                .sheetFrame(minWidth: 580, minHeight: 700)
        case .water(let day):
            WaterAmountView(day: day)
        case .scanBarcode(let day, let meal):
            BarcodeLookupView(day: day, meal: meal)
        case .dayNutrition(let day):
            NavigationStack { DayNutritionView(day: day) }
                .sheetFrame(minWidth: 560, minHeight: 680)
        case .copyEntries(let entries):
            CopyEntriesView(entries: entries)
        case .goals:
            NavigationStack { GoalsView(showsDone: true) }
                .sheetFrame(minWidth: 580, minHeight: 700)
        case .importData(let kind):
            ImportView(initialKind: kind)
        case .settings:
            NavigationStack { SettingsView() }
                .sheetFrame(minWidth: 580, minHeight: 680)
        case .trash:
            NavigationStack { TrashView() }
                .sheetFrame(minWidth: 520, minHeight: 600)
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

/// Full screen on iPhone/iPad, a large sheet on the Mac.
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
                .frame(minWidth: 760, idealWidth: 900, minHeight: 680, idealHeight: 820)
        }
        #endif
    }
}
