# Nina – Apple Health, data and privacy

## What goes where

| Data | Where it lives | Who can read it |
|---|---|---|
| Diary, own foods, meals, recipes, routines, water, weigh-ins typed in Nina, goals | SwiftData on each device, synced through the user's **private** iCloud database (`iCloud.at.binisoft.nina`) | Only the user's Apple Account |
| Coach plan (phases, day types, daily checks, measuring routine, long-term goal, notes) | In the profile, synced the same way | Only the user's Apple Account |
| Body measurements typed in Nina (tape, body fat), day types picked by hand, check ticks, saved check-ins, phase decisions | SwiftData (`BodyMeasurement`, `DayMark`), synced the same way | Only the user's Apple Account |
| Progress photos (front, side, back) – Nina's own data, not Health data | SwiftData (`ProgressPhoto`), the photo and its thumbnail as files in Nina's private iCloud database; not in iCloud Photos, not on the watch | Only the user's Apple Account |
| Built-in food catalog | In the app bundle | Everyone (public data) |
| Today's numbers for widgets and complications | `group.at.binisoft.shared/Nina/today.json` on each device | Nina's widgets on that device |
| The day totals for Thalia (calories, protein, carbs, fat, water of the last 62 days – from Nina's own diary, never from Health) | `group.at.binisoft.shared/Nina/exchange/` on each iPhone, iPad and Mac (not the watch), while Settings → Thalia → Send to Thalia is on | Thalia and Nina on that device |
| Apple Health values (weight, active energy) | Read live from HealthKit on each device, kept in memory only | Never stored or synced by Nina |
| Apple Health body values (body fat, lean mass, waist, height) and today's workouts | Read live from HealthKit on iPhone and iPad, kept in memory only | Never stored or synced by Nina |
| What Nina wrote to Health | A device-only ledger file (entry id → version, and the weigh-ins it wrote) in Application Support | Nina on that device |
| The Body switches (Settings → Apple Health → Body), the "Body fat from" labels, "Not now" on a workout hint | UserDefaults on that device | Nina on that device |
| Coach settings of one device (coach reminders on or off, "Later" on a card, chart range, tips seen, the tape formula when sex isn't set, "Include Apple Health weights", "Lock Photos with Face ID", "Then add progress photos") | UserDefaults on that device | Nina on that device |
| App log | Application Support on each device | The user (Settings → Diagnostics → Copy log) |

No servers, accounts or analytics. App Store guideline 5.1.3(ii) – no Health data in iCloud – is
respected: Nina writes *its own* diary to Health, and reads Health values only live.

## Thalia gets no Apple Health values

The day totals Nina hands Thalia ([THALIA.md](THALIA.md)) come only from what you log in Nina:
eaten entries and water logs. Thalia keeps what it receives in its iCloud, so nothing from Health
may go there: Nina doesn't import foods or water from Health, the active energy it reads from
Health is never added, and weight and body data aren't sent at all. Should a record from Health
ever exist in Nina, it is left out.

## The coach and Apple Health

- **Weigh-ins from your scale or another app** count live: in the 7-day average, the pace, the
  unusual-reading check and the weekly check-in. They are never copied into Nina's data – not into
  a measurement, a day mark, the plan or a saved check-in. A saved check-in leaves its weight
  numbers out when a Health weigh-in was part of them and works them out again live.
- **The weigh-in list** (Progress → Body → All weigh-ins) shows Health weigh-ins with a heart; they
  can't be edited or deleted in Nina.
- **Weigh-ins typed in Nina** – in the weigh-in sheet or in the morning notification's Weight… field
  – are written to Health when weight sharing is on (Settings → Apple Health).
- **Copy for My AI**, **Export Goals & Plan** and **Copy Export** (Goals & Plan → My Plan), and the
  goals & settings export and prompts in Import & Export, only go where you send them. They include
  Health weigh-ins only when "Include Apple Health weights" is switched on (iPhone and iPad; off by
  default, remembered on that device); otherwise the weight in them is your latest weigh-in typed
  in Nina.
- **Tape and body fat** are typed (or imported) in Nina. The tape estimate of body fat is worked out
  live from them and never stored. More in [BODY.md](BODY.md).
- **Imported history** (past weigh-ins from an import, see [IMPORT.md](IMPORT.md)) shows as
  "Imported" in the weigh-in list and is never written to Health – it may be there already from the
  scale it came from.

## Body data from Apple Health (iPhone and iPad)

Settings → Apple Health → **Body** has three switches: **Body fat and lean mass**, **Waist** and
**Workouts suggest the day type**. They are set on each device. iOS asks for permission when you
first turn one on; if you said no, allow it in the Health app: your picture → Apps → Nina.

- **Body fat and lean mass** from your scale or another app show in Progress → Body → Body
  composition as a series per app, marked Health. They count as **Smart scale** unless you change
  it under **Body fat from** (for example an app that writes your DEXA results → DEXA scan), so the
  chart draws the right error band. They are never mixed with what you type in Nina and never drive
  goal progress or the check-in.
- **Waist** from Health shows on the Waist tile and under your tape readings as its own series.
- **Height**: Goals & Plan → Body & Calculator shows "Health: 176 cm" under your height as a hint.
  Set your height with the stepper; nothing from Health is copied into your profile.
- **Workouts suggest the day type**: when today is your default day and Health has a finished
  workout that a day type lists (My Plan → a day type → Apple Health workouts, for example tennis or
  strength), Today shows "🎾 Tennis workout found · Make it a tennis day?" under the chip. Only your
  tap changes the day (with Undo in the message); × hides it for today. If two day types fit, the
  one with more calories is offered.

## Writing to Apple Health (iPhone)

Settings → Apple Health → turn on what to share:

- **Meals and nutrients** – every eaten entry of the last 14 days as a *food* correlation with all
  known nutrients (energy, protein, carbs, fat, fiber, sugar, saturated/mono/poly fat, cholesterol,
  sodium, potassium, calcium, iron, magnesium, zinc, vitamins A, C, D, E, B12, folate, caffeine).
  Each correlation carries a sync identifier and a version: editing an entry replaces it, deleting or
  un-eating it removes it. Planned and skipped entries are not written.
- **Water** – each water log.
- **Weight** – weigh-ins typed in Nina are written; weigh-ins from the scale are read live for the
  trend and the coach. Weigh-ins you save on the watch, iPad or Mac are written by your iPhone on its
  next sync, once (editing or deleting one there updates or removes it in Health too, and so does
  moving it more than 14 days back). Each weigh-in carries a sync identifier, so Health keeps it
  once even when your iPhone and iPad both write it. Imported history is never written to Health –
  not when you edit it, restore it from Recently Deleted or undo either.
- **Active energy** – read to show "budget incl. activity" when you choose to add half or all of it.

Only the iPhone writes, so entries from the Mac or the watch reach Health once the iPhone has synced
them (usually within seconds when Nina is open).

## Barcode lookups

Scanning sends **only the barcode number** to Open Food Facts (`world.openfoodfacts.org`), with a
user agent naming the app. The answer is shown for review; nothing is saved until the user saves it.
Open Food Facts data is under the Open Database License (ODbL), © Open Food Facts contributors.
