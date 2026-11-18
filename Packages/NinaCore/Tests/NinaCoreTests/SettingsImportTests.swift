import Foundation
import Testing
@testable import NinaCore

struct SettingsImportTests {
    static let file = """
    setting,value
    sex,female
    birth_year,1991
    height_cm,171
    weight_kg,67.3
    activity,moderate
    goal,lose
    rate_kg_per_week,0.5
    target_weight_kg,62
    macro_split,high_protein
    training_days,mon;wed;fri
    training_extra_kcal,250
    meals,Frühstück 07:00 🥐;Mittagessen 12:30 🥗;Jause 10:00 🥪;Abendessen 19:00 🍝
    food_names,german
    water_glass_ml,300
    add_burned_calories,half
    focus_nutrients,protein;fiber;salt
    not_supported,I'm lactose intolerant
    favourite_color,green
    """

    @Test func readsEverySetting() {
        let draft = SettingsCSV.parse(Self.file)
        #expect(draft.sex == .female)
        #expect(draft.birthYear == 1991)
        #expect(draft.heightCm == 171)
        #expect(draft.weightKg == 67.3)
        #expect(draft.activity == .moderate)
        #expect(draft.goal == .lose)
        #expect(draft.macroSplit == .highProtein)
        #expect(draft.trainingDays == Weekdays([1, 3, 5]))
        #expect(draft.trainingExtra == 250)
        #expect(draft.language == .german)
        #expect(draft.waterGlass == 300)
        #expect(draft.activityBonusShare == 0.5)
        #expect(draft.focus == [.protein, .fiber, .sodium])
        #expect(draft.wishes == ["I'm lactose intolerant"])
        #expect(draft.skipped.count == 1)
        let meals = draft.meals ?? []
        #expect(meals.map(\.id) == ["breakfast", "snack", "lunch", "dinner"])
        #expect(meals.first?.minutes == 7 * 60)
        #expect(meals.first?.name == "Frühstück")
        #expect(meals[1].emoji == "🥪")
        #expect(meals[1].name == "Jause")
        let both = SettingsCSV.parseMeals("Jause 10:00;Snack 16:00;Breakfast 7am")
        #expect(both.map(\.id) == ["breakfast", "snack", "meal-snack"])
        #expect(both.first?.minutes == 7 * 60)
    }

    @Test func bodyDataRecalculatesTheGoal() {
        let draft = SettingsCSV.parse(Self.file)
        let result = SettingsCSV.apply(draft, to: SettingsState(), year: 2026)
        let body = BodyProfile(sex: .female, age: 35, heightCm: 171, weightKg: 67.3, activity: .moderate, goal: .lose, ratePerWeek: 0.5)
        let expected = GoalCalculator.plan(body, split: .highProtein).targets
        #expect(result.state.targets == expected)
        #expect(result.state.trainingTargets?.energy == expected.energy + 250)
        #expect(result.newWeight == 67.3)
        #expect(result.state.meals.contains { $0.id == "snack" }) // the standard meals stay
        #expect(result.changes.contains { $0.title == "Calories" })
        #expect(result.changes.first?.title == "Weight (logged today)")
    }

    @Test func fixedNumbersWin() {
        let text = "setting,value\ncalories,1800\nprotein_g,150\nsalt_max_g,5\nwater,2.5\n"
        let start = SettingsState(targets: DailyTargets(energy: 2000, protein: 100, carbs: 250, fat: 70))
        let result = SettingsCSV.apply(SettingsCSV.parse(text), to: start, year: 2026)
        #expect(result.state.targets.energy == 1800)
        #expect(result.state.targets.protein == 150)
        #expect(result.state.targets.carbs == 225) // scaled with the calories
        #expect(result.state.targets.sodiumMax == 2000)
        #expect(result.state.targets.water == 2500)
        #expect(result.newWeight == nil)
    }

