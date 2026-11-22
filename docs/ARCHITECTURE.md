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
  WatchCoach           the coach on Apple Watch: day-type chip, checks row (weigh-in, weekly
                       tape, daily checks), Digital Crown values, the status line in the phone's words
  HealthBody           Apple Health body data as series of their own: body fat (with lean mass)
                       per source app and the method it counts as, waist, the height hint
  HealthWorkouts       a finished Health workout → which day type it suggests ("Make it a tennis day?")
  HealthWeightSync     which weigh-ins the iPhone writes to Health on its sync (saved on the watch,
                       iPad or Mac; edits and deletions follow; imported ones never)
  BodyHistoryCSV       the weight & body history import and export (weigh-ins, tape, body fat; one
                       row = one moment), its AI prompt, re-import adds nothing
  ProgressPhotos       photo poses, the session order, image sizes, what Compare shows (the pair of
                       days, the days between, 7-day average weight and waist on each day)
  -- Binisoft exchange --
  ExchangeFormat       Thalia's reference file, copied unchanged: format v1 types, tolerant reader,
                       dates without fractions, FNV-1a
  ThaliaFeed           what Nina hands Thalia: the five metrics and their refs, one total per metric
                       and day from plain records, source.json, Thalia's catalog (read only)
  ThaliaExchangeWriter the day files of the last 62 days (only changed ones, atomically, old ones
                       deleted) and source.json (on changes, else once a day)
