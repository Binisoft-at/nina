import Foundation
import Testing
import BinisoftKitCore
@testable import NinaCore

@Suite("Nutrients")
struct NutrientTests {
    @Test func encodingRoundTripsAndIgnoresUnknownKeys() {
        let values = NutrientValues([.energy: 52, .protein: 0.26, .carbs: 13.81, .fiber: 2.4])
        let text = values.encoded
        #expect(text == "energy=52;protein=0.26;carbs=13.81;fiber=2.4")
        #expect(NutrientValues(encoded: text) == values)
        #expect(NutrientValues(encoded: "energy=10;futureThing=3;protein=x") == NutrientValues([.energy: 10]))
    }

    @Test func sumKeepsUnknownAsUnknown() {
        let a = NutrientValues([.energy: 100, .protein: 5])
        let b = NutrientValues([.energy: 50, .fiber: 2])
        let sum = a + b
        #expect(sum[.energy] == 150)
        #expect(sum[.fiber] == 2)
        #expect(sum[.sugar] == nil)
    }

    @Test func scalingAndSalt() {
        let per100 = NutrientValues([.energy: 52, .sodium: 400])
        let portion = per100.scaled(by: 1.82)
        #expect(abs(portion.energy - 94.64) < 0.001)
        #expect(abs((per100.salt ?? 0) - 1.0) < 0.0001)
        #expect(abs(NutrientValues.sodium(fromSalt: 1.0) - 400) < 0.0001)
    }

    @Test func macroShares() {
        let values = NutrientValues([.protein: 25, .carbs: 45, .fat: 13.333])
        let shares = values.macroShares
        #expect(abs(shares.protein - 0.25) < 0.01)
        #expect(abs(shares.fat - 0.30) < 0.01)
    }

    @Test func numbersPeopleType() {
        #expect(NumberText.parse("1,5") == 1.5)
        #expect(NumberText.parse("½") == 0.5)
        #expect(NumberText.parse("1 1/2") == 1.5)
        #expect(NumberText.parse("3/4") == 0.75)
        #expect(NumberText.parse("2½") == 2.5)
        #expect(NumberText.parse("abc") == nil)
        #expect(NumberText.plain(13.8100001) == "13.81")
        #expect(NumberText.plain(52) == "52")
        #expect(NumberText.plain(-0.00001) == "0")
    }

    @Test func amountTexts() {
        #expect(AmountText(quantity: 150, unitLabel: "g", unitAmount: 1, baseUnit: .gram).text == "150 g")
        #expect(AmountText(quantity: 2, unitLabel: "slice", unitAmount: 30, baseUnit: .gram).text == "2 × slice (60 g)")
        #expect(AmountText(quantity: 1, unitLabel: "medium", unitAmount: 182, baseUnit: .gram).text == "1 medium (182 g)")
        #expect(AmountText(quantity: 0.5, unitLabel: "serving", unitAmount: 1, baseUnit: .serving).text == "½ servings")
        #expect(AmountText.quantity(1.5) == "1½")
        #expect(AmountText.quantity(250) == "250")
    }

    @Test func energyUnits() {
        #expect(abs(EnergyUnit.kJ.value(fromKilocalories: 100) - 418.4) < 0.001)
        #expect(abs(EnergyUnit.kJ.kilocalories(from: 418.4) - 100) < 0.001)
    }

    @Test func servingsEncodeAndParse() {
        let servings = [Serving(en: "slice", de: "Scheibe", amount: 30), Serving(en: "pack", amount: 250)]
        #expect(Serving.decode(Serving.encode(servings)) == servings)
        #expect(Serving.parseList("slice/Scheibe=30|pack=250g") == servings)
        #expect(Serving.formatList(servings) == "slice/Scheibe=30;pack=250")
    }

    @Test func categoriesFromText() {
        #expect(FoodCategory(text: "dairy") == .dairy)
        #expect(FoodCategory(text: "Milchprodukte") == .dairy)
        #expect(FoodCategory(text: "Getränke") == .beverages)
        #expect(FoodCategory(text: "Fast Food") == .fastFood)
        #expect(FoodCategory(text: "something else") == .other)
    }

