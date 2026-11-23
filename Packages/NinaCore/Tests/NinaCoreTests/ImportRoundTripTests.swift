import Foundation
import Testing
import BinisoftKitCore
@testable import NinaCore

// Export → import is a no-op, two AI files in a row don't overwrite each other, and an import only
// changes what the file changes. All values are made up.

private let apple = FoodDraft(name: "Apple", nameDE: "Apfel", category: .fruit, tags: ["snack"],
                              nutrients: NutrientValues([.energy: 52.3333, .protein: 0.2611, .carbs: 13.8104, .fat: 0.17, .fiber: 2.4,
                                                         .sugar: 10.39, .vitaminC: 4.6, .potassium: 107, .sodium: 1]),
                              servings: [Serving(en: "medium", de: "mittel", amount: 182)], barcode: "", isFavorite: true)
private let oatDrink = FoodDraft(name: "Oat drink", brand: "Oatly", category: .beverages, unit: .milliliter,
                                 nutrients: NutrientValues([.energy: 59, .protein: 1, .carbs: 6.6, .fat: 3, .caffeine: 0.0524]),
                                 servings: [Serving(en: "glass", amount: 250)], barcode: "7394376616501", notes: "Barista")

private func foodMap(_ foods: [(UUID, FoodDraft, String)]) -> [String: FoodDraft] {
    var map: [String: FoodDraft] = [:]
    for (uuid, draft, importKey) in foods {
        for key in ImportColumns.lookupKeys(uuid: uuid, importKey: importKey) { map[key] = draft }
        map[draft.contentKey] = map[draft.contentKey] ?? draft
    }
    return map
}

@Suite("Import round trip: foods")
struct FoodRoundTripTests {
    @Test func anUntouchedExportChangesNothing() {
        let a = UUID(), b = UUID()
        let file = FoodCSV.export([(ImportColumns.idKey(a), apple), (ImportColumns.idKey(b), oatDrink)])
        #expect(file.contains("vitamin_c_mg") && file.contains("potassium_mg") && file.contains("sodium_mg") && file.contains("caffeine_mg"))
        #expect(!file.contains("iron_mg")) // only columns some row uses
        let plan = FoodCSV.plan(file, existing: foodMap([(a, apple, ""), (b, oatDrink, "")]))
        #expect(plan.creates == 0 && plan.updates == 0 && plan.unchanged == 2, "\(plan.summary)")
    }

    @Test func everyNutrientComesBackAtFullPrecision() throws {
        let parsed = FoodCSV.parse(FoodCSV.export([(ImportColumns.idKey(UUID()), apple)]))
        let back = try #require(parsed.rows.first?.draft)
        #expect(back.nutrients[.vitaminC] == 4.6)
        #expect(back.nutrients[.potassium] == 107)
        #expect(back.nutrients[.sodium] == 1)
        #expect(back.nutrients[.energy] == 52.3333)
        #expect(back.servings == apple.servings)
    }

    @Test func oneEditedValueChangesOnlyThatValue() throws {
        let a = UUID()
        let edited = FoodCSV.export([(ImportColumns.idKey(a), apple)]).replacingOccurrences(of: ",52.3333,", with: ",55,")
        let plan = FoodCSV.plan(edited, existing: foodMap([(a, apple, "")]))
        #expect(plan.updates == 1)
        let merged = try #require(plan.entries.first?.record)
        #expect(merged.nutrients[.energy] == 55)
        #expect(merged.nutrients[.vitaminC] == 4.6)
        #expect(merged.nutrients[.protein] == 0.2611)
        #expect(merged.servings.first?.de == "mittel")
    }

