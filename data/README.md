# Nina food catalog

Nina ships with a bundled database of about 1,080 everyday foods that people in Austria and Germany
actually eat and log: fruit, vegetables, potatoes, legumes, grains, bread, dairy, cheese, eggs, meat,
poultry, sausages and cold cuts, fish, nuts, sweets, snacks, drinks, alcohol, sauces, spices, prepared
dishes and a few fast-food items. Every food has an English and a German name plus search aliases
(including Austrian words such as *Paradeiser*, *Erdäpfel*, *Topfen*, *Marille* or *Faschiertes*),
nutrients per 100 g (or per 100 ml for drinks) and a few household portions.

The app reads one file, `Packages/NinaCore/Sources/NinaCore/Resources/foods.json`. It is generated; never edit it by hand.

| File | What |
|---|---|
| `data/food-catalog.tsv` | The curated USDA selection: one row per food with names, aliases, category, unit and portions |
| `data/foods-extra.json` | DACH foods USDA lacks (Topfen, Leberkäse, Kaiserschmarrn, Radler, …), each computed from a recipe or taken from typical label values |
| `scripts/build_food_db.py` | Builds and validates `foods.json` from the two files above and the USDA files (Python 3, standard library only) |
| `Packages/NinaCore/Sources/NinaCore/Resources/foods.json` | The generated database the app bundles |

## Sources and licences

- **USDA National Nutrient Database for Standard Reference, Release 28 (SR28).** U.S. Department of
  Agriculture, Agricultural Research Service. Public domain (U.S. government work; CC0). We used the
  SR28 ASCII files (`FOOD_DES.txt`, `NUT_DATA.txt`, `WEIGHT.txt`) as mirrored in
  [github.com/alyssaq/usda-sqlite](https://github.com/alyssaq/usda-sqlite) (`data/` folder). Nutrient
  values are USDA's, unchanged; only rounding and the g → ml conversion are applied. Credit:
  *U.S. Department of Agriculture, Agricultural Research Service. USDA National Nutrient Database for
  Standard Reference, Release 28.*
- **Recipe foods** (`"src": "recipe"`): computed by the build script from a written recipe whose
  ingredients are USDA SR28 foods. Every recipe is stored in `foods-extra.json` with gram (or ml) amounts
  per ingredient and a cooking yield, so anyone can check it.
- **Label foods** (`"src": "label"`): typical per-100 g (per-100 ml) values printed on common Austrian
  and German supermarket products. Used only for simple products (Topfen, Skyr, plant drinks,
  Leberkäse, Extrawurst, bread, …) and rounded conservatively. These are approximations, not the values
  of one particular brand.

Barcode lookups at runtime use Open Food Facts; nothing from Open Food Facts is part of this catalog.
See `THIRD_PARTY_NOTICES.md` in the repository root.

## Rebuild

```bash
# SR28 ASCII files, e.g. from the mirror:
git clone --depth 1 https://github.com/alyssaq/usda-sqlite /tmp/usda-sqlite
python3 scripts/build_food_db.py --sr28 /tmp/usda-sqlite/data
# options: --out <path> (default Packages/NinaCore/Sources/NinaCore/Resources/foods.json), --date YYYY-MM-DD (value of "generated"),
#          --report <file.tsv> (one line per food with names, kcal, macros and portions, for review)
```

The script reads both curated files and the SR28 files, computes the recipes, converts drinks to
per-100 ml, derives portions, rounds, validates and writes compact JSON sorted by id. It prints the
number of foods per category and a warning list. If validation fails it prints the errors and writes
nothing. Building the same input with the same `--date` gives the same file.

### Validation

The build fails on: duplicate ids; duplicate English or duplicate German names (case-insensitive, so
two foods need a distinguishing detail); an unknown category; an empty name or one longer than 44
characters; USDA jargon in a name; more than 6 aliases or an alias that repeats the name; missing
energy, protein, carbohydrate or fat; a negative value; a portion amount that is not above 0 or a
plain gram portion; an implausible density.

It also runs an Atwater check, |energy − (4·protein + 4·carbs + 9·fat + 7·alcohol)| ≤ max(15 kcal, 20 %),
and lists every food outside it. Each one was looked at; the reason is recorded as `atwater: …` in the
catalog's notes column (or `"atwater"` in an extra) and the summary shows it as `ok`. They are all
explained by USDA's own data: fibre-rich spices, herbs and brans (USDA uses specific energy factors and
counts fibre in carbohydrate), vinegar (energy from acetic acid), sugar-free gum (polyols), citrus and
algae factors. A deviation without a recorded reason shows as `WARN`; look at it before shipping.

