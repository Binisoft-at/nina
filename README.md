<p align="center"><img src="design/icon-1024.png" width="160" alt="Nina app icon"></p>

# Nina – Your Nutrition Buddy

A nutrition diary for iPhone, iPad, Mac and Apple Watch that keeps the familiar flow of apps like
Yazio – a day, its meals, the calories and macros left – and removes the friction that makes people
stop logging: about 1,000 everyday foods built in (English and German, Austrian words included),
type a whole meal like a message, plan meals and just confirm them, and organise everything the way
you think.

With a plan, Nina also works as your **nutrition coach who measures you**: phases with dates and a
pace, calories that follow the kind of day (gym, tennis, rest), a morning weigh-in and the tape
once a week, body fat every few weeks, and a two-minute check-in every week that proposes a small
calorie change only when your numbers call for it. Nothing changes without your tap. Training
itself stays in your training app.

## Highlights

- **Coach & Body** – a plan with dated phases (gain, maintain, lose) and a pace range, up to four
  day types with their own targets (calorie cycling), daily checks such as a supplement, protein
  per meal and a long-term goal. Today shows the day-type chip, one strip with what's due (weigh
  in, waist, creatine …) and at most one coach card. The weekly check-in looks at your 7-day
  average weight, its pace and how well you followed the plan, and offers "Apply from tomorrow"
  with Undo. Phase starts and the review weight ask before anything switches. How to measure and
  how the check-in decides: [docs/BODY.md](docs/BODY.md).
- **Progress** – **Body**: the 7-day average weight against your plan's corridor, the pace, tape
  tiles with a chart per site, body fat per method with lean and fat mass, the body goal, your
  phases on a timeline, check-ins and all weigh-ins and measurements. **Nutrition**: calories
  against your goal, consistency streaks, macros, fiber/sugar/salt limits, top foods, eating
  rhythm, weekday pattern and your *measured* maintenance calories.
- **Progress photos** – front, side and back, with your last photo shown faintly over the camera so
  you stand the same way, and Compare: two days side by side, faded or with a slider, next to your
  weight and waist. Kept only in Nina's private iCloud, with an optional Face ID lock.
- **Coach on Apple Watch** – today's day type under the ring (tap to switch), weigh-in and waist
  with the Digital Crown, daily checks in one tap and how your weight is going, each with Undo.
- **Body data from Apple Health** – body fat, lean mass and waist from your scale as series of their
  own, your height as a hint, and "Make it a tennis day?" after a matching workout. Read live, never
  stored: [docs/HEALTH.md](docs/HEALTH.md).
- **Bring your history** – old weigh-ins, tape logs and DEXA, InBody or 3D-scan reports come in
  through your AI; Nina adds only what's new, one Undo takes it back, and the export gives it all
  back as CSV.
