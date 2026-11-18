import Foundation
import Testing
import BinisoftKitCore
@testable import NinaCore

@Suite("Food CSV")
struct FoodCSVTests {
    let file = """
    id,name,name_de,brand,category,tags,unit,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,portions,barcode,favorite,notes
    1,Greek yogurt 2%,Griechisches Joghurt,Fage,dairy,breakfast|high-protein,g,73,10,3.6,2,,3.6,1.3,0.1,pot=170,5201054017197,yes,
    2,Oat drink,Haferdrink,Oatly,beverages,,ml,59,1,6.6,3,0.8,3.4,0.3,0.1,glass=250,,,
    3,No energy,,,,,,,5,5,5,,,,,,,,
    4,,,,,,,100,1,1,1,,,,,,,,
    """

    @Test func parsesRowsAndSkipsBadOnes() throws {
        let parsed = FoodCSV.parse(file)
        #expect(parsed.rows.count == 2)
        let yogurt = try #require(parsed.rows.first?.draft)
        #expect(yogurt.name == "Greek yogurt 2%")
        #expect(yogurt.category == .dairy)
        #expect(yogurt.tags == ["breakfast", "high-protein"])
        #expect(yogurt.isFavorite)
        #expect(yogurt.servings == [Serving(en: "pot", amount: 170)])
        #expect(abs((yogurt.nutrients[.sodium] ?? 0) - 40) < 0.001)
        #expect(parsed.rows[1].draft.unit == .milliliter)
        #expect(parsed.skipped.count == 2)
    }

    @Test func exportReimportsWithoutChanges() {
        let parsed = FoodCSV.parse(file)
        let exported = FoodCSV.export(parsed.rows.map { ($0.key, $0.draft) })
        var existing: [String: FoodDraft] = [:]
        for row in parsed.rows {
            for key in ImportColumns.lookupKeys(forKey: row.key) { existing[key] = row.draft }
        }
        let plan = FoodCSV.plan(exported, existing: existing)
        #expect(plan.unchanged == 2)
        #expect(!plan.hasChanges)
    }

    @Test func understandsGermanHeadersAndCommas() throws {
        let german = """
        Lebensmittel;Marke;Brennwert (kcal);Eiweiß;Kohlenhydrate;davon Zucker;Fett;Salz
        Topfen mager;Clever;"70";12;4,0;4;0,2;0,1
        """
        let parsed = FoodCSV.parse(german)
        let topfen = try #require(parsed.rows.first?.draft)
        #expect(topfen.name == "Topfen mager")
        #expect(topfen.nutrients[.energy] == 70)
        #expect(topfen.nutrients[.carbs] == 4)
        #expect(topfen.nutrients[.fat] == 0.2)
        #expect(ImportKind.detect(german) == .foods)
    }

    @Test func kilojoulesBecomeKilocalories() throws {
        let parsed = FoodCSV.parse("name,kj,protein,carbs,fat\nBread,1046,8,48,2")
        let bread = try #require(parsed.rows.first?.draft)
        #expect(abs(bread.nutrients.energy - 250) < 0.1)
    }

    @Test func promptListsTheColumns() {
        let prompt = FoodCSV.prompt(appName: "Nina", existingTags: ["breakfast"]).text
        #expect(prompt.contains(FoodCSV.header.joined(separator: ",")))
        #expect(prompt.contains("breakfast"))
        #expect(prompt.contains("per 100 g"))
    }
}

@Suite("Diary CSV")
struct DiaryCSVTests {
    let file = """
    id,date,time,meal,food,brand,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,note,status
    1,2026-11-12,07:30,breakfast,Oats,,60,g,,233,8.1,40,4.1,6,0.6,0.7,0,,
    2,12.11.2026,12:15,Mittagessen,Schnitzel,,1,piece,180,,,,,,,,,,
    3,2026-11-12,,dinner,Pasta,,1,plate,,650,22,95,18,,,,,,planned
    4,someday,,,Cake,,,,,300,,,,,,,,,
    """

