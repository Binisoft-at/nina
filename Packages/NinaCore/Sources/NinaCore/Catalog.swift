import Foundation

/// One food in the bundled catalog file (`foods.json`, built by scripts/build_food_db.py from
/// USDA SR28 plus a few DACH staples). See data/README.md.
public struct CatalogFood: Codable, Sendable {
    public var id: String
    public var en: String
    public var de: String
    public var aliases: [String]?
    public var cat: String
    public var unit: String?
    public var density: Double?
    public var n: NutrientValues
    public var portions: [Serving]?
    public var src: String?
    public var note: String?

    public var record: FoodRecord {
        FoodRecord(
            ref: FoodRef(id),
            name: en,
            nameDE: de,
            category: FoodCategory(rawValue: cat) ?? .other,
            unit: BaseUnit(text: unit ?? "g"),
            density: density ?? 1,
            nutrients: n,
            servings: portions ?? [],
            aliases: aliases ?? [],
            source: .catalog
        )
    }
}

public struct CatalogFile: Codable, Sendable {
    public var version: Int
    public var generated: String?
    public var sources: [String: String]?
    public var foods: [CatalogFood]
}

/// The bundled, read-only food catalog. Loaded once; never synced (it ships with the app).
public final class FoodCatalog: Sendable {
    public let foods: [FoodRecord]
    public let byRef: [FoodRef: FoodRecord]
    public let sources: [String: String]
    public let generated: String

    public init(foods: [FoodRecord], sources: [String: String] = [:], generated: String = "") {
        self.foods = foods
        var map: [FoodRef: FoodRecord] = [:]
        for food in foods { map[food.ref] = food }
        self.byRef = map
        self.sources = sources
        self.generated = generated
    }

    public static func decode(_ data: Data) throws -> FoodCatalog {
        let file = try JSONDecoder().decode(CatalogFile.self, from: data)
        return FoodCatalog(foods: file.foods.map(\.record), sources: file.sources ?? [:], generated: file.generated ?? "")
    }

    public subscript(_ ref: FoodRef) -> FoodRecord? { byRef[ref] }

    public static let empty = FoodCatalog(foods: [])

    /// The catalog shipped inside NinaCore (`Resources/foods.json`). Empty if it can't be read.
    public static let bundled: FoodCatalog = {
        guard let url = Bundle.module.url(forResource: "foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? FoodCatalog.decode(data) else { return .empty }
        return catalog
    }()
}
