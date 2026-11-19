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
  SettingsCSV(+Plan)   the goals & settings format, including the whole coach plan, the preview
                       groups and the export; SetupPrompt is the combined prompt for an AI
  OpenFoodFacts        barcode product JSON → food draft
  Snapshot             today's numbers (with the day type) for widgets/complications; Health mapping
  NinaTour             the interactive tour catalog
  -- coach & body --
  CoachPlan            the plan: day types, dated phases with target revisions, long-term goal,
                       protein per meal, daily checks, measuring routine, adjustment rules, pauses,
                       notes; the profile mirror; day-mark kinds and key=value texts
  PlanEdits            plan editor changes (set up, add/change day types and checks, targets as a
                       revision from a day, pause and resume)
  WeightSignal         morning weight, 7-day average, pace (least squares), status, corridor,
                       review checkpoint, unusual readings and reason tags, sanity check
  Body                 tape sites (landmarks, plausible ranges, measurement error), sides, the
                       measuring protocol and conditions, readings (2 + 1), body-fat methods
  BodyComposition      tape trends, US Navy tape estimate (live), body-fat series per method and
                       device, lean and fat mass, FFMI, ratios, the long-term goal card, ceilings
  BodySchedule         what is due when: weigh-in, weekly sites, full sets, body fat, events
  ProteinMeals         protein per meal: the rule, each meal's fill, the "+18 g to reach 35" hint
  Adherence            one day against its targets, a week's or window's summary and grade
  CheckInEngine        the weekly check-in: input, rules, verdict, proposal, snapshot, phase
                       transition targets
  CoachGlue            the seams between them (weight signal → check-in, composition, schedule)
  CoachBoard           what Today shows: day-type chip, checks strip, at most one coach card,
                       week average line
  CoachReminders       the coach notifications as plain values (times, quiet hours, actions)
  CoachCopy            the "Copy for My AI" text