    @Test func columnsTheFileDoesntHaveKeepTheStoredValues() throws {
        let a = UUID()
        // A short file an AI wrote for the same food: only the label columns, no id.
        let text = "name,kcal,protein,carbs,fat\nApple,52.33,0.26,13.81,0.17\n"
        let plan = FoodCSV.plan(text, existing: foodMap([(a, apple, "")]))
        #expect(plan.unchanged == 1, "\(plan.summary)")
        let changed = FoodCSV.plan("name,kcal,protein,carbs,fat\nApple,60,0.26,13.81,0.17\n", existing: foodMap([(a, apple, "")]))
        let merged = try #require(changed.entries.first?.record)
        #expect(changed.updates == 1)
        #expect(merged.nutrients[.energy] == 60)
        #expect(merged.nutrients[.vitaminC] == 4.6)
        #expect(merged.isFavorite && merged.nameDE == "Apfel" && merged.tags == ["snack"])
    }

    @Test func twoAIFilesInARowDontOverwriteEachOther() {
        let first = "id,name,brand,kcal,protein,carbs,fat\n1,Greek yogurt 2%,Fage,73,10,3.6,2\n2,Oat drink,Oatly,59,1,6.6,3\n"
        let second = "id,name,brand,kcal,protein,carbs,fat\n1,Skyr,,63,11,4,0.2\n2,Protein bar,,380,30,40,12\n3,Rice cakes,,387,8,81,3\n"
        let parsed = FoodCSV.parse(first)
        // What the first import stored: new foods keep the row's key as their import key.
        let stored = parsed.rows.map { (UUID(), $0.draft, $0.key) }
        let plan = FoodCSV.plan(second, existing: foodMap(stored))
        #expect(plan.creates == 3 && plan.updates == 0, "\(plan.summary)")
        #expect(!parsed.rows.contains { $0.key.hasPrefix("id:") })
    }

    @Test func aFoodIAlreadyHaveIsMatchedByNameAndBrand() {
        let mine = FoodDraft(name: "Greek yogurt 2%", brand: "Fage", nutrients: NutrientValues([.energy: 73, .protein: 10, .carbs: 3.6, .fat: 2]))
        let same = FoodCSV.plan("name,brand,kcal,protein,carbs,fat\nGreek yogurt 2%,Fage,73,10,3.6,2\n", existing: foodMap([(UUID(), mine, "")]))
        #expect(same.unchanged == 1)
        let newer = FoodCSV.plan("name,brand,kcal,protein,carbs,fat\ngreek yogurt 2%,FAGE,70,10,3.6,2\n", existing: foodMap([(UUID(), mine, "")]))
        #expect(newer.updates == 1)
    }

    @Test func aBarcodeASpreadsheetShortenedIsLeftOut() throws {
        let parsed = FoodCSV.parse("name,kcal,protein,carbs,fat,barcode\nSkyr,63,11,4,0.2,5.2E+12\n")
        #expect(parsed.rows.first?.draft.barcode == "")
        #expect(parsed.skipped.first?.contains("shortened") == true)
        // …and a stored barcode isn't cleared by it.
        let a = UUID()
        let plan = FoodCSV.plan("id,name,brand,kcal,protein,carbs,fat,barcode\n\(a.uuidString),Oat drink,Oatly,59,1,6.6,3,7.39438E+12\n",
                                existing: foodMap([(a, oatDrink, "")]))
        let merged = try #require(plan.entries.first?.record)
        #expect(merged.barcode == "7394376616501")
    }

    @Test func promptListsMyFoodsAndAsksForEmptyIDs() {
        let prompt = FoodCSV.prompt(appName: "Nina", existingFoods: ["Skyr", "Oat drink"]).text
        #expect(prompt.contains("Foods I already have"))
        #expect(prompt.contains("Skyr, Oat drink"))
        #expect(prompt.contains("Leave the id column empty"))
        #expect(!prompt.contains("Number the id column"))
        let many = (1...300).map { "Food \($0)" }
        #expect(!FoodCSV.prompt(appName: "Nina", existingFoods: many).text.contains("Food 201"))
    }
}

