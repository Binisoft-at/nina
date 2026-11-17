import SwiftUI
import SwiftData
import BinisoftKit
import NinaCore

enum AppTab: Hashable {
    case today, foods, plan, insights, search
}

/// iPhone: the Foods tab shows foods or meals & recipes.
enum FoodsPage: String, CaseIterable, Identifiable {
    case foods, recipes
    var id: String { rawValue }
    var title: String { self == .foods ? "Foods" : "Meals & Recipes" }
}

/// Mac (and iPad sidebar) sections.
enum SidebarItem: Hashable, CaseIterable, Identifiable {
    case today, foods, recipes, plan, insights, body, trash

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Diary"
        case .foods: "Foods"
        case .recipes: "Meals & Recipes"
        case .plan: "Plan"
        case .insights: "Insights"
        case .body: "Weight"
        case .trash: "Recently Deleted"
        }
    }

    var symbol: String {
        switch self {
        case .today: "fork.knife"
        case .foods: "carrot"
        case .recipes: "frying.pan"
        case .plan: "calendar.badge.clock"
        case .insights: "chart.bar.xaxis"
        case .body: "scalemass"
        case .trash: "trash"
        }
    }
}

/// How the food search was opened: to log on a day, or to pick an ingredient for a meal or recipe.
enum FoodPickMode {
    case log(day: DayKey, meal: String?)
    case pick((RecipeLine) -> Void)

    var isLogging: Bool {
        if case .log = self { return true }
        return false
    }
}

/// Every sheet the app can show. One place, so any screen (and the tour) can open any sheet.
enum AppSheet: Identifiable {
    case create
    case addFood(day: DayKey, meal: String?)
    case quickCalories(day: DayKey, meal: String?)
    case editEntry(LogEntry)
    case food(FoodRecord)
    case newFood(FoodDraft?)
    case editFood(Food)
    case recipe(Recipe?, kind: RecipeKind)
    case saveAsMeal([LogEntry])
    case planRule(PlanRule?, recipe: Recipe?)
    case weight(WeightEntry?)
    case water(DayKey)
    case scanBarcode(day: DayKey, meal: String?)
    case dayNutrition(DayKey)
    case copyEntries([LogEntry])
    case goals
    case importData(ImportKind?)
    case settings
    case trash

    var id: String {
        switch self {
        case .create: "create"
        case .addFood(let day, let meal): "add-\(day)-\(meal ?? "")"
        case .quickCalories(let day, _): "quick-\(day)"
        case .editEntry(let entry): "entry-" + entry.uuid.uuidString
        case .food(let record): "food-" + record.ref.rawValue
        case .newFood: "new-food"
        case .editFood(let food): "edit-food-" + food.uuid.uuidString
        case .recipe(let recipe, let kind): "recipe-\(recipe?.uuid.uuidString ?? "new")-\(kind.rawValue)"
        case .saveAsMeal: "save-as-meal"
        case .planRule(let rule, _): "plan-" + (rule?.uuid.uuidString ?? "new")
        case .weight(let entry): "weight-" + (entry?.uuid.uuidString ?? "new")
        case .water(let day): "water-\(day)"
        case .scanBarcode: "scan"
        case .dayNutrition(let day): "nutrition-\(day)"
        case .copyEntries: "copy-entries"
        case .goals: "goals"
        case .importData: "import"
        case .settings: "settings"
        case .trash: "trash"
        }
    }
}

struct TourRequest: Identifiable {
    let id = UUID()
    let steps: [TourStep<NinaTourSnapshot>]
}
