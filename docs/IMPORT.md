# Nina – import and export

Nina reads three CSV formats. Each one has a **"Copy the prompt for another AI"** button in
Settings → Import & Export (or + → Import My Data): paste the prompt into ChatGPT, Claude or any AI
together with your data – photos of nutrition labels, product names, notes, screenshots, another
app's export (Yazio, MyFitnessPal …) – and paste the CSV it writes back into Nina. Nina shows a
preview first; nothing changes until you tap Import. Everything is read on the device.

Importing the same file again **updates instead of duplicating**: rows are matched by their `id`
column (or, without one, by their content). The exports use the same formats, so you can export,
edit in Numbers or Excel, and import again.

| Format | One row per | Nutrition values | Header |
|---|---|---|---|
| Foods | food | per 100 g (or 100 ml for drinks) | `id,name,name_de,brand,category,tags,unit,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,portions,barcode,favorite,notes` |
| Diary | thing eaten | totals of that row | `id,date,time,meal,food,brand,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,note,status` |
| Meals & recipes | ingredient | totals of that ingredient | `recipe,kind,servings,total_weight_g,ingredient,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,notes` |

## Forgiving on purpose

- **Delimiters**: comma, semicolon, tab or `|` – detected from the header line.
- **Numbers**: `4.5`, `4,5`, `1.234,5`, `120 kcal`, `4,5 g` all work.
- **Headers**: German and label wording is understood: `Brennwert (kcal)`, `Eiweiß`,
  `Kohlenhydrate`, `davon Zucker`, `Fett`, `gesättigte Fettsäuren`, `Ballaststoffe`, `Salz`,
  `Lebensmittel`, `Marke`, `Datum`, `Mahlzeit` …
- **Energy** in kJ (`kj` column) is converted; **salt** (EU labels) or **sodium_mg** (US labels).
- **Optional nutrients** (foods format): `monounsaturated_fat`, `polyunsaturated_fat`, `trans_fat`,
  `cholesterol_mg`, `potassium_mg`, `calcium_mg`, `iron_mg`, `magnesium_mg`, `zinc_mg`,
  `vitamin_a_ug`, `vitamin_c_mg`, `vitamin_d_ug`, `vitamin_e_mg`, `vitamin_b12_ug`, `folate_ug`,
  `water_g`, `alcohol_g`, `caffeine_mg`.
- **Lists in a cell** (tags, portions): separated by `;` (`|` works too).
- **Diary and recipe rows without nutrition** (empty `kcal`): Nina looks the food up by name in the
  built-in catalog and your foods and uses the amount (`grams`, or `amount` + `unit` like
  `2` + `slice`). Rows it can't find are reported in the preview and skipped.
- **Dates**: `2026-11-13`, `13.11.2026`, `13.11.26`, `11/13/2026`. **Meals**: `breakfast`, `lunch`,
  `dinner`, `snack` or your own meal names; `Frühstück`, `Mittagessen`, `Abendessen`, `Jause` work too.

## The prompts

These are exactly what the app copies (the app also lists your existing tags, meal names and
recipes so the AI reuses them). Regenerate this section with
`NINA_PROMPTS_OUT=docs/.prompts.md swift test --package-path Packages/NinaCore --filter writePrompts`.

### Foods

```text
You convert my data into the CSV import format of my app "Nina". Turn the foods I give you (photos of nutrition labels, product names, a spreadsheet or another app's export) into my food list. Values are per 100 g, or per 100 ml for drinks.

## Output rules
- Answer with ONE csv code block and nothing else. The first line is exactly this header:
id,name,name_de,brand,category,tags,unit,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,portions,barcode,favorite,notes
- Comma separated, UTF-8. Put a value in "double quotes" if it contains a comma, a quote or a line break.
- Leave a column empty when it doesn't apply. Never invent data; skip a row if it is unclear.
- Keep my own words and names exactly as I wrote them.
- One row per food. Use the values printed on the label (per 100 g / 100 ml). If I only give a product name, use the manufacturer's label values or a national food composition database (USDA, BLS, Swiss Food Composition Database) and never guess wildly; if you're unsure, leave the row out.
- kcal must match the macros roughly (4 kcal per g protein and carbs, 9 per g fat).
- Decimal point, not comma (4.5). No units inside the number cells.
- category must be one of the listed values.
- Number the id column 1, 2, 3 … unless my data already has ids.

## Columns
| column | meaning | required |
|---|---|---|
| id | A stable id per food (1, 2, 3 …). Keep it when you edit the file so importing again updates instead of duplicating. | no |
| name | Food name in my words, short ("Greek yogurt 2%", "Oat milk Barista"). | yes |
| name_de | German name, if you know it (optional). | no |
| brand | Brand or shop, empty for generic foods. | no |
| category | One of: fruit, vegetables, legumes, grains, bread, cereals, dairy, cheese, eggs, meat, poultry, sausages, fish, plantProtein, nuts, fats, sweets, snacks, beverages, alcohol, condiments, spices, dishes, fastFood, other. | no |
| tags | Optional labels separated by ; (e.g. breakfast;high-protein). | no |
| unit | g if the values are per 100 g, ml if per 100 ml (drinks). | no |
| kcal | Energy in kcal per 100 g/ml. | yes |
| protein | Protein in g per 100 g/ml. | yes |
| carbs | Carbohydrates in g per 100 g/ml. | yes |
| fat | Fat in g per 100 g/ml. | yes |
| fiber | Fiber in g per 100 g/ml. | no |
| sugar | Sugars in g per 100 g/ml. | no |
| saturated_fat | Saturated fat in g per 100 g/ml. | no |
| salt | Salt in g per 100 g/ml (as on EU labels). | no |
| portions | Household portions as name=amount separated by ; – amount in g or ml, e.g. slice=30;pack=250;glass=250. | no |
| barcode | EAN/GTIN barcode digits, if known. | no |
| favorite | yes for foods I eat often. | no |
| notes | Anything else. | no |

## Example
```csv
id,name,name_de,brand,category,tags,unit,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,portions,barcode,favorite,notes
1,Greek yogurt 2%,Griechisches Joghurt 2 %,Fage,dairy,breakfast;high-protein,g,73,10,3.6,2,,3.6,1.3,0.1,pot=170,5201054017197,yes,
2,Oat drink Barista,Haferdrink Barista,Oatly,beverages,,ml,59,1,6.6,3,0.8,3.4,0.3,0.1,glass=250,,,
```

Here is my data:
```