- **Thalia** – on each iPhone, iPad and Mac, Nina hands Thalia (Binisoft's planner) the day's
  calories, protein, carbs, fat and water, never anything from Apple Health; Settings → Thalia
  turns it off: [docs/THALIA.md](docs/THALIA.md).

- **Today** – a calorie ring with what's left (swipe it for other days), your priority nutrients,
  meals with their totals, water in one tap. Planned food shows dimmed; tap ✓ when you've eaten it.
- **Log in seconds** – search ~1,000 foods (USDA data, names in English and German, "Paradeiser",
  "Topfen", "Erdäpfel" welcome) or type `2 eggs, 1 toast and 200 ml milk`, `10 dag Extrawurst`,
  `ein Achtel Rotwein` – Nina understands amounts and units and logs everything at once. Recents,
  favourites, saved meals, quick calories, barcode scan (Open Food Facts).
- **Gestures everywhere** – swipe right to log again or confirm, left to delete (with Undo), drag
  entries between meals, select many and move, copy or save them as a meal; ⌘Z and shake to undo.
- **Foods, your way** – group by category, brand, tag or letter; sort by most logged, recent,
  calories or protein per calorie; filter by category, "high protein", "high fiber", "light",
  "low sugar" and your own tags. Customise any built-in food with your label's values.
- **Plan** – routines ("usual breakfast, Mon–Fri 07:30") plan themselves; "plan tomorrow like today";
  the notification asks "Lunch planned – eaten?" with ✓ right in the banner.
- **Meals & recipes** – meals log their foods in one tap; recipes compute per serving and per 100 g
  from the cooked weight.
- **Goals & Plan** – the standard calculator (Mifflin–St Jeor) with every step explained with your
  numbers, a pace from 0.05 to 1 kg a week, which nutrients matter most to you, and **My Plan**:
  phases, day types, daily checks, measuring, adjustments, protein per meal, long-term goal, notes,
  pause. On the Mac it is a tab of the Settings window.
- **Import from anywhere** – one setup prompt for your AI that writes your goals, the whole coach
  plan, your foods, your meals and your weight history in one go, plus five CSV formats (goals &
  settings, foods, diary, meals & recipes, weight & body history) with their own prompts. Preview first, with a switch per body value; importing
  again updates instead of duplicating, and Undo puts everything back. "Copy for My AI" hands your
  last four weeks to your AI and asks for an answer you can import. Formats and prompts:
  [docs/IMPORT.md](docs/IMPORT.md).
- **Apple ecosystem** – iCloud sync between all devices, Apple Health (meals, water and weight
  written; weight and activity read live, never stored), Apple Watch app with Digital Crown amounts
  and dictation, complications and widgets with the day type, coach reminders (weigh in right in
  the notification), Siri and Shortcuts ("Log food in Nina"), Mac menus and shortcuts, Liquid
  Glass, light and dark mode.

## Project layout

Nina follows the Binisoft handbook, Binisoft's internal app conventions (version in
`.binisoft-handbook`). Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

| Path | What |
|---|---|
| `Packages/NinaCore` | All logic without Apple UI frameworks: nutrients, the food catalog, search, quick-add parser, goals, insights, plans, CSV formats, Open Food Facts parsing, tour catalog, and the coach (plan, weight signal, body measurements and composition, schedule, adherence, check-in, Today board, reminders) – tested on Linux |
| `Packages/NinaCore/Sources/NinaCore/Resources/foods.json` | The built-in food catalog (built by `scripts/build_food_db.py`, see [data/README.md](data/README.md)) |
| `Shared` | SwiftData models, the store every change goes through, food library, formatting – compiled into the app, the Mac app and the watch app |
| `App/Sources` | iOS + macOS SwiftUI app |
| `Watch/Sources` | watchOS app |
| `Widgets/Sources` | Home/Lock Screen widgets and watch complications (one source, two targets) |
| `Config/` | Every identifier (`Base.xcconfig`), CI settings (`ci.env`), Info.plists and entitlements |
| `cloudkit/schema.ckdb` | CloudKit schema of `iCloud.at.binisoft.nina` (generated by `tools/cloudkit-schema.py`) |
| `Vendor/BinisoftKit`, `scripts/ci`, handbook workflows | Synced from the handbook – never edited here |
| `design/` | Icon sources and renderer |
| `project.yml` | XcodeGen spec (the `.xcodeproj` is generated) |

## Build

```bash
make check   # without a Mac: Core tests + syntax check
make open    # on a Mac: generates Nina.xcodeproj and opens it
```

Requires Xcode 26+. Accounts, secrets, CloudKit and TestFlight: [docs/SETUP.md](docs/SETUP.md).

## Status, privacy, licence

- **Status**: in development; builds go to TestFlight (iPhone, iPad, Mac, Apple Watch).
- **Privacy**: no servers, no accounts, no analytics. The diary syncs only through the user's own
  private iCloud; Apple Health values are read live on each device and never stored in Nina's iCloud
  data; barcode lookups send only the barcode number to Open Food Facts ([docs/HEALTH.md](docs/HEALTH.md)).
- **Licence**: © Binisoft LLC, all rights reserved – the source is public to read, not to reuse
  ([LICENSE](LICENSE)). Food data: USDA (public domain) and Open Food Facts (ODbL) –
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- **Feedback**: bug reports and ideas as GitHub issues are welcome; pull requests aren't accepted at
  the moment. Security problems: [SECURITY.md](SECURITY.md).
