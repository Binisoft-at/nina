# Nina – import and export

**Set up everything at once:** + → Import My Data → **Copy the Setup Prompt**. Paste it into
ChatGPT, Claude or any AI, add a few lines about you (age, height, weight, goal, training, meal
times) and the foods and meals you eat (product names, label photos, your own dishes), and paste its
whole answer back. It writes up to three CSV blocks – goals & settings, foods, meals & recipes – and
Nina imports them together, settings first, with a preview of every change.

Each format also works on its own, with its own **"Copy the prompt for another AI"** button in
Settings → Import & Export (or + → Import My Data): paste the prompt into any AI together with your
data – photos of nutrition labels, product names, notes, screenshots, another app's export (Yazio,
MyFitnessPal …) – and paste the CSV it writes back into Nina. Nina shows a preview first; nothing
changes until you tap Import. Everything is read on the device.

Importing the same file again **updates instead of duplicating**: rows are matched by their `id`
column (or, without one, by their content). The exports use the same formats, so you can export,
edit in Numbers or Excel, and import again.

| Format | One row per | Nutrition values | Header |
|---|---|---|---|
| Goals & settings | setting | – | `setting,value` |
| Foods | food | per 100 g (or 100 ml for drinks) | `id,name,name_de,brand,category,tags,unit,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,portions,barcode,favorite,notes` |
| Diary | thing eaten | totals of that row | `id,date,time,meal,food,brand,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,note,status` |
| Meals & recipes | ingredient | totals of that ingredient | `recipe,kind,servings,total_weight_g,ingredient,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,notes` |

## Goals & settings

Two columns, one row per setting; only the settings in the file change. The full list with allowed
values is in the prompt below (`SettingsCSV.keys` in NinaCore).

- **Body data** (`sex`, `birth_year` or `age`, `height_cm`, `weight_kg`, `activity`, `goal`,
  `rate_kg_per_week`, `macro_split`) recalculates calories and macros exactly like Settings → Goals
  (Mifflin–St Jeor, activity factor, ±7,700 kcal per kg). `weight_kg` is also logged as today's weight.
- **Fixed numbers** (`calories`, `protein_g`, `carbs_g`, `fat_g`, `fiber_g`, `sugar_max_g`,
  `saturated_fat_max_g`, `salt_max_g`, `water_ml`) win over the calculation. Calories without macros
  keep the current split (or use `macro_split`, also as percent: `30/40/30`).
- **Training days** (`training_days` = `mon;wed;fri` or `none`, `training_extra_kcal`) add calories on
  those weekdays, 70 % carbs and 30 % protein.
- **Meals** (`meals` = `Breakfast 07:30 🥐;Lunch 12:30 🥗;Jause 10:00`): `Frühstück`, `Mittagessen`,
  `Abendessen`, `Jause` map to the standard meals; other names become own meals.
- **Preferences**: `food_names` (english/german), `energy_unit`, `day_starts_at`, `water_glass_ml`,
  `add_burned_calories` (none/half/all), `focus_nutrients`.
- **`not_supported`** rows: whatever the AI found that Nina can't store (allergies, a diet, a
  reminder …). The preview lists them as "Nina can't store these yet".
- Settings → Import & Export → **Export Goals & Settings** writes the same format.

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

These are exactly what the app copies (the app also adds your current settings and lists your
existing tags, meal names and recipes so the AI reuses them). Regenerate this section with
`NINA_PROMPTS_OUT=docs/.prompts.md swift test --package-path Packages/NinaCore --filter writePrompts`.

### Set up Nina (everything at once)

````text
You set up my nutrition app "Nina" from what I tell you: about me (body, goal, training, habits, meal times, preferences), the foods I eat (product names, label photos, my own dishes) and my usual meals and recipes.

## Output rules
- Answer with up to THREE csv code blocks and nothing else, in this order. Each block starts with its header line. Leave a block out when my notes have nothing for it.
  1. Goals & settings – header: setting,value
  2. My foods – header: id,name,name_de,brand,category,tags,unit,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,portions,barcode,favorite,notes
  3. My meals & recipes – header: recipe,kind,servings,total_weight_g,ingredient,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,notes
- Comma separated, UTF-8. Put a value in "double quotes" if it contains a comma, a quote or a line break. Decimal point, not comma (4.5). No units inside number cells.
- Never invent data; leave a cell empty when it doesn't apply and skip a row when it's unclear. Keep my own words and names as I wrote them.
- Nina already knows about 1,000 basic foods (fruit, vegetables, bread, dairy, meat, fish, drinks …) in English and German. Put a food into block 2 only if it's a branded product, my own item, or I give label values. Ingredients of meals and recipes may be basic foods: leave their nutrient cells empty and Nina looks them up.

