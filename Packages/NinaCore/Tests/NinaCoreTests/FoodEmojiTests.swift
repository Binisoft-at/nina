import Foundation
import Testing
@testable import NinaCore

struct FoodEmojiTests {
    /// Names as they appear in the catalog and in diaries (English, German, Austrian).
    static let expected: [(String, String?)] = [
        ("Banana", "🍌"), ("Bananen", "🍌"), ("Apple, raw", "🍎"), ("Äpfel", "🍎"),
        ("Erdäpfel, gekocht", "🥔"), ("Potatoes, boiled", "🥔"), ("Sweet potato, baked", "🍠"), ("Süßkartoffel", "🍠"),
        ("Pineapple", "🍍"), ("Watermelon", "🍉"), ("Wassermelone", "🍉"),
        ("Milk 2%", "🥛"), ("Vollmilch 3,5 %", "🥛"), ("Buttermilch", "🥛"), ("Coffee cream 10%", "🥛"),
        ("Apple juice", "🧃"), ("Apfelsaft", "🧃"), ("Orangensaft", "🧃"), ("Lemon juice", "🍋"),
        ("Coffee", "☕"), ("Milchkaffee", "☕"), ("Pfefferminztee", "🍵"), ("Ginger ale", "🥤"),
        ("Bier", "🍺"), ("Weißbier", "🍺"), ("Ein Achtel Rotwein", "🍷"), ("Mineralwasser", "💧"),
        ("Tuna in water, canned", "🐟"), ("Sardinen in Tomatensauce", "🐟"), ("Lachs, geräuchert", "🐟"),
        ("Cheeseburger mit Salat", "🍔"), ("Pizza Salami", "🍕"), ("Chicken soup", "🍲"), ("Gemüsesuppe", "🍲"),
        ("Spaghetti Bolognese", "🍝"), ("Käsespätzle", "🍝"), ("Wiener Schnitzel vom Kalb", "🍖"),
        ("Scrambled eggs", "🍳"), ("Eierspeis", "🍳"), ("Egg, size M", "🥚"), ("Eier", "🥚"),
        ("Chicken breast, roasted", "🍗"), ("Backhendl", "🍗"), ("Chicken meat, roasted, skinless", "🍗"),
        ("Leberkäse", "🍖"), ("Bergkäse", "🧀"), ("Limburger", "🧀"), ("Käsekuchen", "🍰"), ("Käsekrainer", "🌭"),
        ("Milchreis", "🍚"), ("Wassereis", "🍨"), ("Ice cream, vanilla", "🍨"),
        ("Peanut butter", "🥜"), ("Erdnussbutter", "🥜"), ("Butter", "🧈"),
        ("Kichererbsen", "🫘"), ("Erbsen", "🫛"), ("Green beans, cooked", "🫛"),
        ("Pumpkin seeds", nil), ("Olive oil", nil), ("Apfelessig", nil), ("Brown sugar", nil),
        ("Vollkornbrot", "🍞"), ("Semmel", "🥖"), ("Croissant", "🥐"), ("Palatschinken", "🥞"), ("Kaiserschmarrn", "🥞"),
        ("Germknödel", "🥟"), ("Apfelstrudel", "🍰"), ("Rice pudding", "🍮"),
        ("Iceberg lettuce", "🥬"), ("Paradeiser", "🍅"), ("Tomato sauce", "🍅"), ("Champignons", "🍄"),
        ("Almonds", nil), ("Skyr, plain", nil), ("Tofu, firm", nil),
    ]

    @Test func knownFoods() {
        for (name, emoji) in Self.expected {
            #expect(FoodEmoji.match(name) == emoji, "\(name)")
        }
    }

    @Test func fallsBackToTheCategory() {
        let almonds = FoodRecord(ref: FoodRef("test:almonds"), name: "Almonds", nameDE: "Mandeln", category: .nuts,
                                 nutrients: NutrientValues())
        #expect(almonds.emoji == FoodCategory.nuts.emoji)
        // The German name helps when the English one has no match.
        let roll = FoodRecord(ref: FoodRef("test:roll"), name: "Kaiser bun", nameDE: "Kaisersemmel", category: .bread,
                              nutrients: NutrientValues())
        #expect(roll.emoji == "🥖")
    }

    @Test func mostCatalogFoodsHaveTheirOwnEmoji() {
        let foods = FoodCatalog.bundled.foods
        let own = foods.filter { FoodEmoji.match($0.name) != nil || FoodEmoji.match($0.nameDE) != nil }.count
        #expect(foods.count > 1_000)
        #expect(Double(own) / Double(foods.count) > 0.7)
    }
}