### Diary

```text
You convert my data into the CSV import format of my app "Nina". Turn what I ate (notes, screenshots or an export from another nutrition app) into diary rows. Nutrition values are the TOTALS for each row, not per 100 g.

## Output rules
- Answer with ONE csv code block and nothing else. The first line is exactly this header:
id,date,time,meal,food,brand,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,note,status
- Comma separated, UTF-8. Put a value in "double quotes" if it contains a comma, a quote or a line break.
- Leave a column empty when it doesn't apply. Never invent data; skip a row if it is unclear.
- Keep my own words and names exactly as I wrote them.
- One row per food eaten. A meal with several foods becomes several rows with the same date and meal.
- Use the values from my data. If you must estimate, use reliable sources (product labels, USDA, BLS) and say so in the note column.
- Decimal point, not comma. No units inside the number cells.
- Number the id column 1, 2, 3 … unless my data already has ids.

## Columns
| column | meaning | required |
|---|---|---|
| id | A stable id per row (1, 2, 3 …). | no |
| date | Day in YYYY-MM-DD. | yes |
| time | Time HH:MM (24 h), if known. | no |
| meal | breakfast, lunch, dinner or snack (or one of my own meal names). | yes |
| food | What was eaten, short and in my words. | yes |
| brand | Brand, if any. | no |
| amount | How many of unit (e.g. 2 for two slices, 150 for 150 g). | no |
| unit | g, ml, or a portion word like slice, piece, cup, tbsp, glass. | no |
| grams | Total weight in g (or ml for drinks), if known. | no |
| kcal | Total kcal for this row (not per 100 g). Leave empty only if you can't know – the app then looks the food up. | no |
| protein | Total protein in g for this row. | no |
| carbs | Total carbohydrates in g for this row. | no |
| fat | Total fat in g for this row. | no |
| fiber | Total fiber in g. | no |
| sugar | Total sugar in g. | no |
| saturated_fat | Total saturated fat in g. | no |
| salt | Total salt in g. | no |
| note | Anything else. | no |
| status | eaten (default) or planned. | no |

## Names that already exist in Nina (reuse them exactly)
- Meals: Breakfast, Lunch, Snacks, Dinner

## Example
```csv
id,date,time,meal,food,brand,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,note,status
1,2026-11-12,07:30,breakfast,Oats,,60,g,60,233,8.1,40,4.1,6,0.6,0.7,0,,
2,2026-11-12,07:30,breakfast,Banana,,1,piece,118,105,1.3,27,0.4,3.1,14.4,0.1,0,,
```

Here is my data:
```

### Meals & recipes

```text
You convert my data into the CSV import format of my app "Nina". Turn my recipes and usual meals into rows: one row per ingredient, rows of the same recipe share its name. Nutrition values are the totals for the ingredient amount, not per 100 g.

## Output rules
- Answer with ONE csv code block and nothing else. The first line is exactly this header:
recipe,kind,servings,total_weight_g,ingredient,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,notes
- Comma separated, UTF-8. Put a value in "double quotes" if it contains a comma, a quote or a line break.
- Leave a column empty when it doesn't apply. Never invent data; skip a row if it is unclear.
- Keep my own words and names exactly as I wrote them.
- Use kind=meal for combinations I eat as they are (e.g. my usual breakfast) and kind=recipe for dishes cooked once and eaten in portions.
- Use reliable values (product labels, USDA, BLS). If you can't know an ingredient's values, leave its nutrient cells empty – the app looks it up.
- Decimal point, not comma. No units inside the number cells.

## Columns
| column | meaning | required |
|---|---|---|
| recipe | Name of the meal or recipe (the same on every row of it). | yes |
| kind | meal (several foods logged together, e.g. my usual breakfast) or recipe (cooked once, eaten in portions). | no |
| servings | How many portions the recipe makes (recipes only). | no |
| total_weight_g | Cooked weight of the whole recipe in g, if known. | no |
| ingredient | One food of the meal or recipe. | yes |
| amount | How many of unit. | no |
| unit | g, ml, or a portion word like piece, slice, tbsp. | no |
| grams | Weight in g (ml for liquids) of this ingredient. | no |
| kcal | Total kcal of this ingredient amount (not per 100 g). Leave empty if unknown – the app looks it up. | no |
| protein | Total protein in g. | no |
| carbs | Total carbohydrates in g. | no |
| fat | Total fat in g. | no |
| fiber | Total fiber in g. | no |
| sugar | Total sugar in g. | no |
| saturated_fat | Total saturated fat in g. | no |
| salt | Total salt in g. | no |
| notes | Notes for the recipe (preparation), on its first row. | no |

## Example
```csv
recipe,kind,servings,total_weight_g,ingredient,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,notes
Usual breakfast,meal,,,Oats,60,g,60,233,8.1,40,4.1,6,0.6,0.7,0,
Usual breakfast,meal,,,Milk 1.5%,250,ml,250,118,8.5,12,3.8,0,12,2.4,0.3,
```

Here is my data:
```