## 1. Goals & settings (setting,value)
- One row per setting. Leave out every setting my notes don't say anything about – only the rows in the file change.
- Prefer my body data (birth_year or age, height_cm, weight_kg, activity, goal, rate_kg_per_week) over fixed numbers: Nina calculates calories and macros from them with the Mifflin–St Jeor formula. Write calories or grams only if I give fixed numbers (e.g. from a dietitian).
- Put a value in "double quotes" if it contains a comma. Decimal point, not comma (67.5). No units inside number cells.
- Anything I mention that doesn't fit a setting (e.g. allergies, a diet I follow, a medication, a reminder I want): one row each with setting not_supported – the app shows the list.

| setting | value |
|---|---|
| sex | female, male or unspecified (only for the calorie formula) – e.g. female |
| birth_year | Year of birth, e.g. 1991 (or use age) – e.g. 1991 |
| age | Age in years, if the birth year isn't known |
| height_cm | Height in cm – e.g. 171 |
| weight_kg | Current weight in kg (logged as today's weight) – e.g. 67.3 |
| activity | sedentary (desk job), light (exercise 1–3 days/week), moderate (3–5 days), active (6–7 days), very_active (physical job plus training) – e.g. moderate |
| goal | lose, maintain or gain (weight) – e.g. lose |
| rate_kg_per_week | How fast to lose or gain, kg per week (0.25–1) – e.g. 0.5 |
| target_weight_kg | Target weight in kg – e.g. 62 |
| macro_split | balanced, high_protein, low_carb, endurance or keto – or percent of calories as protein/carbs/fat, e.g. 30/40/30 – e.g. high_protein |
| calories | Daily calories in kcal – only if I have a fixed number; otherwise leave it out and Nina calculates it from my body data |
| protein_g | Daily protein in g (only a fixed number) |
| carbs_g | Daily carbohydrates in g (only a fixed number) |
| fat_g | Daily fat in g (only a fixed number) |
| fiber_g | Daily fiber goal in g |
| sugar_max_g | Most sugar per day in g |
| saturated_fat_max_g | Most saturated fat per day in g |
| salt_max_g | Most salt per day in g |
| water_ml | Daily water goal in ml – e.g. 2500 |
| training_days | Weekdays with more calories, e.g. mon;wed;fri – or none – e.g. mon;wed;fri |
| training_extra_kcal | Extra kcal on training days (mostly carbs), e.g. 300 – e.g. 300 |
| meals | My meals with their usual time and an emoji, separated by ; – e.g. Breakfast 07:30 🥐;Lunch 12:30 🥗;Snack 16:00 🍎;Dinner 19:00 🍝 |
| food_names | english or german – e.g. german |
| energy_unit | kcal or kJ – e.g. kcal |
| day_starts_at | Hour the diary day starts, 0–6 (e.g. 3: a 2 am snack still counts for yesterday) |
| water_glass_ml | Size of one glass of water in ml – e.g. 300 |
| add_burned_calories | none, half or all – how much of the calories burned (Apple Health) is added to the day – e.g. half |
| focus_nutrients | Up to 4 nutrients shown first, separated by ; (protein, carbs, fat, fiber, sugar, saturated fat, salt, water …) – e.g. protein;fiber;sugar |
| not_supported | Anything from my notes that doesn't fit one of the settings above (one row each) – Nina lists it so I can ask for it |

## 2. My foods
Turn the foods I give you (photos of nutrition labels, product names, a spreadsheet or another app's export) into my food list. Values are per 100 g, or per 100 ml for drinks.
- One row per food. Use the values printed on the label (per 100 g / 100 ml). If I only give a product name, use the manufacturer's label values or a national food composition database (USDA, BLS, Swiss Food Composition Database) and never guess wildly; if you're unsure, leave the row out.
- kcal must match the macros roughly (4 kcal per g protein and carbs, 9 per g fat).
- Decimal point, not comma (4.5). No units inside the number cells.
- category must be one of the listed values.
- Number the id column 1, 2, 3 … unless my data already has ids.

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

## 3. My meals & recipes
Turn my recipes and usual meals into rows: one row per ingredient, rows of the same recipe share its name. Nutrition values are the totals for the ingredient amount, not per 100 g.
- Use kind=meal for combinations I eat as they are (e.g. my usual breakfast) and kind=recipe for dishes cooked once and eaten in portions.
- Use reliable values (product labels, USDA, BLS). If you can't know an ingredient's values, leave its nutrient cells empty – the app looks it up.
- Decimal point, not comma. No units inside the number cells.

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

## Example answer
```csv
setting,value
birth_year,1991
height_cm,171
weight_kg,67.3
activity,moderate
goal,lose
rate_kg_per_week,0.5
macro_split,high_protein
training_days,mon;wed;fri
meals,Breakfast 07:30 🥐;Lunch 12:30 🥗;Snack 16:00 🍎;Dinner 19:00 🍝
not_supported,I'm lactose intolerant
```
```csv
id,name,name_de,brand,category,tags,unit,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,portions,barcode,favorite,notes
1,Greek yogurt 2%,Griechisches Joghurt 2 %,Fage,dairy,breakfast;high-protein,g,73,10,3.6,2,,3.6,1.3,0.1,pot=170,5201054017197,yes,
```
```csv
recipe,kind,servings,total_weight_g,ingredient,amount,unit,grams,kcal,protein,carbs,fat,fiber,sugar,saturated_fat,salt,notes
Usual breakfast,meal,,,Oats,60,g,60,233,8.1,40,4.1,6,0.6,0.7,0,
Usual breakfast,meal,,,Milk 1.5%,250,ml,250,118,8.5,12,3.8,0,12,2.4,0.3,
```

## About me and my foods
(I write or paste it below – a few lines are enough.)
````

### Goals & settings

````text
You set up my nutrition app "Nina" from what I tell you about myself (body, goal, training, habits, my meals and their times, preferences). Write the settings as a CSV with two columns.

## Output rules
- Answer with ONE csv code block and nothing else. The first line is exactly this header:
setting,value
- One row per setting. Leave out every setting my notes don't say anything about – only the rows in the file change.
- Prefer my body data (birth_year or age, height_cm, weight_kg, activity, goal, rate_kg_per_week) over fixed numbers: Nina calculates calories and macros from them with the Mifflin–St Jeor formula. Write calories or grams only if I give fixed numbers (e.g. from a dietitian).
- Put a value in "double quotes" if it contains a comma. Decimal point, not comma (67.5). No units inside number cells.
- Anything I mention that doesn't fit a setting (e.g. allergies, a diet I follow, a medication, a reminder I want): one row each with setting not_supported – the app shows the list.

## Settings
| setting | value |
|---|---|
| sex | female, male or unspecified (only for the calorie formula) – e.g. female |
| birth_year | Year of birth, e.g. 1991 (or use age) – e.g. 1991 |
| age | Age in years, if the birth year isn't known |
| height_cm | Height in cm – e.g. 171 |
| weight_kg | Current weight in kg (logged as today's weight) – e.g. 67.3 |
| activity | sedentary (desk job), light (exercise 1–3 days/week), moderate (3–5 days), active (6–7 days), very_active (physical job plus training) – e.g. moderate |
| goal | lose, maintain or gain (weight) – e.g. lose |
| rate_kg_per_week | How fast to lose or gain, kg per week (0.25–1) – e.g. 0.5 |
| target_weight_kg | Target weight in kg – e.g. 62 |
| macro_split | balanced, high_protein, low_carb, endurance or keto – or percent of calories as protein/carbs/fat, e.g. 30/40/30 – e.g. high_protein |
| calories | Daily calories in kcal – only if I have a fixed number; otherwise leave it out and Nina calculates it from my body data |
| protein_g | Daily protein in g (only a fixed number) |
| carbs_g | Daily carbohydrates in g (only a fixed number) |
| fat_g | Daily fat in g (only a fixed number) |
| fiber_g | Daily fiber goal in g |
| sugar_max_g | Most sugar per day in g |
| saturated_fat_max_g | Most saturated fat per day in g |
| salt_max_g | Most salt per day in g |
| water_ml | Daily water goal in ml – e.g. 2500 |
| training_days | Weekdays with more calories, e.g. mon;wed;fri – or none – e.g. mon;wed;fri |
| training_extra_kcal | Extra kcal on training days (mostly carbs), e.g. 300 – e.g. 300 |
| meals | My meals with their usual time and an emoji, separated by ; – e.g. Breakfast 07:30 🥐;Lunch 12:30 🥗;Snack 16:00 🍎;Dinner 19:00 🍝 |
| food_names | english or german – e.g. german |
| energy_unit | kcal or kJ – e.g. kcal |
| day_starts_at | Hour the diary day starts, 0–6 (e.g. 3: a 2 am snack still counts for yesterday) |
| water_glass_ml | Size of one glass of water in ml – e.g. 300 |
| add_burned_calories | none, half or all – how much of the calories burned (Apple Health) is added to the day – e.g. half |
| focus_nutrients | Up to 4 nutrients shown first, separated by ; (protein, carbs, fat, fiber, sugar, saturated fat, salt, water …) – e.g. protein;fiber;sugar |
| not_supported | Anything from my notes that doesn't fit one of the settings above (one row each) – Nina lists it so I can ask for it |

## My notes
(I paste or describe them below.)
````

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
