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
  those weekdays, 70 % carbs and 30 % protein. With a coach plan, day types do this (see below).
- **Meals** (`meals` = `Breakfast 07:30 🥐;Lunch 12:30 🥗;Jause 10:00`): `Frühstück`, `Mittagessen`,
  `Abendessen`, `Jause` map to the standard meals; other names become own meals.
- **Preferences**: `food_names` (english/german), `energy_unit`, `day_starts_at`, `water_glass_ml`,
  `add_burned_calories` (none/half/all), `focus_nutrients`.
- **Body values** (`body_fat_percent` with `body_fat_method`, and `neck_cm`, `chest_cm`, `arm_cm`,
  `waist_cm`, `waist_narrow_cm`, `hip_cm`, `thigh_cm`, `calf_cm`) become today's baseline: one
  body-fat record (method `estimate` unless the file says otherwise) and one tape record. Each value
  is listed in the preview.
- **`note`** rows: advice from a plan that isn't a setting (training, recovery, timing). They are
  kept in the coach plan and shown there.
- **`not_supported`** rows: only real wishes – something you want Nina to do that no row covers.
  The preview lists them under "Not supported".
- Settings → Import & Export → **Export Goals & Settings** writes the same format, including the
  whole coach plan.

## Coach plan

The same `setting,value` file can carry a whole plan: dated phases, calorie cycling by day type,
body measurements, the weekly check-in, supplements, protein per meal, a long-term goal and notes.
Keys are read like every setting (`.`, spaces and `-` become `_`, upper or lower case), so
`phase.1.gym.calories`, `Phase 1 Gym Calories` and `phase_1_gym_calories` are the same row. Ids
(`gym`, `creatine`, the phase number) are lowercase letters and digits.

| Rows | What they set |
|---|---|
| `day_type.<id>.name`, `.emoji`, `.days` (`mon;wed;fri`, `flexible` or `default`), `.per_week`, `.workouts` | Up to 4 kinds of day with their own targets. Exactly one is the default (all other days). Gym, tennis and rest get an emoji by themselves. |
| `phase.<n>.name`, `.goal`, `.start`, `.end`, `.rate_kg_per_week` (`0.1-0.2`), `.rate_percent_per_week`, `.review_weight_kg` (`82-83`), `.target_weight_kg`, `.target_body_fat_percent`, `.max_waist_gain_cm`, `.note` | Dated phases. Dates are `YYYY-MM-DD` or `YYYY-MM` (a start becomes the 1st, an end the last day of the month); `~` or "about" in front marks them as approximate. |
| `phase.<n>.calories`, `.protein_g`, `.carbs_g`, `.fat_g`, `.fiber_g`, `.water_ml`, `.macros_g` (`160/328/72`) | A phase's baseline targets (for a later phase – the current phase uses the flat rows). |
| `phase.<n>.<day type>.calories`, `.macros_g`, `.protein_g`, `.carbs_g`, `.fat_g`, `.fiber_g`, `.water_ml` | Targets of one day type in that phase. Missing values come from the baseline; calories without carbs keep protein and fat and give carbs the rest. |
| `check.<id>.name`, `.emoji`, `.dose`, `.when` (a meal, `08:00` or `anytime`), `.days` (`daily`, weekdays or day-type ids), `.optional`, `.remind`, `.affects_weight` | Daily checks such as a supplement (`supplement.<id>.*` works too). Creatine is marked "affects weight" by itself. |
| `measure.weigh_in` (`daily 07:00`), `.morning_until`, `.weekly` (`waist`), `.full` (`waist;chest;arm;thigh;hip`), `.full_every_weeks`, `.body_fat_every_weeks`, `.body_fat_method`, `.side`, `.thigh_mark`, `.two_readings` | The measuring routine. |
| `checkin.day` (`mon`), `.adjust_after_weeks` (`2-3`), `.step_kcal` (`100-150`), `.lock_days` | The weekly check-in and calorie adjustments (`check-in.*` works too). |
| `long_term.weight_kg`, `.body_fat_percent`, `.waist_cm`, `.date`, `.note` | The long-term goal, separate from the current phase's target weight. |
| `meal_protein_g` (`35-45`), `protein_meals` (`4` or `breakfast;lunch;snack;dinner`) | Protein per eating occasion. |
| `note` (one row each) | Plan notes. |

