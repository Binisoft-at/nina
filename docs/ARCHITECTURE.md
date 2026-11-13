# Nina – architecture

```
Packages/NinaCore      logic without Apple UI frameworks (Swift Testing, runs on Linux in CI)
  Nutrients            26 nutrients, NutrientValues (unknown ≠ 0, salt/sodium, macro shares, kJ)
  Foods, FoodCategory  FoodRef (usda:… / nina:… / food:<uuid> / recipe:<uuid>), FoodRecord, Serving
  Catalog              the bundled foods.json (USDA SR28 + DACH staples), loaded once
  Search               normalisation (umlauts, "ae"→a, accents), typo-tolerant ranked search with usage
  QuickParser          "200 g chicken, 2 eggs and 1 Semmel" → items with amounts (EN/DE, dag, Achtel …)
  Goals                Mifflin–St Jeor calculator with explainable steps, targets, macro splits
  Days, Diary          day keys (optional late-night day start), meals, day totals and progress
  Insights             period stats, streaks, top foods, weight trend, measured maintenance
  Plan                 weekday rules, materialisation keys, multi-device duplicate convergence
  FoodCSV, DiaryCSV,   the three import/export formats and their AI prompts; header aliases
  Recipes, ImportColumns  (German labels, kJ, salt), lookups for rows without nutrition
  OpenFoodFacts        barcode product JSON → food draft
  Snapshot             today's numbers for widgets/complications; Health type mapping
  NinaTour             the interactive tour catalog
Shared/                compiled into the app, the Mac app and the watch app
  Model/Models         SwiftData models (CloudKit rules: defaults, optional relationships with
                       inverses, nothing unique; nutrients as one text field so new nutrients need
                       no schema change)
  Model/Model+Core     conversions to Core types, NinaSettings (the profile as plain values)
  Store/NinaStore      every change goes through here: logging, editing, moving, copying, plans,
                       soft delete, save, widget snapshot, change notification
  Store/FoodLibrary    catalog + own foods + recipes merged, search index, usage ranking, quick add
  Store/Persistence    opens the store via BinisoftKit ModelStore (+ the tour's practice store)
  Store/DemoData       sample data for -Demo launches and the tour (in memory, never synced)
  Store/WidgetBridge   today's snapshot in the shared App Group (also compiled into the widgets)
  UI/Rings, Format     ring, nutrient colours and locale-aware formatting (also in the widgets)
App/Sources            iOS + macOS app (targets Nina and NinaMac, one source tree)
  Root                 AppModel (state, actions with Undo toasts), navigation, sheets, commands
  Today                the diary day: week strip, summary ring, meals, entries, water, editors
  Add                  search & quick add, portion picker, quick calories, barcode lookup
  Foods                library (group/sort/filter), detail with nutrition label, editor
  Recipes, Plan        meals & recipes, routines and the week plan
  Insights             charts, consistency, macros, top foods, rhythm, weight and maintenance
  Settings, Import     goals, meals, Health, reminders, data; three-format import/export
  Services             Apple Health, notifications (Eaten/Skipped actions), App Intents
  Tour                 the tour on the practice day + TipKit hints
Watch/Sources          watch app: today, water, planned meals, dictation, Digital Crown amounts
Widgets/Sources        widgets (iPhone) and complications (watch) from one source
```

## Data flow

- **Every mutation** goes through `NinaStore`; `save()` writes, refreshes the widget snapshot and
  posts `.ninaDataChanged`. `AppModel` coalesces those into one refresh: settings, food library,
  Health sync, notification schedule.
- **Entries copy their nutrients** when logged (totals of the amount), so editing or deleting a food
  never rewrites history; changing an entry's amount scales its totals.
- **Catalog foods** live in the bundle, not in iCloud. Favouriting, tagging or correcting one creates
  a personal `Food` with `catalogID` set; it keeps the catalog reference, so history and usage stay
  attached.
- **Plans** are entries with `status = planned`. Routines (`PlanRule`) create them for the next days
  once per rule and day (`planKey`), even when deleted (then they stay deleted). Two devices that
  planned before syncing converge on the oldest group.
- **Apple Health** (iPhone only): eaten entries of the last 14 days are written as food correlations
  with `HKMetadataKeySyncIdentifier` + version; edits replace, deletions remove. What was written is
  remembered in a device-only file. Weight and active energy are read live, never stored.
- **Sync**: SwiftData + CloudKit private database of `iCloud.at.binisoft.nina`; the watch syncs on its
  own. The shared App Group only holds today's snapshot for widgets and complications.

## Decisions

| Question | Choice | Why |
|---|---|---|
| Food database | USDA SR28 (public domain), curated to ~1,000 foods with EN/DE names | Accurate, complete nutrients, free to bundle; Open Food Facts only for single barcode lookups (ODbL) |
| Nutrients in the model | One encoded text field | New nutrients without CloudKit schema changes; unknown stays unknown |
| Logging speed | Ranked search with usage + quick-add parser | Typing what you ate is faster than tapping through forms, and deterministic (unlike photo AI) |
| Planning | Planned entries confirmed with one tap / from a notification | Logging becomes confirming |
| Health | Write on iPhone only, sync identifiers | No duplicates across devices; guideline 5.1.3 respected |