    @Test func highlightsFollowClaimThresholds() {
        let skyr = FoodRecord(ref: FoodRef("x"), name: "Skyr", nutrients: NutrientValues([.energy: 63, .protein: 11, .carbs: 4, .fat: 0.2, .sugar: 4]))
        #expect(skyr.highlights.contains(.highProtein))
        #expect(skyr.highlights.contains(.lowSugar))
    }
}

@Suite("Catalog and search")
struct SearchTests {
    let catalog = FoodCatalog.bundled

    @Test func bundledCatalogLoads() {
        #expect(catalog.foods.count >= 10)
        let apple = catalog[FoodRef("usda:09003")]
        #expect(apple?.name == "Apple")
        #expect(apple?.nutrients.energy == 52)
        #expect(apple?.servings.first?.amount == 182)
    }

    @Test func oneDamagedFoodDoesNotCostTheCatalog() throws {
        let json = #"{"version":1,"foods":[{"id":"a","en":"A","de":"A","cat":"fruit","n":{"energy":10,"protein":0,"carbs":2,"fat":0}},{"id":"broken"},{"id":"b","en":"B","de":"B","cat":"nope","n":{"energy":5,"protein":0,"carbs":1,"fat":0},"portions":[{"en":"piece","amount":50}]}]}"#
        let catalog = try FoodCatalog.decode(Data(json.utf8))
        #expect(catalog.foods.map(\.ref.rawValue) == ["a", "b"])
        #expect(catalog.byRef[FoodRef("b")]?.category == .other)
        #expect(catalog.byRef[FoodRef("b")]?.servings.first?.de == "")
    }

    @Test func catalogIsConsistent() {
        var ids = Set<FoodRef>()
        for food in catalog.foods {
            #expect(ids.insert(food.ref).inserted, "duplicate id \(food.ref)")
            #expect(!food.name.isEmpty && !food.nameDE.isEmpty, "names missing for \(food.ref)")
            #expect(food.nutrients[.energy] != nil, "energy missing for \(food.ref)")
            for serving in food.servings { #expect(serving.amount > 0) }
        }
    }

    @Test func normalisation() {
        #expect(SearchText.normalize("Äpfel, roh (100 g)") == "apfel roh 100 g")
        #expect(SearchText.normalize("Grüße – Straße") == "grusse strasse")
        #expect(SearchText.tokens("Aepfel") == ["apfel"])
        #expect(SearchText.tokens("Hühnerbrust") == SearchText.tokens("Huehnerbrust"))
    }

    @Test func typos() {
        #expect(SearchText.distance(Array("banane"), Array("banana"), limit: 1) == 1)
        #expect(SearchText.distance(Array("chikcen"), Array("chicken"), limit: 1) == 1)
        #expect(SearchText.distance(Array("apple"), Array("orange"), limit: 2) > 2)
    }

    @Test func rankingFindsWhatPeopleMean() {
        let index = FoodSearchIndex(catalog.foods, language: .english)
        #expect(index.search("banana").first?.ref == FoodRef("usda:09040"))
        #expect(index.search("Banane").first?.ref == FoodRef("usda:09040"))
        #expect(index.search("banan").first?.ref == FoodRef("usda:09040"))
        #expect(index.search("äpfel").first?.ref == FoodRef("usda:09003"))
        #expect(index.search("huhnerbrust").first?.name.hasPrefix("Chicken breast") == true)
        #expect(index.search("chicken roasted").first?.ref == FoodRef("usda:05064"))
        #expect(index.search("eggs").first?.ref == FoodRef("usda:01123"))
        #expect(index.search("").isEmpty)
        #expect(index.search("zzzz qqq").isEmpty)
    }

    @Test func usageAndFavoritesLiftResults() {
        let index = FoodSearchIndex(catalog.foods, language: .english)
        let raw = FoodRef("usda:05062")
        let plain = index.search("chicken breast")
        let used = index.search("chicken breast", usage: [raw: FoodUsage(count: 30, lastUsed: Date(), lastAmount: 200)])
        #expect(plain.firstIndex { $0.ref == raw } ?? 99 >= used.firstIndex { $0.ref == raw } ?? 99)
        #expect(used.first?.ref == raw)
    }

    @Test func germanNamesComeFirstInGerman() {
        let index = FoodSearchIndex(catalog.foods, language: .german)
        let result = index.search("milch").first
        #expect(result?.displayName(.german) == "Vollmilch 3,5 %")
        #expect(result?.secondaryName(.german) == "Whole milk 3.5%")
    }
}

@Suite("Quick add")
struct QuickParserTests {
    let catalog = FoodCatalog.bundled