    @Test func parsesDatesUnitsAndLookups() throws {
        let parsed = DiaryCSV.parse(file)
        #expect(parsed.rows.count == 3)
        let oats = try #require(parsed.rows.first?.draft)
        #expect(oats.day.rawValue == "2026-11-12")
        #expect(oats.minutes == 450)
        #expect(oats.amount == 60)
        #expect(!oats.needsLookup)
        let schnitzel = parsed.rows[1].draft
        #expect(schnitzel.day.rawValue == "2026-11-12")
        #expect(schnitzel.meal == "Mittagessen")
        #expect(schnitzel.amount == 180)
        #expect(schnitzel.needsLookup)
        #expect(parsed.rows[2].draft.status == .planned)
        #expect(parsed.skipped.count == 1)
        #expect(ImportKind.detect(file) == .diary)
    }

    @Test func dates() {
        #expect(DiaryCSV.parseDate("2026-11-13")?.rawValue == "2026-11-13")
        #expect(DiaryCSV.parseDate("13.11.26")?.rawValue == "2026-11-13")
        #expect(DiaryCSV.parseDate("11/13/2026")?.rawValue == "2026-11-13")
        #expect(DiaryCSV.parseDate("2026-11-13T08:00:00Z")?.rawValue == "2026-11-13")
        #expect(DiaryCSV.parseDate("tomorrow") == nil)
    }

    @Test func exportRoundTrips() {
        let parsed = DiaryCSV.parse(file)
        let exported = DiaryCSV.export(parsed.rows.map { ($0.key, $0.draft) })
        let again = DiaryCSV.parse(exported)
        #expect(again.rows.count == 3)
        #expect(again.rows[0].draft.nutrients[.energy] == 233)
        #expect(again.rows[2].draft.status == .planned)
    }
}

@Suite("Recipe CSV")
struct RecipeCSVTests {
    let file = """
    recipe,kind,servings,total_weight_g,ingredient,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,notes
    Usual breakfast,meal,,,Oats,60,g,,233,8.1,40,4.1,6,0.6,0.7,0,
    Usual breakfast,meal,,,Milk 1.5%,250,ml,,118,8.5,12,3.8,0,12,2.4,0.3,
    Chili,recipe,4,1600,Beef mince,500,g,,1250,100,0,95,,,,,Simmer 1 h
    Chili,recipe,4,1600,Kidney beans,1,can,240,,,,,,,,,
    Empty,meal,,,,,,,,,,,,,,,
    """

    @Test func groupsIngredients() throws {
        let parsed = RecipeCSV.parse(file)
        #expect(parsed.rows.count == 2)
        let breakfast = try #require(parsed.rows.first?.draft)
        #expect(breakfast.kind == .meal)
        #expect(breakfast.items.count == 2)
        #expect(breakfast.items[1].unit == .milliliter)
        let chili = parsed.rows[1].draft
        #expect(chili.kind == .recipe)
        #expect(chili.servings == 4)
        #expect(chili.totalWeight == 1600)
        #expect(chili.notes == "Simmer 1 h")
        #expect(chili.items[1].needsLookup)
        #expect(parsed.skipped == ["Empty: no ingredients"])
        #expect(ImportKind.detect(file) == .recipes)
    }

    @Test func recipeAsFood() {
        let totals = NutrientValues([.energy: 1600, .protein: 120, .carbs: 100, .fat: 80])
        let byWeight = RecipeMath.record(ref: FoodRef("recipe:x"), recordID: nil, name: "Chili", totals: totals, servings: 4, weight: 1600)
        #expect(byWeight.unit == .gram)
        #expect(byWeight.nutrients.energy == 100)
        #expect(byWeight.servings.first?.amount == 400)
        let byServing = RecipeMath.record(ref: FoodRef("recipe:x"), recordID: nil, name: "Chili", totals: totals, servings: 4, weight: 0)
        #expect(byServing.unit == .serving)
        #expect(byServing.nutrients.energy == 400)
        #expect(byServing.nutrients(forAmount: 0.5).energy == 200)
    }

    @Test func exportParsesBack() {
        let parsed = RecipeCSV.parse(file)
        let exported = RecipeCSV.export(parsed.rows.map(\.draft))
        let again = RecipeCSV.parse(exported)
        #expect(again.rows.map(\.draft.name) == ["Usual breakfast", "Chili"])
        #expect(again.rows[1].draft.servings == 4)
    }
}

