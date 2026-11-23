import Foundation

/// A specific emoji for well-known foods ("Banana" → 🍌, "Vollmilch" → 🥛, "Erdäpfel" → 🥔), else the
/// category's. Works on English and German names, so diary entries logged in either language match.
///
/// The head of a name decides: English puts it last ("apple juice" is juice), German compounds too
/// ("Apfelsaft" is Saft, "Bergkäse" is Käse). So words are checked from the last to the first, and
/// German heads also match at the end of a longer word. Only the part before the first comma and
/// before "with"/"mit" counts ("Cheeseburger mit Salat" is a burger).
public enum FoodEmoji {
    struct Rule {
        let emoji: String
        /// Whole words (also with a plural "s"/"es"/"n"/"en").
        let words: Set<String>
        /// Two-word names, checked before single words ("ice cream", "peanut butter").
        let phrases: [String]
        /// German compound heads: also match as the end of a longer word ("Vollmilch").
        let heads: [String]
    }

    public static func emoji(for names: [String], category: FoodCategory) -> String {
        let key = names.joined(separator: "\u{1F}") + "\u{1F}" + category.rawValue
        if let known = cache.value(for: key) { return known }
        var result = category.emoji
        for name in names where !name.isEmpty {
            if let found = match(name) {
                result = found
                break
            }
        }
        cache.store(result, for: key)
        return result
    }

    /// Lists show the same foods again and again: each name is matched against the rules once.
    private static let cache = EmojiCache()

