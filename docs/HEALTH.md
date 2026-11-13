# Nina – Apple Health, data and privacy

## What goes where

| Data | Where it lives | Who can read it |
|---|---|---|
| Diary, own foods, meals, recipes, routines, water, weigh-ins typed in Nina, goals | SwiftData on each device, synced through the user's **private** iCloud database (`iCloud.at.binisoft.nina`) | Only the user's Apple Account |
| Built-in food catalog | In the app bundle | Everyone (public data) |
| Today's numbers for widgets and complications | `group.at.binisoft.shared/Nina/today.json` on each device | Nina's widgets on that device |
| Apple Health values (weight, active energy) | Read live from HealthKit on each device, kept in memory only | Never stored or synced by Nina |
| What Nina wrote to Health | A device-only ledger file (entry id → version) in Application Support | Nina on that device |
| App log | Application Support on each device | The user (Settings → Diagnostics → Copy log) |

No servers, accounts or analytics. App Store guideline 5.1.3(ii) – no Health data in iCloud – is
respected: Nina writes *its own* diary to Health, and reads Health values only live.

## Writing to Apple Health (iPhone)

Settings → Apple Health → turn on what to share:

- **Meals and nutrients** – every eaten entry of the last 14 days as a *food* correlation with all
  known nutrients (energy, protein, carbs, fat, fiber, sugar, saturated/mono/poly fat, cholesterol,
  sodium, potassium, calcium, iron, magnesium, zinc, vitamins A, C, D, E, B12, folate, caffeine).
  Each correlation carries a sync identifier and a version: editing an entry replaces it, deleting or
  un-eating it removes it. Planned and skipped entries are not written.
- **Water** – each water log.
- **Weight** – weigh-ins typed in Nina are written; weigh-ins from the scale are read for the trend.
- **Active energy** – read to show "budget incl. activity" when you choose to add half or all of it.

Only the iPhone writes, so entries from the Mac or the watch reach Health once the iPhone has synced
them (usually within seconds when Nina is open).

## Barcode lookups

Scanning sends **only the barcode number** to Open Food Facts (`world.openfoodfacts.org`), with a
user agent naming the app. The answer is shown for review; nothing is saved until the user saves it.
Open Food Facts data is under the Open Database License (ODbL), © Open Food Facts contributors.