How an import changes the plan:

1. **A group replaces the whole group.** If the file has any `day_type.*` rows, the day types become
   exactly those in the file; the same for `phase.*`, `check.*` and `note`. The preview lists what is
   removed. A phase that keeps its number keeps its history (when it was started, earlier targets).
   `long_term.*`, `measure.*`, `checkin.*` and the protein rows change only the values in the file.
2. **Setting up a plan.** The first file with day types or phases turns the current goal into a plan
   (training days become a "Training" day type plus "Rest", the goal one open-ended phase from today),
   then applies the file.
3. **Flat rows belong to the current phase.** `goal`, `rate_kg_per_week`, `target_weight_kg` and
   `calories`, `protein_g`, `carbs_g`, `fat_g`, `fiber_g`, `water_ml` are the running phase's values
   (its baseline targets). Without a running phase they work as before. A maintain phase has no
   pace: `rate_kg_per_week` doesn't change it (its own `phase.N.rate_kg_per_week` row does), and the
   export writes `phase.N.rate_kg_per_week,0` for it.
4. **New targets start today.** Changed targets of a running phase become a new set from today, so
   earlier days keep theirs. They also replace a change planned for a later day (for example a
   check-in adjustment applied "from tomorrow"); the preview says so in orange. A planned phase gets
   its targets from its start. A phase the file starts with a start before today keeps, for the days
   up to yesterday, the targets those days had; its own targets start today.
5. **A start today or earlier counts as "Start".** Importing a phase whose start has come starts it;
   of several, the one that started last runs and the earlier ones end the day before. A phase that
   was already planned with the same start is left for the "phase starts today" card.
6. **`training_days`** still works without `day_type` rows (it becomes the "Training" and "Rest" day
   types once there is a plan); next to `day_type` rows it is skipped with a note.
7. **Checks in orange**: macros more than 5 % off the calories, overlapping phase dates (trimmed), a
   day-type id that doesn't exist, rates outside 0.05–1 kg (or 1.5 %) per week, more than 4 day types.

Example (made-up numbers):

```csv
setting,value
weight_kg,80
goal,gain
rate_kg_per_week,0.1-0.2
target_weight_kg,83
calories,2600
protein_g,160
carbs_g,328
fat_g,72
body_fat_percent,20
body_fat_method,estimate
waist_cm,88
meal_protein_g,35-45
protein_meals,4
long_term.weight_kg,78
long_term.body_fat_percent,14
day_type.gym.name,Gym
day_type.gym.days,mon;wed;fri
day_type.tennis.name,Tennis
day_type.tennis.days,flexible
day_type.tennis.per_week,2
day_type.rest.name,Rest
day_type.rest.days,default
phase.1.name,Lean gain
phase.1.goal,gain
phase.1.start,2030-01-07
phase.1.end,~2030-05-31
phase.1.rate_kg_per_week,0.1-0.2
phase.1.review_weight_kg,82-83
phase.1.gym.calories,2600
phase.1.gym.macros_g,160/328/72
phase.1.tennis.calories,2800
phase.1.tennis.macros_g,160/378/72
phase.1.rest.calories,2400
phase.1.rest.macros_g,160/278/72
phase.2.name,Fat loss
phase.2.goal,lose
phase.2.start,~2030-06
phase.2.end,~2030-08
phase.2.target_weight_kg,78
check.creatine.name,Creatine monohydrate
check.creatine.dose,3-5 g
check.creatine.when,breakfast
check.creatine.optional,yes
measure.weekly,waist
measure.full,waist;chest;arm;thigh;hip
checkin.day,mon
checkin.adjust_after_weeks,2-3
checkin.step_kcal,100-150
note,An extra gym session counts as a gym day: pick Gym on that day.
```

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
- **Ranges** (rates, review weight, protein per meal, check-in steps): `0.1-0.2`, `0.1–0.2`,
  `0.1 to 0.2`.
- **Dates**: `2026-11-13`, `13.11.2026`, `13.11.26`, `11/13/2026`. **Meals**: `breakfast`, `lunch`,
  `dinner`, `snack` or your own meal names; `Frühstück`, `Mittagessen`, `Abendessen`, `Jause` work too.