## Output format (`foods.json`)

```json
{"version":1,"generated":"2026-11-13","sources":{"usda":"…","recipe":"…","label":"…"},"foods":[
 {"id":"usda:09003","en":"Apple","de":"Apfel","aliases":["Äpfel","apples"],"cat":"fruit","unit":"g",
  "n":{"energy":52,"protein":0.26,"carbs":13.8,"fat":0.17,"fiber":2.4,"sugar":10.4,…},
  "portions":[{"en":"medium","de":"mittelgroß","amount":182},…],"src":"usda"}]}
```

- `id`: `usda:<NDB_No>` or `nina:<kebab-case-slug>`. **Stable forever**: never rename, renumber or reuse
  an id, because logged meals refer to it. Remove a food only if it is truly wrong.
- `unit`: `g`, or `ml` for drinks and pourable liquids (milk, cream, juice, soft drinks, beer, wine,
  spirits, plant drinks, broth and soups, coffee, tea, vinegar, soy sauce). For `ml` foods every
  nutrient is per 100 ml (USDA per-100 g value × density) and `density` (g per ml) is given. The density
  comes from USDA household volume weights (fl oz, cup, a container with its volume, tbsp); where the
  USDA weight is implausible the catalog overrides it in the notes (`density=…`). Oils stay in g.
- `n`: nutrients per 100 g or 100 ml. Keys and USDA nutrient numbers: energy 208 (kcal), protein 203,
  carbs 205 (carbohydrate by difference, i.e. including fibre), fat 204, fiber 291, sugar 269,
  saturatedFat 606, monoFat 645, polyFat 646, transFat 605, cholesterol 601 (mg), sodium 307 (mg),
  potassium 306 (mg), calcium 301 (mg), iron 303 (mg), magnesium 304 (mg), zinc 309 (mg), vitaminA 320
  (µg RAE), vitaminC 401 (mg), vitaminD 328 (µg), vitaminE 323 (mg), vitaminB12 418 (µg), folate 435
  (µg DFE), water 255 (g), alcohol 221 (g), caffeine 262 (mg). A key is missing when USDA has no value
  (0 is written only when USDA says 0). Energy is rounded to whole kcal, everything else to at most
  3 significant digits.
- `portions`: up to 4 household portions in the food's unit. The app always offers plain grams or
  millilitres in addition.
- `src`: `usda`, `recipe` or `label`; extras may carry a one-line `note`.

## Naming rules

- Short, natural names a person would type: main noun first, details after a comma
  (`White rice, cooked` / `Weißer Reis, gekocht`, `Chicken breast, roasted` / `Hähnchenbrust, gebraten`).
  At most 44 characters. No USDA jargon ("NFS", "includes USDA commodity", "separable lean only":
  write `lean`, or leave the detail in the notes column).
- German names use proper orthography (umlauts, ß, `3,5 %` with a comma and a space before `%`).
  The German name is the common standard German word; Austrian words go into the aliases
  (`Tomate` + alias `Paradeiser`, `Blumenkohl` + `Karfiol`). Austrian specialties keep their Austrian
  name (`Topfenstrudel`, `Kaiserschmarrn`, `Palatschinken`, `Schlagobers 36 %`, `Maroni`).
- `raw` / `roh` only when the catalog also has a cooked variant (`Carrot, raw` next to
  `Carrot, cooked`, but plain `Apple`). Meat, poultry and fish always say raw or cooked, because the
  raw and cooked weights differ a lot. Dry grains, rice and pasta are `uncooked` / `ungekocht`; dried
  legumes are `dry` / `getrocknet`.
- When two foods would get the same name, add the distinguishing detail (`Sour cream, light` vs.
  `Sour cream, full-fat`; `Duck, roasted, with skin` vs. `… skinless`).
- Aliases: 0–6 extra search terms — synonyms, plurals with a changed stem (`Äpfel`), Austrian and
  regional words, common brand words where people search by brand (`Nutella`, `Soletti`, `Manner
  Schnitten`); never the name itself again.