Shared/                compiled into the app, the Mac app and the watch app
  Model/Models         SwiftData models (CloudKit rules: defaults, optional relationships with
                       inverses, nothing unique; nutrients as one text field so new nutrients need
                       no schema change); BodyMeasurement and DayMark for the coach;
                       ProgressPhoto (the photo and its thumbnail with external storage, synced as
                       CKAssets; app only – the watch's store leaves it out, Persistence.models)
  Model/Model+Core     conversions to Core types, NinaSettings (the profile and the plan as plain
                       values: every day's targets and day type)
  Store/NinaStore      every change goes through here: logging, editing, moving, copying, plans,
                       soft delete, save, widget snapshot, change notification, settings import
  Store/NinaStore+Coach  reading and writing body records and day marks, the plan (with its
                       mirror), check-ins and phase decisions – each write returns a CoachUndo
  Store/NinaStore+History  the weight & body history: Nina's own weigh-ins and measurements as
                       BodyHistoryRecord, the import plan and the import (imported weigh-ins get
                       the #import tag), the export – never Apple Health values
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
                       CheckInSheet*; PhaseSheets* (phase and review); PlanEditor* (My Plan);
                       BodyPhotos* (progress photos: card, camera, session, compare, viewer, lock,
                       store helpers, demo); HealthBodyPage/HealthBodyViews (Health on the body
                       page, the workout hint under Today's chip, the height hint)
  Settings, Import     goals, meals, Health (incl. the Body switches), reminders (incl. Coach),
                       data; import/export with the settings preview; ImportHistory (the history
                       preview lines and the Import & Export menu of All measurements)
  Services             Apple Health (HealthService; HealthService+Body reads body fat, lean mass,
                       waist, height and today's workouts live), notifications (meal and coach,
                       with banner actions), App Intents, ThaliaExchange (the App Group folder,
                       the Mac entitlement check, ThaliaDelivery: the passes for Thalia)
  Tour                 the tour on the practice day + TipKit hints
Watch/Sources          watch app: today, water, planned meals, dictation, Digital Crown amounts;
                       the coach (WatchModel+Coach: one load for the day and the writes with Undo;
                       WatchCoachViews: chip, checks, Crown screens, status line)
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
  Weigh-ins saved on the watch, iPad or Mac are written by the iPhone on its sync
  (`HealthWeightSync`): once, found again if already there, removed when edited, deleted or gone
  from the window; the ledger remembers them. Weight samples carry the sync identifier
  `nina.weight.<uuid>` + version, so two devices or passes never write one twice. Every weight write
  asks `HealthWeightSync.writes` first: weigh-ins whose note has the `#import` tag are never written.
- **Apple Health body data** (iPhone and iPad, `HealthBodyReader` in HealthService+Body): body fat,
  lean mass, waist, height and today's workouts are read live when their switch is on and kept in
  memory. They become series of their own (`HealthBody`), never merged into Nina's records or the
  goal; a workout only offers a day type (`HealthWorkouts`) and the person's tap writes the mark.
- **Sync**: SwiftData + CloudKit private database of `iCloud.at.binisoft.nina`; the watch syncs on its
  own. The shared App Group only holds today's snapshot for widgets and complications and the
  day values for Thalia (below).

### The exchange with Thalia

Binisoft exchange, format v1 (owner doc: [THALIA.md](THALIA.md)). Each app writes only its own
folder of the shared App Group `group.at.binisoft.shared` on the device it runs on; Thalia reads
them when it opens there.

- **Files**: `<group>/Nina/exchange/source.json` (source `nina`, app `Nina`, the app version, the
  five metrics as refs of kind `metric`) and `days/<YYYY-MM-DD>.json` – one `value` fact per metric
  and day: `kcal`, `protein_g`, `carbs_g`, `fat_g` (eaten entries, `EntryStatus.eaten` as Today's
  totals count them) and `water_ml` (the day's water logs, Today's water card). Id
  `<metric>-<day>`, German `refTitle`, `origin` `app`, kcal and ml whole, grams to 0.1, `at` = the
  day's latest record of the metric. The day is the entry's diary day.
- **Passes** (`ThaliaDelivery`, App/Sources/Services/ThaliaExchange.swift): after every own save
  (`.ninaDataChanged`, 2 s of quiet), at the end of the own CloudKit import
  (`NSPersistentCloudKitContainer.eventChangedNotification`, an import with an end date), when the
  app comes to the foreground, at the day change and when the switch changes; the first one 5 s
  after launch. A pass reads the last 62 days on the main actor into plain values
  (`ThaliaFeed.FoodRecord`, `.WaterRecord`); building the facts, writing and the Darwin notification
  `at.binisoft.exchange.changed` (once per pass that wrote something) run in a detached task.
  `ThaliaExchangeWriter.sync` writes a day only when its facts changed (compared without
  `generatedAt`), gives a day that lost its facts `"facts":[]`, and deletes files older than 62
  days. Errors only go to the app log.
- **Where it never runs**: the watch (App/Sources isn't in its target, and the file is
  `#if !os(watchOS)`), `-Demo`, the tour's practice store, an in-memory or fallback store
  (`AppModel.keepsData`, `isStoredInMemoryOnly`), SwiftUI previews and tests. On the Mac the
  folder is used only when the signed app has the group (`SecTaskCopyValueForEntitlement`, checked
  once, off the main thread); without the group (unsigned builds) nothing is written.
- **The switch** "Send to Thalia" is per device (`nina.thalia.deliver`, default on), because the
  synced profile has no free settings field. Off: one pass without facts empties the window's day
  files, then nothing more (`nina.thalia.cleared`) except deleting files older than 62 days once a
  day; on: a full pass at once.
- **Same bytes on every device**: the diary day as stored, sums in id order, kcal/ml whole and grams
  to 0.1, `at` cut to the whole second (iCloud keeps dates to the millisecond), facts by (`at`,
  `id`), sorted keys. A file that can't be written doesn't stop the others
  (`ThaliaExchangeWriter.SyncFailure` says whether anything was written, so the notification still
  goes out).
- **No Apple Health values**: Nina doesn't import foods or water from Health; a record from Health
  (`ThaliaFeed.isHealthSource`) would never count, and active energy is never added.

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
- **Progress photos** (`ProgressPhoto`): JPEGs at most 2048 px without location or camera
  metadata, plus a 360 px thumbnail, both external storage (CKAssets in the private database).
  Soft-deleted like everything else (Recently Deleted, 30 days). The watch's store doesn't have the
  model, so the watch never downloads them.
- **History import** (`BodyHistoryCSV`, `NinaStore+History`): each row becomes up to three records
  (weigh-in, tape, body fat). Measurements keep an import key, and a record of the same kind on the
  same day with the same values counts as already saved, so importing again adds nothing. One Undo
  trashes what the import added.
- **Device-only settings** (UserDefaults, never synced): `nina.coach.later` (Later taps),
  `nina.coach.reminders.device|off|asked|review` (coach reminders on this device, kinds turned off,
  the one-time question, review times), `nina.coach.measureGuideSeen`, `nina.coach.navyFormula`,
  `nina.coach.copyIncludesHealth`, `nina.body.weightRange`, `nina.body.tip.highCarb`,
  `nina.body.tip.glycogen`, `nina.health.body.bodyFat|waist|workouts` (the Body switches),
  `nina.health.body.labels` (the method per Health app), `nina.photos.lock`,
  `nina.photos.afterFullSet`, `nina.thalia.deliver|lastWritten|cleared` (Send to Thalia, the last
  write, the day files emptied after switching off).

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
| Thalia | Day totals per metric in the shared App Group, rebuilt from the synced store for 62 days on every trigger; switch per device | Every device writes the same bytes; no CloudKit schema change |
| Tape estimate | Computed live from tape, height and sex | Never stored, always follows the latest tape |
| Body fat | Each method and device is its own series | Methods disagree by several points; only like with like is compared |
| Training | Day type and a 1–5 rating only | Training lives in the owner's training app |
| Health body data | Read live as series of their own, never stored | Guideline 5.1.3(ii); methods and devices disagree, so they are never mixed with Nina's own values |
| Progress photos | A SwiftData model with external storage, app only | Private iCloud only (not the photo library); the watch doesn't need them |
| Weigh-ins from other devices to Health | The iPhone writes them on its sync, imported ones never | One device writes, so nothing reaches Health twice; history may already be in Health from the scale |