@Suite("Import round trip: diary")
struct DiaryRoundTripTests {
    static let jause = MealSlot(id: "meal-jause", name: "Jause", emoji: "🥪", minutes: 10 * 60)
    static let meals = MealSlot.defaults + [jause]
    static let day = DayKey("2030-03-04")!

    /// Entries as the app stores them: a catalog food with computed totals and micronutrients, a
    /// drink in glasses, a quick entry, an own meal.
    static let entries: [(UUID, DiaryDraft)] = [
        (UUID(), DiaryDraft(day: day, minutes: 450, meal: "breakfast", name: "Banana", quantity: 1, unitLabel: "medium", amount: 118,
                            unit: .gram, nutrients: NutrientValues([.energy: 105.02, .protein: 1.2862, .carbs: 26.9512, .fat: 0.3894,
                                                                    .potassium: 422.44, .vitaminC: 10.266, .sodium: 1.18]))),
        (UUID(), DiaryDraft(day: day, minutes: 455, meal: "breakfast", name: "Orange juice", quantity: 1, unitLabel: "glass", amount: 250,
                            unit: .milliliter, nutrients: NutrientValues([.energy: 112.5, .protein: 1.75, .carbs: 26, .fat: 0.5]))),
        (UUID(), DiaryDraft(day: day, minutes: 720, meal: "lunch", name: "Quick entry", quantity: 1, unitLabel: "serving", amount: 0,
                            unit: .serving, nutrients: NutrientValues([.energy: 350, .protein: 0, .carbs: 0, .fat: 0]))),
        (UUID(), DiaryDraft(day: day, minutes: 600, meal: "meal-jause", name: "Rye bread", quantity: 2, unitLabel: "slice", amount: 64,
                            unit: .gram, nutrients: NutrientValues([.energy: 166.4, .protein: 5.44, .carbs: 30.9, .fat: 1.06]))),
    ]

    static func existing(_ rows: [(UUID, DiaryDraft)], importKeys: [String] = []) -> [String: DiaryDraft] {
        var map: [String: DiaryDraft] = [:]
        for (index, (uuid, draft)) in rows.enumerated() {
            let importKey = index < importKeys.count ? importKeys[index] : ""
            for key in ImportColumns.lookupKeys(uuid: uuid, importKey: importKey) { map[key] = draft }
        }
        return map
    }

    @Test func anUntouchedExportChangesNothing() {
        let file = DiaryCSV.export(Self.entries.map { (ImportColumns.idKey($0.0), $0.1) }, meals: Self.meals)
        #expect(file.contains(",Jause,"))
        #expect(!file.contains("meal-jause"))
        let plan = DiaryCSV.plan(file, existing: Self.existing(Self.entries), meals: Self.meals)
        #expect(plan.creates == 0 && plan.updates == 0 && plan.unchanged == 4, "\(plan.summary)")
    }

    @Test func anExportIntoAnEmptyDiaryComesBackWhole() throws {
        let file = DiaryCSV.export(Self.entries.map { (ImportColumns.idKey($0.0), $0.1) }, meals: Self.meals)
        let rows = DiaryCSV.parse(file).rows.map(\.draft)
        #expect(rows.count == 4)
        #expect(rows[1].unit == .milliliter && rows[1].unitLabel == "glass" && rows[1].amount == 250)
        #expect(rows[2].unit == .serving)
        #expect(rows[0].nutrients[.potassium] == 422.44)
        #expect(DiaryCSV.mealID(rows[3], in: Self.meals) == "meal-jause")
    }

    @Test func aChangedKcalKeepsThePortion() throws {
        let banana = Self.entries[0]
        let file = DiaryCSV.export([(ImportColumns.idKey(banana.0), banana.1)]).replacingOccurrences(of: ",105.02,", with: ",110,")
        let plan = DiaryCSV.plan(file, existing: Self.existing([banana]), meals: Self.meals)
        let merged = try #require(plan.entries.first?.record)
        #expect(plan.updates == 1)
        #expect(merged.nutrients[.energy] == 110)
        #expect(merged.nutrients[.potassium] == 422.44)
        #expect(merged.sameAmount(as: banana.1))
    }