## The prompts

These are exactly what the app copies (the app also adds your current settings and lists your
existing tags, meal names and recipes so the AI reuses them). Regenerate this section with
`NINA_PROMPTS_OUT=docs/.prompts.md swift test --package-path Packages/NinaCore --filter writePrompts`.

### Set up Nina (everything at once)

````text
You set up my nutrition app "Nina" from what I tell you: about me (body, goal, training, habits, meal times, preferences), my plan if I have one (phases, calorie cycling, measurements, check-ins, supplements), the foods I eat (product names, label photos, my own dishes) and my usual meals and recipes.

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
- Advice from my plan that isn't a setting (training, recovery, timing tips): one row each with setting note – Nina keeps it in my plan.
- Only a real wish that no row covers (e.g. allergies, a diet I follow, a medication, a reminder I want): one row each with setting not_supported – the app shows the list.

| setting | value |
|---|---|
| sex | female, male or unspecified (only for the calorie formula) – e.g. female |
| birth_year | Year of birth, e.g. 1991 (or use age) – e.g. 1991 |
| age | Age in years, if the birth year isn't known |
| height_cm | Height in cm – e.g. 171 |
| weight_kg | Current weight in kg (logged as today's weight) – e.g. 67.3 |
| body_fat_percent | Body fat in %, if I know it (saved as today's body-fat value) |
| body_fat_method | How that body fat was measured: dexa, bodpod, bia_pro (InBody …), scale, skinfold, navy (tape) or estimate (the default) |
| neck_cm | Neck circumference in cm, just below the larynx (today's tape values; also chest_cm, arm_cm, waist_cm, hip_cm, thigh_cm, calf_cm) |
| chest_cm | Chest at nipple height in cm |
| arm_cm | Relaxed upper arm in cm |
| waist_cm | Waist at the navel in cm |
| waist_narrow_cm | Narrowest waist in cm (women's tape estimate) |
| hip_cm | Hip at the widest point in cm |
| thigh_cm | Thigh halfway between hip crease and kneecap in cm |
| calf_cm | Calf at the widest point in cm |
| activity | sedentary (desk job), light (exercise 1–3 days/week), moderate (3–5 days), active (6–7 days), very_active (physical job plus training) – e.g. moderate |
| goal | lose, maintain or gain (weight) – e.g. lose |
| rate_kg_per_week | How fast to lose or gain, kg per week: 0.05–1; a range like 0.1-0.2 is fine – e.g. 0.5 |
| target_weight_kg | Target weight in kg (of the current phase, if my plan has phases) – e.g. 62 |
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
| meal_protein_g | Protein per protein meal in g, a range like 35-45 (or just a minimum) |
| protein_meals | Protein meals per day (4) – or which meals, separated by ; (breakfast;lunch;snack;dinner) |
| training_days | Weekdays with more calories, e.g. mon;wed;fri – or none (with a coach plan use day_type rows instead) – e.g. mon;wed;fri |
| training_extra_kcal | Extra kcal on training days (mostly carbs), e.g. 300 – e.g. 300 |
| meals | My meals with their usual time and an emoji, separated by ; – e.g. Breakfast 07:30 🥐;Lunch 12:30 🥗;Snack 16:00 🍎;Dinner 19:00 🍝 |
| food_names | english or german – e.g. german |
| energy_unit | kcal or kJ – e.g. kcal |
| day_starts_at | Hour the diary day starts, 0–6 (e.g. 3: a 2 am snack still counts for yesterday) |
| water_glass_ml | Size of one glass of water in ml – e.g. 300 |
| add_burned_calories | none, half or all – how much of the calories burned (Apple Health) is added to the day – e.g. half |
| focus_nutrients | Up to 4 nutrients shown first, separated by ; (protein, carbs, fat, fiber, sugar, saturated fat, salt, water …) – e.g. protein;fiber;sugar |
| note | Advice from my plan that isn't a setting (training, recovery, timing) – one row each; Nina keeps it in my plan |
| not_supported | Only a real wish: something I want the app to do that no row covers (one row each) – Nina lists it so I can ask for it |

### Coach plan (in block 1, only if my notes describe one)
Same block, same two columns. Use these rows only when my notes describe a plan: dated phases, calorie cycling, body measurements, weekly check-ins or supplements.
- Dated phases (muscle building, fat loss, maintenance with dates) → phase.N.* rows, N = 1, 2, 3 … in date order. Dates YYYY-MM-DD or YYYY-MM; put ~ in front of an approximate date.
- Calorie cycling (different calories on different kinds of days) → one day_type.ID.* group per kind of day plus phase.N.ID.* targets in each phase that has numbers. IDs are lowercase letters and digits (gym, tennis, rest); at most 4 day types, exactly one with days default.
- The flat goal, rate_kg_per_week, target_weight_kg, calories, protein_g, carbs_g, fat_g, fiber_g and water_ml rows are the current phase's. Without day_type rows, training_days still works.
- Body fat and tape measurements I have now → body_fat_percent, body_fat_method and the *_cm rows (saved as today's values).
- Supplements my plan names → check.ID.* (only what my plan says; never add one).
- Advice that isn't a setting (training, recovery, timing tips) → one note row each. not_supported is only for real wishes: something I want the app to do that no row covers.
- Ranges are written 0.1-0.2, 82-83, 35-45; macros_g is protein/carbs/fat in grams like 160/328/72.
- A group you write replaces that whole group: if you change a day type, a phase or a check, write all day_type.*, phase.N.* and check.* rows again (copy the unchanged ones from my current settings). Leave the groups out when nothing in them changes.

| setting | value |
|---|---|
| long_term.weight_kg | Long-term goal weight in kg (separate from the current phase's target_weight_kg) – e.g. 78 |
| long_term.body_fat_percent | Long-term body-fat goal in % – e.g. 14 |
| long_term.waist_cm | Long-term waist goal in cm |
| long_term.date | By when (YYYY-MM-DD or YYYY-MM), only if I said so |
| long_term.note | The long-term goal in my words – e.g. Leaner and stronger |
| day_type.ID.name | A kind of day with its own calories (calorie cycling). ID: lowercase letters and digits like gym, tennis, rest; at most 4 day types – e.g. Gym |
| day_type.ID.emoji | One emoji (optional; gym, tennis and rest get one by themselves) – e.g. 🏋️ |
| day_type.ID.days | Fixed weekdays (mon;wed;fri), flexible (picked by hand on the day) or default (all other days – exactly one day type) – e.g. mon;wed;fri |
| day_type.ID.per_week | Flexible day types: how many per week (a hint) – e.g. 2 |
| day_type.ID.workouts | Apple Health workouts that suggest this day: strength, tennis, running, cycling …, separated by ; – e.g. strength |
| phase.N.name | A dated phase of my plan. N = 1, 2, 3 … in date order – e.g. Lean gain |
| phase.N.goal | gain, maintain or lose – e.g. gain |
| phase.N.start | Start date YYYY-MM-DD or YYYY-MM; ~ in front = approximate. A start today or earlier means the phase is running – e.g. 2030-01-07 |
| phase.N.end | End date, same format – e.g. ~2030-05-31 |
| phase.N.rate_kg_per_week | kg per week, 0.05–1; a range like 0.1-0.2 is fine – e.g. 0.1-0.2 |
| phase.N.rate_percent_per_week | Or the rate in % of body weight per week (0.05–1.5) |
| phase.N.review_weight_kg | Weight (range) at which to review the phase – e.g. 82-83 |
| phase.N.target_weight_kg | Target weight of the phase in kg – e.g. 83 |
| phase.N.target_body_fat_percent | Target body fat of the phase in % |
| phase.N.max_waist_gain_cm | Review the phase when the waist grew this much (gain phases: 4 by default) |
| phase.N.calories | A later phase's daily calories (also phase.N.protein_g, carbs_g, fat_g, fiber_g, water_ml, or macros_g). Leave it out for the current phase: the flat calories, protein_g … rows are its numbers |
| phase.N.macros_g | Protein/carbs/fat in grams in one cell – e.g. 160/278/72 |
| phase.N.ID.calories | Calories on that day type in this phase (also phase.N.ID.protein_g, carbs_g, fat_g, fiber_g, water_ml) – e.g. 2600 |
| phase.N.ID.macros_g | Protein/carbs/fat in grams on that day type – e.g. 160/328/72 |
| phase.N.note | A note about the phase |
| check.ID.name | A daily check my plan names (a supplement). ID like creatine – e.g. Creatine monohydrate |
| check.ID.emoji | One emoji (optional) |
| check.ID.dose | The dose as written in my plan – e.g. 3-5 g |
| check.ID.when | A meal (breakfast, lunch, snack, dinner or my own), a time (08:00) or anytime – e.g. breakfast |
| check.ID.days | daily, weekdays (mon;wed;fri) or day-type ids (gym;tennis) – e.g. daily |
| check.ID.optional | yes when a day without it is fine – e.g. yes |
| check.ID.remind | yes for a reminder |
| check.ID.affects_weight | yes when it can move the scale (creatine – set by itself for creatine) |
| measure.weigh_in | When I weigh myself – e.g. daily 07:00 |
| measure.morning_until | Weigh-ins before this time count as morning weights – e.g. 11:00 |
| measure.weekly | Tape sites every week, separated by ; (waist, waist_narrow, hip, chest, arm, thigh, neck, calf) – e.g. waist |
| measure.full | Tape sites of the full set – e.g. waist;chest;arm;thigh;hip |
| measure.full_every_weeks | Full set every n weeks – e.g. 8 |
| measure.body_fat_every_weeks | Body-fat check every n weeks – e.g. 8 |
| measure.body_fat_method | The body-fat method I'll repeat: dexa, bodpod, bia_pro, scale, skinfold, navy or estimate |
| measure.side | right, left or both (arm, thigh, calf) |
| measure.thigh_mark | Where the thigh is measured, e.g. 20 cm above the kneecap |
| measure.two_readings | yes: two readings per site in a full set |
| checkin.day | Weekday of the weekly check-in – e.g. mon |
| checkin.adjust_after_weeks | Weeks of weigh-ins before calories are adjusted – e.g. 2-3 |
| checkin.step_kcal | Size of one calorie adjustment in kcal – e.g. 100-150 |
| checkin.lock_days | Days without a new adjustment after a change – e.g. 14 |

Example with a coach plan (made-up numbers):
```csv
setting,value
weight_kg,80
goal,gain
rate_kg_per_week,0.1-0.2
target_weight_kg,83
calories,2600
protein_g,160
carbs_g,328
fat_g,72
fiber_g,30
water_ml,2500
body_fat_percent,20
body_fat_method,estimate
waist_cm,88
meal_protein_g,35-45
protein_meals,4
long_term.weight_kg,78
long_term.body_fat_percent,14
long_term.note,Leaner and stronger
day_type.gym.name,Gym
day_type.gym.days,mon;wed;fri
day_type.gym.workouts,strength
day_type.tennis.name,Tennis
day_type.tennis.days,flexible
day_type.tennis.per_week,2
day_type.tennis.workouts,tennis
day_type.rest.name,Rest
day_type.rest.days,default
phase.1.name,Lean gain
phase.1.goal,gain
phase.1.start,2030-01-07
phase.1.end,~2030-05-31
phase.1.rate_kg_per_week,0.1-0.2
phase.1.review_weight_kg,82-83
phase.1.target_weight_kg,83
phase.1.gym.calories,2600
phase.1.gym.macros_g,160/328/72
phase.1.tennis.calories,2800
phase.1.tennis.macros_g,160/378/72
phase.1.rest.calories,2400
phase.1.rest.macros_g,160/278/72
phase.2.name,Fat loss
phase.2.goal,lose
phase.2.start,~2030-06
phase.2.end,~2030-08
phase.2.target_weight_kg,78
phase.2.target_body_fat_percent,14
check.creatine.name,Creatine monohydrate
check.creatine.dose,3-5 g
check.creatine.when,breakfast
check.creatine.optional,yes
measure.weigh_in,daily 07:00
measure.weekly,waist
measure.full,waist;chest;arm;thigh;hip
measure.full_every_weeks,8
measure.body_fat_every_weeks,8
checkin.day,mon
checkin.adjust_after_weeks,2-3
checkin.step_kcal,100-150
note,An extra gym session counts as a gym day: pick Gym on that day.
note,The fat-loss start depends on progress.
```

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
You set up my nutrition app "Nina" from what I tell you about myself (body, goal, training, habits, my meals and their times, preferences) and from my plan if I have one (phases, calorie cycling, measurements, check-ins, supplements). Write the settings as a CSV with two columns.

## Output rules
- Answer with ONE csv code block and nothing else. The first line is exactly this header:
setting,value
- One row per setting. Leave out every setting my notes don't say anything about – only the rows in the file change.
- Prefer my body data (birth_year or age, height_cm, weight_kg, activity, goal, rate_kg_per_week) over fixed numbers: Nina calculates calories and macros from them with the Mifflin–St Jeor formula. Write calories or grams only if I give fixed numbers (e.g. from a dietitian).
- Put a value in "double quotes" if it contains a comma. Decimal point, not comma (67.5). No units inside number cells.
- Advice from my plan that isn't a setting (training, recovery, timing tips): one row each with setting note – Nina keeps it in my plan.
- Only a real wish that no row covers (e.g. allergies, a diet I follow, a medication, a reminder I want): one row each with setting not_supported – the app shows the list.

## Settings
| setting | value |
|---|---|
| sex | female, male or unspecified (only for the calorie formula) – e.g. female |
| birth_year | Year of birth, e.g. 1991 (or use age) – e.g. 1991 |
| age | Age in years, if the birth year isn't known |
| height_cm | Height in cm – e.g. 171 |
| weight_kg | Current weight in kg (logged as today's weight) – e.g. 67.3 |
| body_fat_percent | Body fat in %, if I know it (saved as today's body-fat value) |
| body_fat_method | How that body fat was measured: dexa, bodpod, bia_pro (InBody …), scale, skinfold, navy (tape) or estimate (the default) |
| neck_cm | Neck circumference in cm, just below the larynx (today's tape values; also chest_cm, arm_cm, waist_cm, hip_cm, thigh_cm, calf_cm) |
| chest_cm | Chest at nipple height in cm |
| arm_cm | Relaxed upper arm in cm |
| waist_cm | Waist at the navel in cm |
| waist_narrow_cm | Narrowest waist in cm (women's tape estimate) |
| hip_cm | Hip at the widest point in cm |
| thigh_cm | Thigh halfway between hip crease and kneecap in cm |
| calf_cm | Calf at the widest point in cm |
| activity | sedentary (desk job), light (exercise 1–3 days/week), moderate (3–5 days), active (6–7 days), very_active (physical job plus training) – e.g. moderate |
| goal | lose, maintain or gain (weight) – e.g. lose |
| rate_kg_per_week | How fast to lose or gain, kg per week: 0.05–1; a range like 0.1-0.2 is fine – e.g. 0.5 |
| target_weight_kg | Target weight in kg (of the current phase, if my plan has phases) – e.g. 62 |
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
| meal_protein_g | Protein per protein meal in g, a range like 35-45 (or just a minimum) |
| protein_meals | Protein meals per day (4) – or which meals, separated by ; (breakfast;lunch;snack;dinner) |
| training_days | Weekdays with more calories, e.g. mon;wed;fri – or none (with a coach plan use day_type rows instead) – e.g. mon;wed;fri |
| training_extra_kcal | Extra kcal on training days (mostly carbs), e.g. 300 – e.g. 300 |
| meals | My meals with their usual time and an emoji, separated by ; – e.g. Breakfast 07:30 🥐;Lunch 12:30 🥗;Snack 16:00 🍎;Dinner 19:00 🍝 |
| food_names | english or german – e.g. german |
| energy_unit | kcal or kJ – e.g. kcal |
| day_starts_at | Hour the diary day starts, 0–6 (e.g. 3: a 2 am snack still counts for yesterday) |
| water_glass_ml | Size of one glass of water in ml – e.g. 300 |
| add_burned_calories | none, half or all – how much of the calories burned (Apple Health) is added to the day – e.g. half |
| focus_nutrients | Up to 4 nutrients shown first, separated by ; (protein, carbs, fat, fiber, sugar, saturated fat, salt, water …) – e.g. protein;fiber;sugar |
| note | Advice from my plan that isn't a setting (training, recovery, timing) – one row each; Nina keeps it in my plan |
| not_supported | Only a real wish: something I want the app to do that no row covers (one row each) – Nina lists it so I can ask for it |

## Coach plan (only if my notes describe one)
Same block, same two columns. Use these rows only when my notes describe a plan: dated phases, calorie cycling, body measurements, weekly check-ins or supplements.
- Dated phases (muscle building, fat loss, maintenance with dates) → phase.N.* rows, N = 1, 2, 3 … in date order. Dates YYYY-MM-DD or YYYY-MM; put ~ in front of an approximate date.
- Calorie cycling (different calories on different kinds of days) → one day_type.ID.* group per kind of day plus phase.N.ID.* targets in each phase that has numbers. IDs are lowercase letters and digits (gym, tennis, rest); at most 4 day types, exactly one with days default.
- The flat goal, rate_kg_per_week, target_weight_kg, calories, protein_g, carbs_g, fat_g, fiber_g and water_ml rows are the current phase's. Without day_type rows, training_days still works.
- Body fat and tape measurements I have now → body_fat_percent, body_fat_method and the *_cm rows (saved as today's values).
- Supplements my plan names → check.ID.* (only what my plan says; never add one).
- Advice that isn't a setting (training, recovery, timing tips) → one note row each. not_supported is only for real wishes: something I want the app to do that no row covers.
- Ranges are written 0.1-0.2, 82-83, 35-45; macros_g is protein/carbs/fat in grams like 160/328/72.
- A group you write replaces that whole group: if you change a day type, a phase or a check, write all day_type.*, phase.N.* and check.* rows again (copy the unchanged ones from my current settings). Leave the groups out when nothing in them changes.

| setting | value |
|---|---|
| long_term.weight_kg | Long-term goal weight in kg (separate from the current phase's target_weight_kg) – e.g. 78 |
| long_term.body_fat_percent | Long-term body-fat goal in % – e.g. 14 |
| long_term.waist_cm | Long-term waist goal in cm |
| long_term.date | By when (YYYY-MM-DD or YYYY-MM), only if I said so |
| long_term.note | The long-term goal in my words – e.g. Leaner and stronger |
| day_type.ID.name | A kind of day with its own calories (calorie cycling). ID: lowercase letters and digits like gym, tennis, rest; at most 4 day types – e.g. Gym |
| day_type.ID.emoji | One emoji (optional; gym, tennis and rest get one by themselves) – e.g. 🏋️ |
| day_type.ID.days | Fixed weekdays (mon;wed;fri), flexible (picked by hand on the day) or default (all other days – exactly one day type) – e.g. mon;wed;fri |
| day_type.ID.per_week | Flexible day types: how many per week (a hint) – e.g. 2 |
| day_type.ID.workouts | Apple Health workouts that suggest this day: strength, tennis, running, cycling …, separated by ; – e.g. strength |
| phase.N.name | A dated phase of my plan. N = 1, 2, 3 … in date order – e.g. Lean gain |
| phase.N.goal | gain, maintain or lose – e.g. gain |
| phase.N.start | Start date YYYY-MM-DD or YYYY-MM; ~ in front = approximate. A start today or earlier means the phase is running – e.g. 2030-01-07 |
| phase.N.end | End date, same format – e.g. ~2030-05-31 |
| phase.N.rate_kg_per_week | kg per week, 0.05–1; a range like 0.1-0.2 is fine – e.g. 0.1-0.2 |
| phase.N.rate_percent_per_week | Or the rate in % of body weight per week (0.05–1.5) |
| phase.N.review_weight_kg | Weight (range) at which to review the phase – e.g. 82-83 |
| phase.N.target_weight_kg | Target weight of the phase in kg – e.g. 83 |
| phase.N.target_body_fat_percent | Target body fat of the phase in % |
| phase.N.max_waist_gain_cm | Review the phase when the waist grew this much (gain phases: 4 by default) |
| phase.N.calories | A later phase's daily calories (also phase.N.protein_g, carbs_g, fat_g, fiber_g, water_ml, or macros_g). Leave it out for the current phase: the flat calories, protein_g … rows are its numbers |
| phase.N.macros_g | Protein/carbs/fat in grams in one cell – e.g. 160/278/72 |
| phase.N.ID.calories | Calories on that day type in this phase (also phase.N.ID.protein_g, carbs_g, fat_g, fiber_g, water_ml) – e.g. 2600 |
| phase.N.ID.macros_g | Protein/carbs/fat in grams on that day type – e.g. 160/328/72 |
| phase.N.note | A note about the phase |
| check.ID.name | A daily check my plan names (a supplement). ID like creatine – e.g. Creatine monohydrate |
| check.ID.emoji | One emoji (optional) |
| check.ID.dose | The dose as written in my plan – e.g. 3-5 g |
| check.ID.when | A meal (breakfast, lunch, snack, dinner or my own), a time (08:00) or anytime – e.g. breakfast |
| check.ID.days | daily, weekdays (mon;wed;fri) or day-type ids (gym;tennis) – e.g. daily |
| check.ID.optional | yes when a day without it is fine – e.g. yes |
| check.ID.remind | yes for a reminder |
| check.ID.affects_weight | yes when it can move the scale (creatine – set by itself for creatine) |
| measure.weigh_in | When I weigh myself – e.g. daily 07:00 |
| measure.morning_until | Weigh-ins before this time count as morning weights – e.g. 11:00 |
| measure.weekly | Tape sites every week, separated by ; (waist, waist_narrow, hip, chest, arm, thigh, neck, calf) – e.g. waist |
| measure.full | Tape sites of the full set – e.g. waist;chest;arm;thigh;hip |
| measure.full_every_weeks | Full set every n weeks – e.g. 8 |
| measure.body_fat_every_weeks | Body-fat check every n weeks – e.g. 8 |
| measure.body_fat_method | The body-fat method I'll repeat: dexa, bodpod, bia_pro, scale, skinfold, navy or estimate |
| measure.side | right, left or both (arm, thigh, calf) |
| measure.thigh_mark | Where the thigh is measured, e.g. 20 cm above the kneecap |
| measure.two_readings | yes: two readings per site in a full set |
| checkin.day | Weekday of the weekly check-in – e.g. mon |
| checkin.adjust_after_weeks | Weeks of weigh-ins before calories are adjusted – e.g. 2-3 |
| checkin.step_kcal | Size of one calorie adjustment in kcal – e.g. 100-150 |
| checkin.lock_days | Days without a new adjustment after a change – e.g. 14 |

Example with a coach plan (made-up numbers):
```csv
setting,value
weight_kg,80
goal,gain
rate_kg_per_week,0.1-0.2
target_weight_kg,83
calories,2600
protein_g,160
carbs_g,328
fat_g,72
fiber_g,30
water_ml,2500
body_fat_percent,20
body_fat_method,estimate
waist_cm,88
meal_protein_g,35-45
protein_meals,4
long_term.weight_kg,78
long_term.body_fat_percent,14
long_term.note,Leaner and stronger
day_type.gym.name,Gym
day_type.gym.days,mon;wed;fri
day_type.gym.workouts,strength
day_type.tennis.name,Tennis
day_type.tennis.days,flexible
day_type.tennis.per_week,2
day_type.tennis.workouts,tennis
day_type.rest.name,Rest
day_type.rest.days,default
phase.1.name,Lean gain
phase.1.goal,gain
phase.1.start,2030-01-07
phase.1.end,~2030-05-31
phase.1.rate_kg_per_week,0.1-0.2
phase.1.review_weight_kg,82-83
phase.1.target_weight_kg,83
phase.1.gym.calories,2600
phase.1.gym.macros_g,160/328/72
phase.1.tennis.calories,2800
phase.1.tennis.macros_g,160/378/72
phase.1.rest.calories,2400
phase.1.rest.macros_g,160/278/72
phase.2.name,Fat loss
phase.2.goal,lose
phase.2.start,~2030-06
phase.2.end,~2030-08
phase.2.target_weight_kg,78
phase.2.target_body_fat_percent,14
check.creatine.name,Creatine monohydrate
check.creatine.dose,3-5 g
check.creatine.when,breakfast
check.creatine.optional,yes
measure.weigh_in,daily 07:00
measure.weekly,waist
measure.full,waist;chest;arm;thigh;hip
measure.full_every_weeks,8
measure.body_fat_every_weeks,8
checkin.day,mon
checkin.adjust_after_weeks,2-3
checkin.step_kcal,100-150
note,An extra gym session counts as a gym day: pick Gym on that day.
note,The fat-loss start depends on progress.
```

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