- Where a USDA food stands in for a European product, say so in the notes (for example `USDA: Kit Kat`
  for the chocolate wafer bar, `USDA 3.25% whole milk` for whole milk 3.5 %).

## Portions

Portion labels are short: `medium` / `mittelgroß`, `slice` / `Scheibe`, `tbsp` / `EL`,
`glass (250 ml)` / `Glas (250 ml)`. Rules used in the catalog:

- Fruit and vegetables: USDA sizes (small, medium, large) where they are realistic; European sizes
  where USDA's are American (potatoes, sweet potatoes).
- Bread slice 25–50 g by bread type, rolls 40–60 g, cheese slice 20 g, eggs by EU size (M 50 g, L 60 g
  edible part), yogurt cups 150–180 g, butter tbsp/tsp/portion pack.
- Drinks use named profiles (`@juice`, `@softdrink`, `@beer`, `@wine`, `@spirits`, `@coffee`, …):
  glass 250 ml, can 330 ml, bottle 0.5 l, small beer 0.33 l, wine *Achtel* 125 ml and *Viertel* 250 ml,
  *Stamperl* 2 cl, espresso cup 30 ml, mug (*Häferl*) 250 ml. The profiles are defined at the top of
  `scripts/build_food_db.py`.
- Never a plain `g` or `100 g` portion.

In `food-catalog.tsv` the portions column is either empty (derive portions from USDA `WEIGHT.txt`:
size words, pieces, slices, tbsp/tsp; cups, ounces and US servings are ignored), `-` (no portions), or a
`|`-separated list of `en/de=amount`, `@profile` and `auto` (the derived portions).

## How to add a food

**From USDA SR28** (preferred whenever USDA has a good match):

1. Find the food in `FOOD_DES.txt` (search the `Long_Desc`) and note the 5-digit NDB number. Prefer the
   generic food over a brand and the plain raw and most common cooked preparation.
2. Add a row to `data/food-catalog.tsv` in its category section:
   `ndb  en  de  aliases  cat  unit  portions  notes` (tab-separated).
3. Run the build, look at the summary and at the food in `--report`, fix names or portions, and check
   the values against `NUT_DATA.txt` for one or two nutrients.

**DACH food without a USDA match** — add an entry to `data/foods-extra.json` with a new
`nina:<slug>` id and one of the two methods:

- `"src": "recipe"` with `"recipe": {"ingredients": [{"ndb": "20481", "g": 125, "item": "flour"}, …],
  "yield": 0.9}`. Amounts are grams, or `"ml"` (converted with the ingredient's USDA density, or a given
  `"density"`). `yield` is cooked weight / raw weight (or give `"yield_g"`); the lost weight is taken out
  of `water`. Drinks (`"unit": "ml"`) are per 100 ml of the finished drink (`"yield_ml"`, default: the
  sum of the ml amounts); `"alcohol_retention"` models alcohol lost on heating. A nutrient is reported
  only when ingredients lacking a USDA value for it are at most 10 % of the recipe mass (water, salt and
  sugar count as true zeros). Use only USDA ingredients and say in `note` where one stands in for a
  European product (e.g. Topfen ≈ USDA dry curd cottage cheese).
- `"src": "label"` with `"label": {"energy": …, "fat": …, "saturatedFat": …, "carbsExclFiber": …,
  "sugar": …, "fiber": …, "protein": …, "salt": …}` copied from typical product labels (per 100 g, or
  per 100 ml with `"unit": "ml"` and a `"density"`). EU labels give carbohydrate without fibre; the build
  adds fibre so `carbs` means the same as USDA's. Salt is converted to sodium (salt ÷ 2.5). Only for
  simple products; never invent precise values without one of these two methods.

Keep the total around 1,000 foods: everyday foods first, no ten variants of the same thing.

## Known limitations

- USDA describes American foods. Products of the same name can differ in Europe (bread, sausages,
  yogurt, sweets); where it mattered we used a closer USDA food, a recipe or label values.
- Recipe values do not apply vitamin retention factors, so heat-sensitive vitamins of cooked recipe
  foods can be slightly high. Fat absorbed in frying is an estimate stated in each recipe.
- Some USDA flours and breads are enriched (added iron, B vitamins, folic acid); unenriched versions
  were chosen where USDA has them.