    @Test func aChangedAmountScalesTheTotals() throws {
        let bread = Self.entries[3]
        // Only the date, food and grams: 64 g → 96 g.
        let file = "id,date,food,grams\n\(bread.0.uuidString),2030-03-04,Rye bread,96\n"
        let plan = DiaryCSV.plan(file, existing: Self.existing([bread]), meals: Self.meals)
        let merged = try #require(plan.entries.first?.record)
        #expect(merged.amount == 96)
        #expect(abs((merged.nutrients[.energy] ?? 0) - 249.6) < 0.001)
        #expect(merged.meal == "meal-jause") // no meal column: the meal stays
    }

    @Test func twoAIFilesInARowAreBothNew() {
        let first = "id,date,meal,food,kcal\n1,2030-10-01,breakfast,Oats,233\n"
        let second = "id,date,meal,food,kcal\n1,2030-11-20,dinner,Pizza,800\n"
        let stored = DiaryCSV.parse(first).rows.map { (UUID(), $0.draft) }
        let keys = DiaryCSV.parse(first).rows.map(\.key)
        let plan = DiaryCSV.plan(second, existing: Self.existing(stored, importKeys: keys), meals: Self.meals)
        #expect(plan.creates == 1 && plan.updates == 0)
        // The same AI file again updates nothing.
        #expect(DiaryCSV.plan(first, existing: Self.existing(stored, importKeys: keys)).unchanged == 1)
    }

    @Test func ownMealIDsMatch() {
        #expect(MealSlot.matching("meal-jause", in: Self.meals)?.id == "meal-jause")
        #expect(MealSlot.matching("meal-3f2a1b9c", in: Self.meals + [MealSlot(id: "meal-3f2a1b9c", name: "Pre-workout", emoji: "💪", minutes: 1020)])?.name == "Pre-workout")
        #expect(MealSlot.matching("Jause", in: Self.meals)?.id == "meal-jause")
        #expect(MealSlot.matching("Snacks", in: Self.meals)?.id == "snack")
    }

    @Test func aRowWithoutAMealGoesToTheMealOfItsTime() {
        let rows = DiaryCSV.parse("date,time,food,kcal\n2030-03-04,12:40,Soup,200\n2030-03-04,,Tea,2\n").rows.map(\.draft)
        #expect(DiaryCSV.mealID(rows[0], in: Self.meals) == "lunch")
        #expect(DiaryCSV.mealID(rows[1], in: Self.meals) == "snack")
    }

    @Test func howImportedAmountsAreStored() {
        let banana = Self.entries[0].1.storedAmount()
        #expect(banana == AmountText(quantity: 1, unitLabel: "medium", unitAmount: 118, baseUnit: .gram))
        let grams = DiaryDraft(day: Self.day, meal: "lunch", name: "Rice", quantity: 150, unitLabel: "g", amount: 150).storedAmount()
        #expect(grams == AmountText(quantity: 150, unitLabel: "g", unitAmount: 1, baseUnit: .gram))
        let quick = Self.entries[2].1.storedAmount()
        #expect(quick.baseUnit == .serving && quick.unitAmount == 0)
        // A lookup gave 60 g for two slices.
        let slices = DiaryDraft(day: Self.day, meal: "lunch", name: "Bread", quantity: 2, unitLabel: "slice").storedAmount(lookedUp: (60, .gram))
        #expect(slices == AmountText(quantity: 2, unitLabel: "slice", unitAmount: 30, baseUnit: .gram))
    }

