# Nina → Thalia (Binisoft exchange, format v1)

Thalia (Binisoft's planner, 1.9.0 or newer) can show the day's calories, protein, carbs, fat and
water from Nina next to its own measures. Nina hands them over as small files on the same device;
Thalia picks them up the next time it opens there. No network, no server, no permission prompt.

## What Nina delivers

One value per day and metric – the day's total, the same number Today shows:

| Metric | Unit | Title in the file | What counts |
|---|---|---|---|
| `kcal` | kcal | Kalorien | eaten entries of the day (always kcal, also when Nina shows kJ) |
| `protein_g` | g | Protein | eaten entries of the day |
| `carbs_g` | g | Kohlenhydrate | eaten entries of the day |
| `fat_g` | g | Fett | eaten entries of the day |
| `water_ml` | ml | Wasser | the day's water logs (the number on Today's water card) |

- A day with no eaten entries has no calorie, protein, carbs or fat value; a day without water
  logs has no water value. A real 0 (entries, but 0 g fat) is sent as 0.
- Planned, skipped and deleted entries never count. Weight, body data, fiber and the rest are not
  sent.
- In Thalia, a measure with the source `app:nina:kcal` (or `app:nina:protein_g` …) shows the day's
  value; an own entry in Thalia for that day wins.

## Where the files go

The shared App Group `group.at.binisoft.shared`, Nina's own folder:

```
<group>/Nina/exchange/source.json             Nina, its version and the five metrics
<group>/Nina/exchange/days/2026-11-22.json    one file per day: that day's values
```

Nina writes only there. It may read Thalia's `<group>/Thalia/exchange/catalog.json`, but uses
nothing from it (no category choice in Nina). The App Group is a folder on one device, so Nina
writes on every iPhone, iPad and Mac it runs on – always from its synced diary, so every device
writes the same numbers.

## When it writes

- A few seconds after every change in Nina, right after changes from your other devices arrive
  through iCloud, when Nina comes to the front, and at midnight.
- Each time it works out the last 62 days and rewrites only the days whose numbers changed (also
  older days you edit, and both days when an entry moves to another day). A day that had values
  and now has none gets an empty file, so Thalia removes them. Files older than 62 days are deleted.
- `source.json` is written when the metrics or Nina's version change, otherwise once a day.
- Writing never slows down Nina, and never shows an error – problems go to the app log
  (Settings → Diagnostics → App Log).

## What never goes there

- **Apple Health**: Nina doesn't import foods or water from Health, and the active energy it reads
  from Health is never added. Should a record from Health ever exist, it is left out.
- **Demo and practice data**: not in `-Demo` launches, the tour's practice day, previews, tests,
  or when Nina runs on a temporary in-memory store.
- **Apple Watch**: the watch neither reads nor writes these files.

## Settings

Settings → **Thalia**: the switch **Send to Thalia** (on by default), the line "Last written: …"
("Not written yet", "Off on this device") and the hint "Thalia picks up the values as soon as you
open Thalia on this device." The switch is per device. Turning it off empties the files of the
last 62 days once (Thalia removes the values) and then writes nothing more; turning it on writes
everything again at once. Settings → iCloud & Data → Where your data lives explains it under
"Thalia".

## Decisions

1. **UI text in English** (Nina's rule): section "Thalia", toggle "Send to Thalia" (default on),
   "Last written: <date, time>" / "Not written yet" / "Off on this device", footer "Thalia picks up
   the values as soon as you open Thalia on this device." The titles inside the files stay German
   (Kalorien, Protein, Kohlenhydrate, Fett, Wasser) – they are data for Thalia.
2. **The switch is per device** (UserDefaults `nina.thalia.deliver`, default on): the synced
   profile has no free settings field, and a new field would need a CloudKit schema change. Off:
   one pass with no values (every existing day file of the window gets `"facts":[]`), then no more
   writes and no heartbeat until it is on again. On: a full pass at once.
3. **The day of a value is Nina's diary day** of the entry (`LogEntry.day`, `WaterLog.day` – it
   already follows "Day starts at"). `at` is the time of the latest entry of that day that counts
   for the metric, in the device's time zone, without fractions. Days after today are skipped.
4. **What counts**: eaten entries only (`EntryStatus.eaten`, as Today's totals count them: not
   planned, not skipped, not deleted); energy in kcal, protein, carbs and fat in g, unknown values
   as 0 (like Today's totals). Water = the sum of the day's water logs (Today's water card). A
   record from Apple Health never counts – today no food or water record in Nina comes from Health.
5. **Rounding**, so every device writes identical bytes: kcal and ml to whole numbers, grams to
   0.1. One value per metric and day, id `<metric>-<day>` (`kcal-2026-11-22`), kind `value`,
   `ref` = the metric, German `refTitle`, `unit`, `origin` `app`.
6. **Never written** in demo (`-Demo`), the tour's practice day, from an in-memory or fallback store
   (`AppModel.keepsData`), in SwiftUI previews, in tests, or on the watch.
7. **Version 1.1.0** (`MARKETING_VERSION`); `appVersion` in `source.json` is the app's version.
8. **Tour**: one read-only step "thalia" (since 5), tour version 5.

## Code

- `Packages/NinaCore/Sources/NinaCore/ExchangeFormat.swift` – Thalia's reference file, copied
  unchanged (format types, reader, dates, FNV-1a).
- `Packages/NinaCore/Sources/NinaCore/ThaliaFeed.swift` – what Nina delivers: the metrics, the
  refs, the day values from plain records, `source.json` and its heartbeat rule.
- `Packages/NinaCore/Sources/NinaCore/ThaliaExchangeWriter.swift` – writing the day files (only
  changed ones, atomically, old ones deleted) and `source.json`.
- `App/Sources/Services/ThaliaExchange.swift` – the App Group folder (on the Mac only when the
  signed app has the group), Thalia's catalog, the Darwin notification `at.binisoft.exchange.changed`,
  and `ThaliaDelivery`, which runs the passes.
- Tests: `Packages/NinaCore/Tests/NinaCoreTests/ThaliaExchangeTests.swift` with Thalia's fixtures.

## For Bini

- The App Group `group.at.binisoft.shared` must be on the App ID `at.binisoft.nina` (iPhone, iPad
  and Mac share it) in the developer portal. The widgets (`at.binisoft.nina.widgets`) already use
  it; the watch doesn't need it.
- In Thalia: link a measure to `app:nina:kcal`, `app:nina:protein_g`, `app:nina:carbs_g`,
  `app:nina:fat_g` or `app:nina:water_ml`.

## Open questions

1. Switch per device or for all devices? A) per device, as now (recommended – no iCloud schema
   change) B) one switch for all devices (a new synced field: needs "Deploy Schema Changes").
2. An entry without a protein (carbs, fat) value counts as 0 – A) as now, like Today's totals
   (recommended) B) leave the metric out of a day where no entry has a value.
3. A snack at 1:00 with "Day starts at 3:00" counts for the day before – A) Nina's diary day, as
   Today shows it (recommended) B) the calendar day of the time.
4. When switched off, `source.json` stays (Thalia still lists Nina, without values) – A) keep it
   (recommended) B) delete it too.