@Suite("Open Food Facts")
struct OpenFoodFactsTests {
    @Test func parsesAProduct() throws {
        let json = """
        {"code":"9001234567890","status":1,"product":{"product_name":"Bio Skyr Natur","product_name_de":"Bio Skyr Natur",
        "brands":"Ja! Natürlich, Rewe","quantity":"450 g","serving_size":"150 g","serving_quantity":150,
        "categories_tags":["en:dairies","en:fermented-milk-products","en:yogurts"],
        "nutriments":{"energy-kcal_100g":63,"energy_100g":266,"proteins_100g":11,"carbohydrates_100g":4,"sugars_100g":4,
        "fat_100g":0.2,"saturated-fat_100g":0.1,"salt_100g":0.13,"calcium_100g":0.15}}}
        """
        let result = OpenFoodFacts.parse(Data(json.utf8), barcode: "9001234567890")
        guard case .success(let draft) = result else {
            Issue.record("expected a product, got \(result)")
            return
        }
        #expect(draft.name == "Bio Skyr Natur")
        #expect(draft.brand == "Ja! Natürlich")
        #expect(draft.category == .dairy)
        #expect(draft.unit == .gram)
        #expect(draft.nutrients[.energy] == 63)
        #expect(abs((draft.nutrients[.sodium] ?? 0) - 52) < 0.01)
        #expect(abs((draft.nutrients[.calcium] ?? 0) - 150) < 0.01)
        #expect(draft.servings.map(\.amount) == [150, 450])
    }

    @Test func drinksAreMillilitres() {
        let json = """
        {"status":1,"product":{"product_name":"Almdudler","quantity":"0,5 l","categories_tags":["en:beverages"],
        "nutriments":{"energy-kj_100g":138,"proteins_100g":0,"carbohydrates_100g":8,"fat_100g":0}}}
        """
        guard case .success(let draft) = OpenFoodFacts.parse(Data(json.utf8), barcode: "1") else {
            Issue.record("expected a product")
            return
        }
        #expect(draft.unit == .milliliter)
        #expect(abs(draft.nutrients.energy - 33) < 0.1)
        #expect(draft.servings.first?.amount == 500)
    }

    @Test func missingProducts() {
        #expect(OpenFoodFacts.parse(Data(#"{"status":0}"#.utf8), barcode: "1") == .failure(.notFound))
        #expect(OpenFoodFacts.parse(Data("nope".utf8), barcode: "1") == .failure(.unreadable))
        let noValues = #"{"status":1,"product":{"product_name":"Mystery","nutriments":{}}}"#
        #expect(OpenFoodFacts.parse(Data(noValues.utf8), barcode: "1") == .failure(.noNutrition(name: "Mystery")))
        #expect(OpenFoodFacts.productURL(barcode: "12") == nil)
        #expect(OpenFoodFacts.productURL(barcode: "9001234567890")?.absoluteString.contains("9001234567890") == true)
    }

    @Test func volumes() {
        #expect(OpenFoodFacts.containsVolume("330 ml"))
        #expect(OpenFoodFacts.containsVolume("1,5 l"))
        #expect(OpenFoodFacts.containsVolume("75cl"))
        #expect(!OpenFoodFacts.containsVolume("500 g"))
        #expect(!OpenFoodFacts.containsVolume("1 kg"))
        #expect(OpenFoodFacts.amount(in: "1,5 l") == 1500)
        #expect(OpenFoodFacts.amount(in: "250g") == 250)
    }
}

/// Writes the AI prompts for docs/IMPORT.md: `NINA_PROMPTS_OUT=/path swift test --filter writePrompts`.
@Suite("Prompts for the docs")
struct PromptExportTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NINA_PROMPTS_OUT"] != nil))
    func writePrompts() throws {
        let path = try #require(ProcessInfo.processInfo.environment["NINA_PROMPTS_OUT"])
        let meals = MealSlot.defaults.sorted { $0.minutes < $1.minutes }.map(\.name)
        let text = [
            "### Set up Nina (everything at once)\n\n````text\n" + SetupPrompt.text(appName: "Nina") + "\n````\n",
            "### Goals & settings\n\n````text\n" + SettingsCSV.prompt(appName: "Nina") + "\n````\n",
            "### Foods\n\n```text\n" + FoodCSV.prompt(appName: "Nina").text + "```\n",
            "### Diary\n\n```text\n" + DiaryCSV.prompt(appName: "Nina", mealNames: meals).text + "```\n",
            "### Meals & recipes\n\n```text\n" + RecipeCSV.prompt(appName: "Nina", existingNames: []).text + "```\n",
        ].joined(separator: "\n")
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