    @Test func amountsWithTheirUnitGluedOn() {
        let rows = DiaryCSV.parse("date,food,amount\n2030-03-04,Oats,40.00 g\n2030-03-04,Milk,0.2 l\n2030-03-04,Bread,2 slices\n").rows.map(\.draft)
        #expect(rows[0].quantity == 40 && rows[0].unitLabel == "g" && rows[0].amount == 40)
        #expect(rows[1].amount == 200 && rows[1].unit == .milliliter)
        #expect(rows[2].quantity == 2 && rows[2].unitLabel == "slices" && rows[2].amount == 0)
    }
}

@Suite("Import round trip: meals & recipes")
struct RecipeRoundTripTests {
    static let oats = RecipeDraft(name: "Overnight oats", kind: .recipe, servings: 2, totalWeight: 0, notes: "Soak overnight", items: [
        RecipeItemDraft(name: "Oats, rolled", quantity: 80, unitLabel: "g", amount: 80, unit: .gram,
                        nutrients: NutrientValues([.energy: 303.2, .protein: 10.5264, .carbs: 54.1, .fat: 5.2, .iron: 3.3672])),
        RecipeItemDraft(name: "Milk 1.5%", quantity: 1, unitLabel: "glass", amount: 250, unit: .gram,
                        nutrients: NutrientValues([.energy: 117.5, .protein: 8.5, .carbs: 12, .fat: 3.75])),
    ])

    @Test func anUntouchedExportChangesNothing() {
        let file = RecipeCSV.exportWithAllNutrients([Self.oats])
        #expect(file.contains("iron_mg"))
        let plan = RecipeCSV.planImport(file, existing: [RecipeCSV.key(forName: Self.oats.name): Self.oats])
        #expect(plan.unchanged == 1 && plan.updates == 0, "\(plan.summary)")
    }

    @Test func unchangedIngredientsAreKept() throws {
        let file = RecipeCSV.exportWithAllNutrients([Self.oats]).replacingOccurrences(of: ",117.5,", with: ",120,")
        let plan = RecipeCSV.planImport(file, existing: [RecipeCSV.key(forName: Self.oats.name): Self.oats])
        let merged = try #require(plan.entries.first?.record)
        #expect(plan.updates == 1)
        #expect(RecipeCSV.keptIngredientIndices(of: merged, in: Self.oats) == [0, nil])
        #expect(merged.items[0] == Self.oats.items[0])
        #expect(merged.notes == "Soak overnight")
    }

    @Test func anIngredientWithoutValuesIsTheStoredOne() throws {
        // An AI repeats the recipe and leaves the nutrients empty: nothing changes.
        let text = "recipe,kind,servings,ingredient,amount,unit,grams\nOvernight oats,recipe,2,\"Oats, rolled\",80,g,80\nOvernight oats,recipe,2,Milk 1.5%,1,glass,250\n"
        let plan = RecipeCSV.planImport(text, existing: [RecipeCSV.key(forName: Self.oats.name): Self.oats])
        #expect(plan.unchanged == 1, "\(plan.summary)")
    }
}

@Suite("Import: cells and shapes")
struct ImportCellTests {
    @Test func numbersPeopleAndAIsWrite() {
        #expect(ImportColumns.number("<0.5") == 0.5)
        #expect(ImportColumns.number("< 0,5 g") == 0.5)
        #expect(ImportColumns.number("~52") == 52)
        #expect(ImportColumns.number("≈ 52") == 52)
        #expect(ImportColumns.number("ca. 52") == 52)
        #expect(ImportColumns.number("12.5 (est.)") == 12.5)
        #expect(ImportColumns.number("1 234") == 1234)
        #expect(ImportColumns.number("12 345,5") == 12345.5)
        #expect(ImportColumns.number("3*") == 3)
        #expect(ImportColumns.number("1 1/2") == 1.5)
        #expect(ImportColumns.number("120 kcal") == 120)
        #expect(ImportColumns.number("about") == nil)
        #expect(ImportColumns.number("-") == nil)
    }