Shared/                compiled into the app, the Mac app and the watch app
  Model/Models         SwiftData models (CloudKit rules: defaults, optional relationships with
                       inverses, nothing unique; nutrients as one text field so new nutrients need
                       no schema change); BodyMeasurement and DayMark for the coach
  Model/Model+Core     conversions to Core types, NinaSettings (the profile and the plan as plain
                       values: every day's targets and day type)
  Store/NinaStore      every change goes through here: logging, editing, moving, copying, plans,
                       soft delete, save, widget snapshot, change notification, settings import
  Store/NinaStore+Coach  reading and writing body records and day marks, the plan (with its
                       mirror), check-ins and phase decisions – each write returns a CoachUndo
  Store/FoodLibrary    catalog + own foods + recipes merged, search index, usage ranking, quick add
  Store/Persistence    opens the store via BinisoftKit ModelStore (+ the tour's practice store)
  Store/DemoData       sample data for -Demo launches and the tour (in memory, never synced)
  Store/WidgetBridge   today's snapshot in the shared App Group (also compiled into the widgets)
  UI/Rings, Format     ring, nutrient colours and locale-aware formatting (also in the widgets)
App/Sources            iOS + macOS app (targets Nina and NinaMac, one source tree)
  Root                 AppModel (state, actions with Undo toasts, coach actions, deep links),
                       navigation, sheets, commands
  Today                the diary day: week strip, summary ring, meals, entries, water, editors
  Add                  search & quick add, portion picker, quick calories, barcode lookup
  Foods                library (group/sort/filter), detail with nutrition label, editor
  Recipes, Plan        meals & recipes, routines and the week plan
  Insights             Nutrition page: charts, consistency, macros, top foods, rhythm, maintenance;
                       Weigh-ins list and Recently Deleted
  Coach                CoachContext (everything for one day, built in one go); TodayCoach* (chip,
                       checks strip, coach card, protein pills); BodySheets* (weigh-in, measure,
                       body fat); ProgressHome and BodyPage*/BodyDetails (Progress → Body);
                       CheckInSheet*; PhaseSheets* (phase and review); PlanEditor* (My Plan)
  Settings, Import     goals, meals, Health, reminders (incl. Coach), data; import/export with
                       the settings preview
  Services             Apple Health, notifications (meal and coach, with banner actions), App Intents
  Tour                 the tour on the practice day + TipKit hints
Watch/Sources          watch app: today, water, planned meals, dictation, Digital Crown amounts
Widgets/Sources        widgets (iPhone) and complications (watch) from one source, day-type emoji
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

### Coach & body

- **The plan** is one JSON text in `NinaProfile.coachPlan` (`CoachPlan`, sorted keys, `v: 1`):
  day types, phases, long-term goal, protein per meal, daily checks, measuring routine, adjustment
  rules, pauses and notes. New plan fields need no CloudKit change. `plan.isSetUp` (a phase or a
  day type) gates every coach part; without it Nina behaves as before.
- **Targets are dated revisions**: a phase holds `revisions` (from a day: a baseline and targets per
  day type). Check-in adjustments and edits add a revision from tomorrow (or today), so past days
  keep the targets they had and adherence history stays right. A day's targets: the day type's
  targets in the phase active that day, else the phase's baseline, else the profile's.
- **The mirror**: every plan save (`NinaStore.updatePlan`) also writes the running phase's targets,
  goal, pace and target weight into the profile's own fields, so older builds and the widgets show
  near-correct numbers.
- **`BodyMeasurement`** holds what you type: tape values in cm (`waist=84.0;chest=101.5`) or a
  body-fat assessment (method, %, optional lean, fat and bone kg, device), with conditions
  (`morning,fasted`). Weigh-ins stay in `WeightEntry`; reason tags are `#salty` tokens in its note.
- **`DayMark`** is a small record per day: a day type picked by hand (`dayType`), a daily check
  (`check`, `state=done|skipped`), a weekly check-in (`checkIn`, key `week-<Monday>`, the snapshot
  in `values` and the decision in `meta`), a phase decision (`phase`, `event=started|…`) or a day
  event (`event`). The newest live mark per day wins.
- Both are synced and soft-deleted like everything else (30-day trash, Undo toasts). Every coach
  write returns a `CoachUndo` (marks added, trashed and edited, the previous plan) that the toast's
  Undo hands back to `NinaStore.undo`.
- **`CoachContext`** (App/Sources/Coach) gathers everything for one day in one go – plan, marks,
  typed weigh-ins plus the live Apple Health ones, the weight signal, the measuring schedule and
  what is due, the `CoachBoard`, the protein rule, body records, saved check-ins – and with
  `checkIn: true` the week's `CheckInEvaluation`. Views build it in `.task(id:)` keyed on
  `app.dataVersion` and keep it in `@State`.
- **`CoachBoard`** (NinaCore) decides what Today shows from plain values: the day-type chip, one
  checks strip (weigh-in, measurements, daily checks; hidden when nothing is open), at most one
  coach card by priority (phase start/end > review > check-in > baseline > welcome back) and the
  week-average line. "Later" on a card is device-only (`nina.coach.later`).
- **Notifications**: `CoachReminders` (NinaCore) plans the coach notifications as values; the app's
  `NotificationScheduler.reschedule` adds them to the meal reminders on every data change (3-day
  window), re-registers their categories from the plan and removes delivered ones whose task is
  done. Banner actions (Weight…, Waist…, a check done, Tennis today) write through `NinaStore`. By default
  only the iPhone schedules them.
- **Apple Health stays live**: Health weigh-ins count in the weight signal but are never written
  into a mark, a measurement, the plan or a check-in snapshot (a snapshot drops its weight numbers
  when a Health weight was involved and recomputes them live). The tape estimate (US Navy) is
  computed live and never stored either.
- **Device-only settings** (UserDefaults, never synced): `nina.coach.later` (Later taps),
  `nina.coach.reminders.device|off|asked|review` (coach reminders on this device, kinds turned off,
  the one-time question, review times), `nina.coach.measureGuideSeen`, `nina.coach.navyFormula`,
  `nina.coach.copyIncludesHealth`, `nina.body.weightRange`, `nina.body.tip.highCarb`,
  `nina.body.tip.glycogen`.

## Decisions

| Question | Choice | Why |
|---|---|---|
| Food database | USDA SR28 (public domain), curated to ~1,000 foods with EN/DE names | Accurate, complete nutrients, free to bundle; Open Food Facts only for single barcode lookups (ODbL) |
| Nutrients in the model | One encoded text field | New nutrients without CloudKit schema changes; unknown stays unknown |
| Logging speed | Ranked search with usage + quick-add parser | Typing what you ate is faster than tapping through forms, and deterministic (unlike photo AI) |
| Planning | Planned entries confirmed with one tap / from a notification | Logging becomes confirming |
| Health | Write on iPhone only, sync identifiers | No duplicates across devices; guideline 5.1.3 respected |
| Coach plan storage | One JSON text on the profile, plus `BodyMeasurement` and `DayMark` | One CloudKit deploy; new plan fields need none |
| Target history | Dated revisions per phase | Past days keep their targets; check-ins judge each day by what applied then |
| Coach changes | Proposals only: Apply, Start, a review choice – each with Undo | Nothing changes calories or phases without a tap |
| Weight decisions | Morning weights, 7-day average, least-squares pace over 14–21 days, 2 check-ins in a row | Day-to-day swings never move the plan |
| Tape estimate | Computed live from tape, height and sex | Never stored, always follows the latest tape |
| Body fat | Each method and device is its own series | Methods disagree by several points; only like with like is compared |
| Training | Day type and a 1–5 rating only | Training lives in the owner's training app |