    @Test func splitsAListIntoItems() {
        let items = QuickParser.parse("200 g chicken breast, 2 eggs and 1 toast")
        #expect(items.count == 3)
        #expect(items[0] == QuickItem(original: "200 g chicken breast", quantity: 200, unit: .mass(1), query: "chicken breast"))
        #expect(items[1].quantity == 2)
        #expect(items[1].query == "eggs")
        #expect(items[2].query == "toast")
    }

    @Test func keepsDishNamesTogether() {
        #expect(QuickParser.parse("fish and chips").map(\.query) == ["fish and chips"])
        #expect(QuickParser.parse("Salz und Pfeffer").count == 1)
        #expect(QuickParser.parse("Banane und 2 Eier").map(\.query) == ["Banane", "Eier"])
    }

    @Test func gluedUnitsFractionsAndWords() {
        #expect(QuickParser.parse("250ml milk").first?.unit == .volume(1))
        #expect(QuickParser.parse("250ml milk").first?.quantity == 250)
        #expect(QuickParser.parse("½ avocado").first?.quantity == 0.5)
        #expect(QuickParser.parse("1 1/2 bananas").first?.quantity == 1.5)
        #expect(QuickParser.parse("zwei Eier").first?.quantity == 2)
        #expect(QuickParser.parse("an apple").first?.query == "apple")
        #expect(QuickParser.parse("1,5 l water").first?.unit == .volume(1000))
    }

    @Test func austrianMeasures() {
        let wurst = QuickParser.parse("10 dag Extrawurst").first
        #expect(wurst?.quantity == 10)
        #expect(wurst?.unit == .mass(10))
        let wine = QuickParser.parse("ein Achtel Rotwein").first
        #expect(wine?.unit == .volume(125))
        #expect(wine?.query == "Rotwein")
        #expect(QuickParser.parse("Krügerl Bier").first?.unit == .volume(500))
    }

    @Test func trailingAmounts() {
        let item = QuickParser.parse("chicken breast 200g").first
        #expect(item?.quantity == 200)
        #expect(item?.unit == .mass(1))
        #expect(item?.query == "chicken breast")
        #expect(QuickParser.parse("Banane x2").first?.quantity == 2)
        #expect(QuickParser.parse("2x toast").first?.quantity == 2)
    }

    @Test func caloriesOnly() {
        let item = QuickParser.parse("350 kcal snack").first
        #expect(item?.isEnergyOnly == true)
        #expect(item?.kilocalories == 350)
        #expect(item?.query == "snack")
        #expect(QuickParser.parse("500 kcal").first?.isEnergyOnly == true)
    }

    @Test func amountsForFoods() throws {
        let egg = try #require(catalog[FoodRef("usda:01123")])
        let twoEggs = QuickParser.amount(for: QuickParser.parse("2 eggs")[0], food: egg)
        #expect(twoEggs.amount == 100)
        #expect(twoEggs.serving?.en == "large")

        let milk = try #require(catalog[FoodRef("usda:01077")])
        let glass = QuickParser.amount(for: QuickParser.parse("1 glass milk")[0], food: milk)
        #expect(glass.amount == 250)
        let grams = QuickParser.amount(for: QuickParser.parse("200 g milk")[0], food: milk)
        #expect(abs(grams.amount - 200 / 1.031) < 0.01)

        let toast = try #require(catalog[FoodRef("usda:18069")])
        let slices = QuickParser.amount(for: QuickParser.parse("2 Scheiben Toast")[0], food: toast)
        #expect(slices.amount == 50)

        let oil = try #require(catalog[FoodRef("usda:04053")])
        let spoon = QuickParser.amount(for: QuickParser.parse("1 EL Olivenöl")[0], food: oil)
        #expect(spoon.amount == 13.5)

        let chicken = try #require(catalog[FoodRef("usda:05062")])
        let plainNumber = QuickParser.amount(for: QuickParser.parse("chicken 180")[0], food: chicken)
        #expect(plainNumber.amount == 180)
    }
}
