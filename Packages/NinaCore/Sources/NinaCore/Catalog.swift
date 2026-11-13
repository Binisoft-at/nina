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
    /// Foods that couldn't be read (a damaged entry never costs the whole catalog).
    public var skipped = 0

    private enum CodingKeys: String, CodingKey { case version, generated, sources, foods }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        generated = try container.decodeIfPresent(String.self, forKey: .generated)
        sources = try container.decodeIfPresent([String: String].self, forKey: .sources)
        var list = try container.nestedUnkeyedContainer(forKey: .foods)
        var foods: [CatalogFood] = []
        var skipped = 0
        while !list.isAtEnd {
            if let food = try? list.decode(CatalogFood.self) {
                foods.append(food)
            } else {
                skipped += 1
                _ = try? list.decode(Discarded.self)
            }
        }
        self.foods = foods
        self.skipped = skipped
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(generated, forKey: .generated)
        try container.encodeIfPresent(sources, forKey: .sources)
        try container.encode(foods, forKey: .foods)
    }

    /// Consumes one element of any shape.
    private struct Discarded: Decodable {
        init(from decoder: Decoder) throws {}
    }
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
