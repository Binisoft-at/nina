# Nina → Thalia (Binisoft exchange, format v1)

Thalia (Binisoft's planner, 1.9.0 or newer) can show the day's calories, protein, carbs, fat,
water and morning weight from Nina next to its own measures. Nina hands them over as small files
on the same device; Thalia picks them up the next time it opens there. No network, no server, no
permission prompt.

## What Nina delivers

One value per day and metric – the same number Today shows:

| Metric | Unit | Title in the file | What counts |
|---|---|---|---|
| `kcal` | kcal | Kalorien | eaten entries of the day that have a calorie value |
| `protein_g` | g | Protein | eaten entries of the day that have a protein value |
| `carbs_g` | g | Kohlenhydrate | eaten entries of the day that have a carbs value |
| `fat_g` | g | Fett | eaten entries of the day that have a fat value |
| `water_ml` | ml | Wasser | the day's water logs (the number on Today's water card) |
| `body_weight_kg` | kg | Gewicht | the day's morning weigh-in in Nina (see below) |

- **A metric no entry of the day has a value for is left out that day.** Example: you log only
  "500 kcal" quick entries – Thalia gets calories, but no protein, carbs or fat for that day. Entries
  with a value count (their sum); a 0 you entered (a coffee with 0 g fat) stays 0.
- A day without water logs has no water value; a day without a weigh-in has no weight.
- **Weight**: the day's morning weigh-in by Nina's morning rule – the earliest weigh-in of the diary
  day before the morning cutoff of your plan (11:00 unless you changed it), and if there is none
  before it, the day's earliest. Every weigh-in saved in Nina counts – typed on any device, logged
  on the watch or from a notification, and imported history. To 0.1 kg; its time is that weigh-in's time.
- Planned, skipped and deleted entries never count. Body measurements, fiber and the rest are not
  sent.
- In Thalia, a measure with the source `app:nina:kcal` (or `app:nina:protein_g`, …,
  `app:nina:body_weight_kg`) shows the day's value; an own entry in Thalia for that day wins.

## Where the files go

The shared App Group `group.at.binisoft.shared`, Nina's own folder:

```
<group>/Nina/exchange/source.json             Nina, its version and the six metrics
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
- `source.json` is written at once when the metrics or Nina's version change (the first pass after
  this update writes it with six metrics), otherwise once a day.
- Writing never slows down Nina, and never shows an error – problems go to the app log
  (Settings → Diagnostics → App Log). A file that can't be written doesn't stop the others; the
  next pass tries it again.

## What never goes there

- **Apple Health**: Nina doesn't import foods, water or weights from Health. The weight Nina shows
  from Health (a scale that writes to Health) is read live and never stored, so it never reaches
  Thalia – only weigh-ins saved in Nina do. The active energy Nina reads from Health is never added.
  Should a record from Health ever exist, it is left out.
- **Demo and practice data**: not in `-Demo` launches, the tour's practice day, previews, tests,
  or when Nina runs on a temporary in-memory store.
- **Apple Watch**: the watch neither reads nor writes these files.

## Settings

Settings → **Thalia** (in German, by your choice): the switch **An Thalia liefern** (on by default),
the line "Zuletzt geschrieben: 22. Nov. 2030, 21:15" ("Noch nichts geschrieben", "Aus") and the hint
"Thalia übernimmt die Werte, sobald Thalia auf diesem Gerät geöffnet wird."

**One switch for all your devices.** It syncs through iCloud with your other settings: turn it off
on the iPhone and it is off on the iPad and the Mac too. Each device then empties its files of the
last 62 days once (Thalia removes the values) and writes nothing more – only files older than 62
days are still deleted, once a day. `source.json` stays, so Thalia still lists Nina. Turning it on
writes everything again at once on that device, and on the others as soon as they get the change
(when Nina opens or iCloud brings it). Settings → iCloud & Data → Where your data lives explains it
under "Thalia".

If you had turned it off on a device before this update, that "off" now counts for all devices
(once, the first time Nina opens there after the update).

## Decisions

1. **Thalia section in German** (your choice "B deutsch"): header "Thalia", toggle "An Thalia
   liefern", "Zuletzt geschrieben: <Datum, Zeit>" (Austrian German date) / "Noch nichts geschrieben"
   / "Aus", footer "Thalia übernimmt die Werte, sobald Thalia auf diesem Gerät geöffnet wird." The
   rest of Nina stays English. The titles inside the files are German too (Kalorien, Protein,
   Kohlenhydrate, Fett, Wasser, Gewicht) – they are data for Thalia.
2. **One switch for all devices** (your choice "immer so dass auf allen Geräten alles funktioniert"):
   stored in the synced profile as `NinaProfile.syncedSettings`, a small JSON text
   (`{"thaliaDeliver":false,"v":1}`) that later settings can join without another iCloud schema
   change. Read leniently; keys a newer Nina adds are kept when an older one writes. The old
   per-device switch (`nina.thalia.deliver`) is moved in once: an "off" there becomes the synced
   "off" when the profile has no value yet; then the old key is removed. A device without a profile
   yet (the synced one still on its way) keeps its old value until there is one. Per device stay:
   the time of the last write and "already emptied" (`nina.thalia.lastWritten`, `nina.thalia.cleared`).
3. **The day of a value is Nina's diary day** of the entry (your choice A: `LogEntry.day`,
   `WaterLog.day`, `WeightEntry.day` – it already follows "Day starts at"). `at` is the time of the
   latest record of that day that has a value for the metric (for the weight: the chosen weigh-in),
   in the device's time zone, cut to the whole second (iCloud keeps times to the millisecond, so
   rounding could differ between devices). Days after today are skipped.
4. **What counts** (your choice B): eaten entries only (`EntryStatus.eaten`, as Today's totals count
   them: not planned, not skipped, not deleted). Per metric only the entries that have a value for it
   (`NutrientValues` keeps "no value" apart from 0); a metric no entry of the day has a value for is
   left out. Water = the sum of the day's water logs (Today's water card). A record from Apple Health
   never counts.
5. **Body weight** (your choice "A am besten auch immer abgleich"): `body_weight_kg` (Thalia sums
   nothing here: the latest value of the day counts, and Nina sends one). Nina's morning rule as for
   the 7-day average (`WeightSignal`), weigh-ins 25–300 kg only, from Nina's own weigh-ins
   (`WeightEntry`: typed, watch, notification, imported) – never Apple Health samples, never
   anything read from HealthKit. Id `body_weight_kg-<day>`.
6. **Rounding**, so every device writes identical bytes: kcal and ml to whole numbers, grams and kg
   to 0.1. One value per metric and day, id `<metric>-<day>` (`kcal-2026-11-22`), kind `value`,
   `ref` = the metric, German `refTitle`, `unit`, `origin` `app`. Sums run in a fixed order, two
   weigh-ins in the same second are told apart by their id, and the facts are sorted by (`at`, `id`).
7. **Switched off, `source.json` stays** (decided): Thalia keeps listing Nina, without values.
8. **Never written** in demo (`-Demo`), the tour's practice day (`isSandbox`), from an in-memory
   or fallback store (`AppModel.keepsData`, `isStoredInMemoryOnly`), in SwiftUI previews
   (`XCODE_RUNNING_FOR_PREVIEWS`), in tests, or on the watch (App/Sources isn't in the watch target,
   and the file is `#if !os(watchOS)`).