    @Test func percentSplitAndAge() {
        let text = "Setting;Value\nage;30\nmacro_split;30/40/30\ncalories;2000\ntraining_days;none\n"
        let start = SettingsState(trainingTargets: DailyTargets.standard.scaled(toEnergy: 2300), trainingDays: Weekdays([2, 4]))
        let result = SettingsCSV.apply(SettingsCSV.parse(text), to: start, year: 2026)
        #expect(result.state.birthYear == 1996)
        #expect(result.state.targets.protein == 150)
        #expect(result.state.targets.carbs == 200)
        #expect(result.state.targets.fat == 67)
        #expect(result.state.trainingTargets == nil)
        #expect(result.notes.isEmpty)
    }

    @Test func missingBodyDataIsExplained() {
        let result = SettingsCSV.apply(SettingsCSV.parse("setting,value\ngoal,lose\n"), to: SettingsState(), year: 2026)
        #expect(result.state.goal == .lose)
        #expect(result.notes.count == 1)
        #expect(result.state.targets == DailyTargets.standard)
    }

    @Test func badValuesAreSkippedWithAReason() {
        let draft = SettingsCSV.parse("setting,value\nheight_cm,tall\nsex,robot\ncalories,99999\nheight,1.80\n")
        #expect(draft.skipped.count == 3)
        #expect(draft.heightCm == 180)
    }

    @Test func exportReadsBack() {
        var state = SettingsState(sex: .male, birthYear: 1988, heightCm: 182, weightKg: 80, activity: .veryActive, goal: .gain,
                                  ratePerWeek: 0.25, targetWeight: 84, macroSplit: .highProtein,
                                  targets: DailyTargets(energy: 2900, protein: 218, carbs: 290, fat: 97, fiber: 41, sugarMax: 72,
                                                        saturatedFatMax: 32, sodiumMax: 2000, water: 2500),
                                  trainingDays: Weekdays([1, 4]), language: .german, energyUnit: .kJ, dayStartHour: 3,
                                  waterGlass: 330, activityBonusShare: 1, focus: [.protein, .sugar])
        state.trainingTargets = SettingsState.training(state.targets, extra: 400)
        let text = SettingsCSV.export(state)
        let result = SettingsCSV.apply(SettingsCSV.parse(text), to: state, year: 2026)
        // Fixed numbers in the export win over the recalculation, so nothing changes.
        #expect(result.changes.isEmpty, "\(result.changes)")
        #expect(SettingsCSV.parse(text).skipped.isEmpty)
    }

    @Test func detectsAndSplitsWhatAnAIWrote() {
        let answer = """
        Here you go:
        ```csv
        setting,value
        goal,lose
        ```
        ```csv
        id,name,name_de,brand,category,tags,unit,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,portions,barcode,favorite,notes
        1,Protein bar,,Brand,snacks,,g,380,30,40,12,,,,,bar=60,,,
        ```
        ```csv
        recipe,kind,servings,total_weight_g,ingredient,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,notes
        Usual breakfast,meal,,,Oats,60,g,60,,,,,,,,,
        ```
        """
        let parts = ImportBundle.parts(answer)
        #expect(parts.map(\.kind) == [.settings, .foods, .recipes])
        let plain = "setting,value\ngoal,gain\n\nid,name,kcal,protein,carbs,fat\n1,Bar,380,30,40,12\n"
        #expect(ImportBundle.parts(plain).map(\.kind) == [.settings, .foods])
        #expect(ImportKind.detect("Setting;Value\ngoal;lose") == .settings)
    }

    @Test func promptsListEverySetting() {
        let prompt = SettingsCSV.prompt(appName: "Nina", current: SettingsCSV.export(SettingsState()))
        for key in SettingsCSV.keys { #expect(prompt.contains("| \(key.name) |")) }
        let setup = SetupPrompt.text(appName: "Nina", currentSettings: "setting,value\ngoal,maintain\n", existingTags: ["breakfast"])
        #expect(setup.contains("setting,value"))
        #expect(setup.contains(FoodCSV.prompt(appName: "Nina").header))
        #expect(setup.contains("Tags: breakfast"))
    }
}