    private final class EmojiCache: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]

        func value(for key: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return values[key]
        }

        func store(_ value: String, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            if values.count >= 20_000 { values.removeAll(keepingCapacity: true) }
            values[key] = value
        }
    }

    /// The specific emoji for one name, or nil when only the category fits.
    static func match(_ name: String) -> String? {
        let main = name.split(separator: ",", maxSplits: 1).first.map(String.init) ?? name
        var tokens = SearchText.tokens(main).filter { $0.contains(where: \.isLetter) }
        if let side = tokens.firstIndex(where: { splitters.contains($0) }), side > 0 {
            tokens = Array(tokens[..<side])
        }
        guard !tokens.isEmpty else { return nil }
        let joined = " " + tokens.joined(separator: " ") + " "
        for rule in all where rule.phrases.contains(where: { joined.contains(" " + $0 + " ") }) {
            return rule.emoji.isEmpty ? nil : rule.emoji
        }
        // A dish word wins wherever it stands: "Pizza Salami" is a pizza, "Chicken soup" a soup.
        for token in tokens.reversed() {
            if let rule = dishes.first(where: { matches(token, $0) }) { return rule.emoji }
        }
        for token in tokens.reversed() {
            if let rule = foods.first(where: { matches(token, $0) }) {
                return rule.emoji.isEmpty ? nil : rule.emoji
            }
        }
        return nil
    }

    static let all = dishes + foods

    /// Words after these describe how it's served or what it's made of: "Tuna in water",
    /// "Sardinen in Tomatensauce", "Schnitzel vom Kalb".
    static let splitters: Set<String> = FoodSearchIndex.sideMarkers.union(["in", "im", "on", "vom", "von", "aus"])

    static func matches(_ token: String, _ rule: Rule) -> Bool {
        if rule.words.contains(token) { return true }
        for suffix in ["s", "es", "n", "en"] where token.count > suffix.count + 2 && token.hasSuffix(suffix) {
            if rule.words.contains(String(token.dropLast(suffix.count))) { return true }
        }
        return rule.heads.contains { token.count >= $0.count + 3 && token.hasSuffix($0) }
    }

    private static func rule(_ emoji: String, _ words: [String], phrases: [String] = [], heads: [String] = []) -> Rule {
        let normal = { (text: String) in SearchText.tokens(text).joined(separator: " ") }
        return Rule(emoji: emoji, words: Set(words.map(normal)), phrases: phrases.map(normal), heads: heads.map(normal))
    }

    /// Dishes and fast food name other foods inside them, so they win wherever they stand in a name.
    static let dishes: [Rule] = [
        // Exceptions first: Limburger is a cheese, Wassereis an ice pop.
        rule("🧀", ["limburger"]),
        rule("🍨", ["wassereis", "popsicle", "eislutscher", "sundae"], phrases: ["ice pop", "ice lolly"]),
        rule("🍪", [], phrases: ["sandwich cookies", "sandwich cookie"]),
        rule("🥖", [], phrases: ["burger bun", "burger buns", "hot dog bun", "hot dog buns"]),
        rule("🥟", [], phrases: ["spring roll", "spring rolls"]),
        rule("🥩", [], phrases: ["stew meat"]),
        rule("🥔", [], phrases: ["mashed potato", "mashed potatoes", "hash brown", "hash browns"]),
        rule("🍔", ["burger", "cheeseburger", "hamburger"], heads: ["burger"]),
        rule("🍕", ["pizza", "flammkuchen"], heads: ["pizza"]),
        rule("🌭", ["hot dog", "hotdog", "würstel", "würstchen", "frankfurter", "bratwurst", "krainer", "käsekrainer",
                    "sausage", "debreziner", "currywurst"], phrases: ["hot dog", "head cheese"], heads: ["wurst", "würstel", "krainer"]),
        rule("🥪", ["sandwich", "toastie", "panini"], phrases: ["breakfast muffin"], heads: ["sandwich"]),
        rule("🌮", ["taco", "tacos", "nachos", "quesadilla", "enchilada"]),
        rule("🌯", ["burrito", "wrap"]),
        rule("🥙", ["kebab", "kebap", "döner", "gyros"], heads: ["kebab", "kebap", "döner"]),
        rule("🧆", ["falafel"]),
        rule("🍣", ["sushi", "maki", "sashimi", "nigiri"]),
        rule("🍛", ["curry", "dal", "dhal"], heads: ["curry"]),
        rule("🍜", ["ramen", "pho", "udon", "noodle soup"], phrases: ["noodle soup"]),
        rule("🍲", ["soup", "suppe", "stew", "eintopf", "gulasch", "goulash", "chili con carne", "broth", "brühe",
                    "bouillon", "consommé"], phrases: ["chili con carne"], heads: ["suppe", "brühe", "eintopf", "gulasch"]),
        rule("🥗", ["salad", "salat", "bowl", "coleslaw"], heads: ["salat"]),
        rule("🍟", ["fries", "pommes", "chips", "french fries", "wedges", "kroketten", "croquettes", "kartoffelchips", "crisps"], phrases: ["french fries"],
             heads: ["pommes"]),
        rule("🍿", ["popcorn"]),
        rule("🍳", ["scrambled", "eierspeis", "eierspeise", "rührei", "spiegelei", "omelette", "omelett", "frittata",
                    "fried egg", "scrambled eggs", "scrambled egg"], phrases: ["fried egg", "scrambled eggs", "scrambled egg"],
             heads: ["omelett"]),
        rule("🥟", ["dumpling", "knödel", "knödl", "nockerl", "pierogi", "ravioli", "tortellini", "gyoza", "maultaschen"],
             heads: ["knödel", "nockerl", "taschen"]),
        rule("🍝", ["pasta", "spaghetti", "noodles", "nudel", "nudeln", "penne", "macaroni", "lasagne", "lasagna",
                    "fusilli", "linguine", "tagliatelle", "spätzle", "spaetzle", "fleckerl", "gnocchi", "noodle"],
             heads: ["nudeln", "nudel", "spätzle", "fleckerl"]),
    ]

    /// Everything else, specific before general: a word is given the first rule that matches it.
    static let foods: [Rule] = [
        // Oils, fats and vinegar keep their category's emoji: "Olive oil" is not an olive, "Apfelessig" not an apple.
        rule("", ["oil", "öl", "fat", "schmalz", "lard", "vinegar", "essig", "sugar", "zucker"],
             phrases: ["fruit cocktail", "baking soda", "baking powder", "bean gum"], heads: ["öl", "schmalz", "essig", "zucker"]),
        // Seeds are not the plant: "Pumpkin seeds" are not a pumpkin.
        rule("", ["seeds", "seed", "kerne", "samen"], heads: ["kerne", "samen"]),
        // Bakery and sweets.
        rule("🥐", ["croissant", "kipferl", "gipfeli", "plunder", "danish", "golatsche", "kolatsche"],
             phrases: ["cinnamon roll", "cinnamon rolls"], heads: ["kipferl", "croissant", "golatsche", "schnecke"]),
        rule("🥨", ["pretzel", "brezel", "breze", "laugenstange"], heads: ["brezel", "breze"]),
        rule("🥯", ["bagel"]),
        rule("🥞", ["pancake", "pancakes", "palatschinke", "pfannkuchen", "crepe", "crêpe", "kaiserschmarrn", "schmarrn"],
             heads: ["palatschinke", "pfannkuchen", "schmarrn"]),
        rule("🧇", ["waffle", "waffel"], heads: ["waffel"]),
        rule("🍮", ["pudding", "custard", "flan", "grießbrei", "grießkoch", "pannacotta"],
             phrases: ["creme caramel", "crème caramel", "panna cotta"], heads: ["pudding"]),
        rule("🧇", ["wafer", "wafers"]),
        rule("🍩", ["donut", "doughnut", "krapfen", "berliner"], heads: ["krapfen"]),
        rule("🍪", ["cookie", "keks", "kekse", "biscuit", "cracker", "zwieback", "lebkuchen", "vanillekipferl"], heads: ["keks", "kekse"]),
        rule("🧁", ["muffin", "cupcake"], heads: ["muffin"]),
        rule("🍰", ["cake", "kuchen", "torte", "strudel", "gugelhupf", "cheesecake", "tiramisu", "brownie", "schnitte"],
             heads: ["kuchen", "torte", "strudel", "schnitte"]),
        rule("🥧", ["pie", "quiche", "tarte"]),
        rule("🍫", ["chocolate", "schokolade", "praline", "nutella", "mozartkugel", "schoko", "cocoa", "kakao"],
             heads: ["schokolade"]),
        rule("🍬", ["candy", "bonbon", "gummy", "gummibärchen", "fruchtgummi", "marshmallow", "lakritze", "licorice"],
             heads: ["gummi", "bonbon"]),
        rule("🍯", ["honey", "honig", "jam", "marmelade", "marmalade", "konfitüre", "syrup", "sirup"], heads: ["honig", "marmelade", "konfitüre"]),
        // Drinks.
        rule("☕", ["coffee", "kaffee", "espresso", "cappuccino", "latte", "macchiato", "melange", "americano", "flat white",
                   "mocca", "mokka", "verlängerter"], phrases: ["flat white", "kleiner brauner", "großer brauner"], heads: ["kaffee"]),
        rule("🥤", ["cola", "soda", "lemonade", "limonade", "limo", "smoothie", "shake", "milkshake", "eistee", "iced tea",
                    "ice tea", "energy drink", "soft drink", "spezi", "almdudler", "drink"],
             phrases: ["iced tea", "ice tea", "energy drink", "soft drink", "ginger ale"], heads: ["limonade", "shake"]),
        rule("🍵", ["tea", "tee", "matcha", "chai"], heads: ["tee"]),
        rule("🍋", [], phrases: ["lemon juice", "lime juice"]),
        rule("🧃", ["juice", "saft", "nektar", "nectar"], phrases: ["juice spritzer"], heads: ["saft", "nektar"]),
        rule("🍺", ["beer", "bier", "radler", "lager", "pils", "weissbier", "weizen", "ale", "stout", "cider"],
             heads: ["bier", "radler"]),
        rule("🥂", ["sparkling", "prosecco", "sekt", "champagne", "champagner", "frizzante"], phrases: ["sparkling wine"]),
        rule("🍷", ["wine", "wein", "spritzer", "gspritzter", "sangria", "rotwein", "weisswein", "glühwein"],
             heads: ["wein", "spritzer"]),
        rule("🍸", ["cocktail", "martini", "aperol", "mojito", "spritz", "daiquiri", "colada", "margarita", "caipirinha"]),
        rule("🍶", ["sake"]),
        rule("🥃", ["whisky", "whiskey", "vodka", "wodka", "rum", "gin", "schnaps", "brandy", "cognac", "tequila", "liqueur",
                    "likör", "obstler", "jägermeister", "sherry", "port", "portwein", "vermouth", "wermut"], heads: ["schnaps", "likör"]),
        rule("🥥", [], phrases: ["coconut milk", "coconut cream"]),
        rule("🥛", ["milk", "milch", "buttermilk", "kefir", "ayran", "cream", "sahne", "rahm", "obers", "schlagobers", "schmand"],
             phrases: ["oat drink", "soy drink", "sour cream"], heads: ["milch", "sahne", "obers", "rahm"]),
        rule("💧", ["water", "wasser", "mineral water", "sparkling water"], phrases: ["mineral water", "sparkling water"],
             heads: ["wasser"]),
        // Rice before ice cream: Milchreis is rice, Speiseeis is ice cream.
        rule("🍚", ["rice", "reis", "risotto", "basmati", "couscous", "bulgur", "quinoa"],
             phrases: ["jasmine rice", "rice cake", "rice cakes"], heads: ["reis"]),
        rule("🍨", ["ice cream", "eis", "gelato", "eiscreme", "sorbet", "frozen yogurt", "speiseeis"],
             phrases: ["ice cream", "frozen yogurt"], heads: ["eis", "eiscreme"]),
        // Fruit. Pineapple before apple, watermelon before melon.
        rule("🍍", ["pineapple", "ananas"]),
        rule("🎃", ["pumpkin", "kürbis", "squash", "butternut", "hokkaido"], heads: ["kürbis"]),
        rule("🍉", ["watermelon", "wassermelone"]),
        rule("🍈", ["melon", "melone", "honeydew", "cantaloupe", "honigmelone", "zuckermelone"], heads: ["melone"]),
        // Erdäpfel are potatoes, not apples.
        rule("🍠", ["sweet potato", "süsskartoffel", "süßkartoffel", "yam"], phrases: ["sweet potato", "sweet potatoes"]),
        rule("🥔", ["potato", "potatoes", "kartoffel", "erdapfel", "erdäpfel", "rösti", "hash browns", "puree", "püree",
                    "kartoffelpüree", "erdäpfelpüree"], phrases: ["hash browns"], heads: ["kartoffel", "erdapfel", "erdäpfel"]),
        rule("🍎", ["apple", "apfel", "äpfel"], heads: ["apfel", "äpfel"]),
        rule("🍐", ["pear", "birne", "nashi"], heads: ["birne"]),
        rule("🍊", ["orange", "mandarin", "mandarine", "clementine", "tangerine", "grapefruit", "pomelo", "orangen"],
             heads: ["orange", "mandarine"]),
        rule("🍋", ["lemon", "lime", "zitrone", "limette"], heads: ["zitrone", "limette"]),
        rule("🍌", ["banana", "banane"], heads: ["banane"]),
        rule("🍇", ["grape", "grapes", "traube", "trauben", "weintraube", "weintrauben", "raisin", "rosine", "rosinen"],
             heads: ["traube", "rosine"]),
        rule("🍓", ["strawberry", "strawberries", "erdbeere", "erdbeeren", "raspberry", "raspberries", "himbeere", "himbeeren"],
             heads: ["erdbeere", "himbeere"]),
        rule("🫐", ["blueberry", "blueberries", "heidelbeere", "heidelbeeren", "blaubeere", "blaubeeren", "blackberry",
                    "blackberries", "brombeere", "brombeeren", "currant", "currants", "johannisbeere", "ribisel", "berries", "cranberry", "cranberries",
                    "beeren", "acai"], heads: ["heidelbeere", "blaubeere", "brombeere", "beere", "beeren"]),
        rule("🍒", ["cherry", "cherries", "kirsche", "kirschen", "weichsel"], heads: ["kirsche"]),
        rule("🍑", ["peach", "pfirsich", "pfirsiche", "nectarine", "nektarine", "apricot", "aprikose", "marille", "marillen"],
             heads: ["pfirsich", "marille", "aprikose"]),
        rule("🥭", ["mango"]),
        rule("🥥", ["coconut", "kokos", "kokosnuss", "kokosflocken", "kokosraspeln"], heads: ["kokos"]),
        rule("🥝", ["kiwi"]),
        rule("🥑", ["avocado", "guacamole"]),
        rule("🍅", ["tomato", "tomatoes", "tomate", "tomaten", "paradeiser", "ketchup"], heads: ["tomate", "paradeiser"]),
        rule("🫒", ["olive", "olives", "oliven"], heads: ["olive", "oliven"]),
        // Vegetables.
        rule("🍆", ["eggplant", "aubergine", "melanzani"]),
        rule("🥕", ["carrot", "karotte", "möhre", "rüebli", "carrots"], heads: ["karotte", "möhre"]),
        rule("🌽", ["corn", "mais", "maize", "polenta", "sweetcorn", "maiskolben"], heads: ["mais"]),
        rule("🌶️", ["chili", "chilli", "jalapeño", "jalapeno", "pfefferoni", "peperoni", "hot pepper"], phrases: ["hot pepper"]),
        rule("🫑", ["bell pepper", "paprika", "capsicum", "sweet pepper"], phrases: ["bell pepper", "sweet pepper"],
             heads: ["paprika"]),
        rule("🥒", ["cucumber", "gurke", "zucchini", "courgette", "pickle", "essiggurke", "cornichon"], heads: ["gurke"]),
        rule("🥦", ["broccoli", "brokkoli", "cauliflower", "karfiol", "blumenkohl", "romanesco"]),
        rule("🥬", ["lettuce", "spinach", "spinat", "kale", "kohl", "cabbage", "chard", "mangold", "rucola", "arugula",
                    "rocket", "endive", "chinakohl", "pak choi", "bok choy", "kraut", "sauerkraut", "kimchi", "celery", "sellerie"],
             phrases: ["pak choi", "bok choy"], heads: ["kohl", "kraut", "spinat"]),
        rule("🧄", ["garlic", "knoblauch"]),
        rule("🧅", ["onion", "onions", "zwiebel", "leek", "lauch", "porree", "shallot", "schalotte", "scallion",
                    "frühlingszwiebel"], heads: ["zwiebel"]),
        rule("🍄", ["mushroom", "mushrooms", "pilz", "pilze", "champignon", "champignons", "eierschwammerl", "pfifferling",
                    "steinpilz", "chanterelle", "chanterelles", "morel", "morels", "morcheln", "shiitake", "portobello"],
             heads: ["pilz", "pilze", "schwammerl"]),
        rule("🫚", ["ginger", "ingwer"]),
        // Nuts, beans and grains.
        rule("🥜", ["peanut", "peanuts", "erdnuss", "erdnüsse", "peanut butter", "erdnussbutter", "erdnussmus"],
             phrases: ["peanut butter"], heads: ["erdnuss"]),
        rule("🌰", ["chestnut", "kastanie", "maroni", "maronen"]),
        rule("🥜", [], phrases: ["almond butter", "cashew butter", "nut butter", "hazelnut butter"]),
        rule("🫛", [], phrases: ["green beans", "green bean", "snap peas"]),
        rule("🌽", [], phrases: ["corn cakes", "corn cake"]),
        rule("🥣", [], phrases: ["wheat puffs", "rice puffs", "corn puffs"]),
        rule("🥬", [], phrases: ["brussels sprouts"]),
        rule("🌱", ["sprouts", "sprossen", "kresse", "cress", "microgreens"], heads: ["sprossen"]),
        rule("🫘", ["beans", "bean", "bohnen", "bohne", "lentils", "linsen", "chickpeas", "kichererbsen", "hummus"],
             heads: ["bohnen", "linsen", "kichererbsen"]),
        rule("🫛", ["peas", "pea", "erbsen", "erbse", "edamame", "snow peas", "zuckerschoten"], heads: ["erbsen", "erbse"]),
        rule("🥣", ["oats", "oatmeal", "porridge", "haferflocken", "muesli", "müsli", "granola", "cornflakes", "cereal",
                    "haferbrei", "dinkelflocken", "flakes", "pops", "overnight oats"], phrases: ["overnight oats"], heads: ["müsli", "haferflocken", "flakes", "pops"]),
        rule("🫓", ["tortilla", "flatbread", "fladenbrot", "naan", "chapati", "roti", "lavash", "pita"],
             heads: ["fladenbrot"]),
        rule("🥖", ["baguette", "roll", "rolls", "semmel", "semmeln", "brötchen", "weckerl", "weckle", "kaisersemmel",
                    "ciabatta", "flûte", "bun", "buns"], heads: ["semmel", "weckerl", "brötchen", "baguette"]),
        rule("🍞", ["bread", "brot", "toast", "loaf", "pumpernickel", "knäckebrot"], phrases: ["english muffin"],
             heads: ["brot", "toast"]),
        // Meat and fish.
        rule("🥓", ["bacon", "speck", "pancetta", "frühstücksspeck"], heads: ["speck"]),
        rule("🍖", ["ham", "schinken", "leberkäse", "leberkäs", "leberkas", "schnitzel", "ribs", "rippchen", "spareribs",
                    "kotelett", "cordon bleu", "meatball", "meatballs", "fleischlaberl", "frikadelle", "bulette", "faschiertes",
                    "hackfleisch", "mince", "minced", "jerky", "salami", "prosciutto", "kassler", "braten", "schweinsbraten"],
             phrases: ["cordon bleu"], heads: ["schinken", "schnitzel", "laberl", "braten", "leberkäse", "leberkäs"]),
        rule("🍗", ["chicken", "huhn", "hühnchen", "hähnchen", "hendl", "turkey", "pute", "puten", "truthahn", "poultry",
                    "geflügel", "nuggets", "wings", "drumstick", "duck", "ente", "gans", "goose", "hühnerfleisch", "putenfleisch",
                    "hendlfleisch"],
             heads: ["hendl", "huhn", "hähnchen", "pute", "ente"]),
        rule("🥩", ["steak", "beef", "rind", "rindfleisch", "pork", "schwein", "schweinefleisch", "lamb", "lamm", "veal", "kalb",
                    "kalbfleisch", "venison", "wild", "tafelspitz", "roast", "lende"],
             heads: ["fleisch", "steak"]),
        rule("🍤", ["shrimp", "shrimps", "prawn", "prawns", "garnele", "garnelen", "scampi", "krabben"], heads: ["garnele", "garnelen"]),
        rule("🦀", ["crab", "krabbe"]),
        rule("🦞", ["lobster", "hummer", "langusten"]),
        rule("🦑", ["squid", "calamari", "tintenfisch", "octopus", "oktopus", "pulpo"]),
        rule("🦪", ["oyster", "auster", "mussels", "muscheln", "clams"], heads: ["muscheln"]),
        rule("🐟", ["fish", "fisch", "salmon", "lachs", "tuna", "thunfisch", "trout", "forelle", "cod", "kabeljau", "herring",
                    "hering", "mackerel", "makrele", "sardine", "sardinen", "zander", "pangasius", "seelachs", "tilapia",
                    "anchovy", "sardellen", "saibling", "karpfen"], heads: ["fisch", "lachs", "forelle"]),
        // Dairy, eggs and fats.
        rule("🧈", ["butter", "ghee", "margarine"], heads: ["butter", "margarine"]),
        rule("🧀", ["cheese", "käse", "parmesan", "mozzarella", "gouda", "emmentaler", "feta", "camembert", "brie", "cheddar",
                    "halloumi", "ricotta", "mascarpone", "raclette", "fondue", "edam", "edamer", "fontina", "pecorino", "provolone",
                    "tilsit", "tilsiter", "gorgonzola", "manchego", "gruyère", "appenzeller", "bergkäse"], heads: ["käse"]),
        rule("🥚", ["egg", "eggs", "ei", "eier", "egg white", "eiklar", "eigelb", "dotter"], phrases: ["egg white"]),
        // Odds and ends.
        rule("🧂", ["salt", "salz"], heads: ["salz"]),
        rule("🥫", ["canned", "dose", "konserve"]),
    ]
}

extension FoodRecord {
    /// The food's own emoji (🍌 for a banana), else its category's.
    public var emoji: String {
        FoodEmoji.emoji(for: [name, nameDE], category: category)
    }
}