    @Test func aFoodRowWithAnApproximateKcalIsRead() throws {
        let food = try #require(FoodCSV.parse("name,kcal,protein,carbs,fat\nSoup,~52,<0.5,8,1\n").rows.first?.draft)
        #expect(food.nutrients[.energy] == 52)
        #expect(food.nutrients[.protein] == 0.5)
    }

    @Test func millilitreUnits() {
        #expect(BaseUnit(text: "100 ml") == .milliliter)
        #expect(BaseUnit(text: "per 100 ml") == .milliliter)
        #expect(BaseUnit(text: "l") == .milliliter)
        #expect(BaseUnit(text: "per 100 g") == .gram)
        #expect(BaseUnit(text: "1 Portion") == .serving)
        #expect(FoodCSV.parse("name,unit,kcal\nJuice,per 100 ml,45\n").rows.first?.draft.unit == .milliliter)
    }

    @Test func germanNameColumns() {
        for header in ["Produkt", "Artikel", "Lebensmittelname", "Nahrungsmittel"] {
            #expect(ImportKind.detect("\(header);Kalorien;Eiweiß\nSkyr;63;11\n") == .foods, "\(header)")
        }
    }

    @Test func titledAndCopiedBlocksAreFound() {
        let titled = "```csv\n# 2. Foods\nname,kcal,protein,carbs,fat\nSkyr,63,11,4,0.2\n```"
        #expect(ImportBundle.parts(titled).map(\.kind) == [.foods])
        let copied = "csv\nCopy code\nsetting,value\ngoal,lose\n"
        #expect(ImportBundle.parts(copied).map(\.kind) == [.settings])
        let labelled = "Goals & settings:\nsetting,value\ngoal,lose\n"
        #expect(ImportBundle.parts(labelled).map(\.kind) == [.settings])
    }

    @Test func oneFenceWithTwoFiles() throws {
        let text = "```csv\nsetting,value\ngoal,lose\n\nname,kcal,protein,carbs,fat\nSkyr,63,11,4,0.2\n```"
        let parts = ImportBundle.parts(text)
        #expect(parts.map(\.kind) == [.settings, .foods])
        let settings = SettingsCSV.parse(try #require(parts.first).text)
        #expect(settings.skipped.isEmpty, "\(settings.skipped)")
        // A title between them works too.
        let titled = "```csv\nsetting,value\ngoal,lose\n\n## My foods\nname,kcal,protein,carbs,fat\nSkyr,63,11,4,0.2\n```"
        #expect(ImportBundle.parts(titled).map(\.kind) == [.settings, .foods])
    }

    @Test func settingsWithoutAHeader() {
        let text = "```csv\nphase.1.rest.calories,2300\ngoal,lose\n```"
        #expect(ImportBundle.parts(text).map(\.kind) == [.settings])
        let draft = SettingsCSV.parse(ImportBundle.parts(text).first?.text ?? "")
        #expect(draft.goal == .lose)
        #expect(draft.skipped.isEmpty)
    }

    @Test func blocksThatArentRecognisedAreListed() {
        let text = "```csv\nsetting,value\ngoal,lose\n```\n\n```json\n{\"goal\": \"lose\"}\n```"
        let split = ImportBundle.split(text)
        #expect(split.parts.map(\.kind) == [.settings])
        #expect(split.unrecognised.count == 1)
        #expect(split.unrecognised.first?.hasPrefix("Block 2, starting \u{201C}{\"goal\"") == true)
        #expect(ImportBundle.fallbackText("```\nfoo\n```") == "foo")
    }

    @Test func aSettingsCommentColumnIsLeftOut() {
        let draft = SettingsCSV.parse("setting,value,comment\nweight_kg,77.3,from my scale\nmeals,Breakfast 07:00;Lunch 12:30,my times\n")
        #expect(draft.weightKg == 77.3)
        #expect(draft.meals?.map(\.name) == ["Breakfast", "Lunch"])
        #expect(draft.skipped.isEmpty, "\(draft.skipped)")
    }
}