9. **Version**: `appVersion` in `source.json` is the app's version (`CFBundleShortVersionString`,
   `MARKETING_VERSION`, 1.1.0 since the first Thalia build).
10. **Tour**: the read-only step "thalia" (since 5) stays; the new parts (weight, one switch for all
    devices) get a "What's new" step with the next tour version.

## Code

- `Packages/NinaCore/Sources/NinaCore/ExchangeFormat.swift` – Thalia's reference file, copied
  unchanged (format types, reader, dates, FNV-1a).
- `Packages/NinaCore/Sources/NinaCore/ThaliaFeed.swift` – what Nina delivers: the six metrics, the
  refs, the day values from plain records (food, water, weigh-ins with the morning rule),
  `source.json`, and the German status line.
- `Packages/NinaCore/Sources/NinaCore/SyncedSettings.swift` – the synced settings (lenient JSON,
  unknown keys kept, versioned) and the switch rule with the move of the old device switch.
- `Packages/NinaCore/Sources/NinaCore/ThaliaExchangeWriter.swift` – writing the day files (only
  changed ones, atomically, old ones deleted) and `source.json`.
- `App/Sources/Services/ThaliaExchange.swift` – the App Group folder (on the Mac only when the
  signed app has the group), Thalia's catalog, the Darwin notification `at.binisoft.exchange.changed`,
  and `ThaliaDelivery`, which follows the synced switch and runs the passes.
- `App/Sources/Settings/ThaliaSettingsSection.swift` – Settings → Thalia.
- `Shared/Model/Models.swift` (`NinaProfile.syncedSettings`), `Shared/Store/NinaStore.swift`
  (`syncedSettings()`, `updateSyncedSettings`), `Shared/Model/Model+Core.swift`
  (`NinaSettings.synced`).
- Tests: `Packages/NinaCore/Tests/NinaCoreTests/ThaliaExchangeTests.swift` (with Thalia's fixtures)
  and `SyncedSettingsTests.swift`.

## For Bini

- **Once, before the TestFlight build with this change**: deploy the iCloud schema (the profile got
  the new field `syncedSettings`): https://icloud.developer.apple.com/dashboard → CloudKit Database →
  `iCloud.at.binisoft.nina` → Development → Deploy Schema Changes… → Deploy.
- The App Group `group.at.binisoft.shared` must be on the App ID `at.binisoft.nina` (iPhone, iPad
  and Mac share it) in the developer portal. The widgets (`at.binisoft.nina.widgets`) already use
  it; the watch doesn't need it.
- `source.json` delivers 6 refs, all of kind `metric`.
- In Thalia: link a measure to `app:nina:kcal`, `app:nina:protein_g`, `app:nina:carbs_g`,
  `app:nina:fat_g`, `app:nina:water_ml` or `app:nina:body_weight_kg`.

## Answered questions

1. Switch per device or for all devices? → **for all devices** (one synced setting).
2. A metric without values on a day? → **B**: left out that day; a real 0 stays 0.
3. A snack at 1:00 with "Day starts at 3:00"? → **A**: Nina's diary day, as Today shows it.
4. `source.json` when switched off? → **A**: it stays.
5. Language of the Thalia section? → **German**.
6. The weight too? → **yes**, the morning weigh-in as `body_weight_kg`.
