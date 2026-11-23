# Nina – tour

The interactive tour runs the real diary on a separate practice day (in memory, never synced) with
a coach card on top. Each step ticks itself off once the practice page shows it was done.

- Opens by itself **once after install**; after an update that added steps it shows only those as
  **"What's new"**; otherwise never by itself.
- Replay: Settings → Replay the Tour, the ••• menu on iPhone, Help → Nina Tour on the Mac.
- While it is open, Mac menu commands (⌘N, ⇧⌘M …) act on the practice page.
- The practice day has a small made-up plan a week in (Gym on Monday, Wednesday and Friday, Tennis
  twice a week, Rest otherwise, creatine as a daily check, weighed in this morning), so the
  day-type chip, the week strip's menu and the checks strip can be tried. Nothing there touches
  your real plan.

## Steps

The catalog is `Packages/NinaCore/Sources/NinaCore/NinaTour.swift` (version 6). Every step has its
own Mac text (click, right-click, menus and shortcuts instead of tap and touch and hold).

| id | Since | Teaches | Ticks off when |
|---|---|---|---|
| welcome | 1 | what the tour is | – (Continue) |
| create | 1 | Create… in the ⋯ menu at the top of Today (Mac: the Create button in the toolbar, ⇧⌘N) | the create sheet opens |
| setup-ai | 2 | the setup prompt for another AI in ⋯ → Create… → Import My Data (Mac: Create → Import My Data) | – (Continue) |
| log | 1 | search and add a food | an entry is eaten |
| quick | 1 | type a whole meal like a message | another entry is eaten |
| recentsPerMeal | 6 | the Recent list follows the meal being logged: "Mostly at breakfast" first, then the rest, newest first (Mac: ⌘N; the watch's Log list too) | – (Continue) |
| undo | 1 | delete and Undo | an entry is deleted and restored |
| move | 1 | move an entry to another meal | the meal layout changes |
| plan | 1 | confirm a planned meal | a planned entry is confirmed |
| water | 1 | water in one tap | water goes up |
| daytype | 3 | the day-type chip on the summary card (Mac: also Day → Day Type, ⌃⌘1–⌃⌘4) | today's day type changes |
| plan-ahead | 3 | touch and hold (Mac: right-click) a day in the week strip to pick its type | another day gets a day type |
| planDayTypes | 6 | in the Plan tab, each of the next 7 days shows its day type's emoji: tap it to change the type, Back to Schedule, Undo (Mac: Plan, ⌘4; click the emoji or right-click the day → Day Type) | – (Continue) |
| checks | 3 | the daily checks strip: tap to tick off, touch and hold for Not Today | a check is ticked done |
| protein | 3 | the protein pill in the meal headers and the "+8 g protein to reach 25" hint in search | – (Continue) |
| weigh-in | 3 | the weigh-in sheet from the strip or ⋯ → Create… → Weight (Mac: File → Log Weight…), a reason under More | a weigh-in is saved |
| measure | 3 | ⋯ → Create… → Measurements (Mac: File → Log Measurements…, ⇧⌘M): one site per page, last time's value already there, −/+ by 0.1 cm, Done | a measurement is saved |
| progress | 3 | Progress → Body (Mac: Body in the sidebar, ⌘6) | – (Continue) |
| checkin | 3 | the weekly check-in card and its four steps (your week, waist, how it went, next week), Apply and Undo | – (Continue) |
| photos | 4 | progress photos: Progress → Body → Photos → Take Photos (Mac: Body → Photos → Add Photos), the last photo faintly over the camera, Compare, the Face ID lock in the card's ⋯ menu | – (Continue) |
| watchCoach | 4 | the coach on Apple Watch: today's day type under the ring, weigh-in and waist with the Digital Crown, daily checks, the weight status | – (Continue) |
| watchHealth | 6 | the watch shows the iPhone's weight numbers, Apple Health weigh-ins included; a scale weigh-in this morning hides Weigh in; open Nina on the iPhone after weighing (Mac: the iPhone passes them on directly, the Mac can't read Health) | – (Continue) |
| healthBody | 4 | Settings → Apple Health → Body: body fat, lean mass and waist from Health as their own series, and "Make it a tennis day?" after a workout (Mac: the workouts of a day type in My Plan) | – (Continue) |
| history | 4 | importing old weigh-ins, tape logs and scan reports: ⋯ → Create… → Import My Data → Body (Mac: File → Import & Export…, ⇧⌘I), only what's new, one Undo | – (Continue) |
| thalia | 6 | Nina hands Thalia the day's calories, protein, carbs, fat, water and morning weight on this device; one switch for all devices in Settings → Thalia → An Thalia liefern (Mac: Settings, ⌘, → General → Thalia). Was version 5's step; it comes back with the new texts | – (Continue) |
| backup | 6 | Settings → Import & Export → Back Up Everything (one folder with all of Nina's data, nothing from Apple Health) and Move to Day… on an entry (Mac: File → Back Up Nina…, ⇧⌘B; Search in the sidebar, ⇧⌘F; on Today ⌫ deletes the selected entries; ⌘C, then ⌘V on another day copies them; right-click → Move to Day…) | – (Continue) |
| autobackup | 6 | the weekly backup: once a week, the last 4 kept, in Files → On My iPhone → Nina or a folder from Choose Folder… (iPad: switch on Back Up Automatically Every Week; Mac: off until switched on, Show in Finder, ⇧⌘B still works) | – (Continue) |
| siri | 6 | Siri and Shortcuts ("Log weight in Nina", "Today is a Tennis day in Nina", "Mark Creatine done in Nina", also in German) and the Control Center controls Log Food, Weigh In and Add Water (Mac: Siri and the Shortcuts app) | – (Continue) |
| coachWidget | 6 | the Coach widget: day type, 7-day average and weekly rate, next measurement, open checks (Mac: points to the iPhone) | – (Continue) |
| menubar | 6 | the names Today and Progress → Nutrition, now the same on the Mac; Nina in the Mac menu bar (Mac: Today ⌘1, Nutrition ⌘5, the menu bar with calories left, protein, water, a glass of water, Log Food…, Weigh In…; off in Settings, ⌘, → General → Menu Bar) | – (Continue) |
| everywhere | 1 | sync, watch, widgets, Health | – (Continue) |
| finish | 1 | where to replay | – (Done) |

People who finished version 5 (on TestFlight) or version 4 get "What's new" with the nine version 6
steps, in tour order: recentsPerMeal, planDayTypes, watchHealth, thalia (shown again with the
morning weight and the one switch), backup, autobackup, siri, coachWidget and menubar. People who
finished version 3 also get the four version 4 steps (photos, watchCoach, healthBody, history);
people who finished version 2 also get the eight coach steps (daytype … checkin). Every version 6
step is read-only (Continue): the practice page has no backup, Siri, widget, watch or menu bar.

## Coach parts without their own step

These are easy to find from the steps above, so the tour only points the way. They are explained
in [BODY.md](BODY.md):

- **The check-in** (from the checkin step): four steps – your week with the pace as a bar against
  your phase's range, the waist typed right in the check-in, how it went with optional ratings,
  and next week. **Copy for My AI** on the last step puts your plan and the last 4 weeks on the
  clipboard for your AI.
- **The measure pages** (from the measure step): one site per page with **Next** and **Skip**, −/+
  by 0.1 cm, **Same as Last Time**; a site's own page on Progress → Body has **Measure Waist** (or
  that site) for just that site, and the link `nina://measure?mode=waist` (any site) does the same.
- **Phases**: the pace range is one slider with two handles; a gain phase can have an optional
  body-fat ceiling that asks for a review; after a gain of more than 12 weeks with a fat-loss phase
  next, the review offers a 1–2 week maintenance bridge first.
- **Reminders**: the morning notification takes the weight (Weight…) and, on a day the weekly
  waist is due, the waist too (Waist…). "Turn on coach reminders?" is asked once per device when a
  plan is first set up.
- **Photos** (from the photos step): the timer, Skip, picking from the library, Compare's Side by
  Side, Fade and Slider, the full-screen viewer and Recently Deleted.
- **Watch, Health and history** (from their steps): the version 4 steps are read-only, because the
  practice page has no watch, no Health data and no file to import. [BODY.md](BODY.md),
  [HEALTH.md](HEALTH.md) and [IMPORT.md](IMPORT.md) have the details.
- **Set your goal**: new people see a small card on Today until their goal is set (Not Now = a
  week, Don't Show Again = for good on that device). It is for new people only, so it has no
  "What's new" step ([BODY.md](BODY.md)).
- **Siri, controls and the widget** (from the siri and coachWidget steps): every phrase, the
  controls and the widget's taps are in [SIRI.md](SIRI.md).

To teach a new feature: add a step with `since: <version + 1>`, bump `NinaTour.version`; people who
took the tour get only the new steps. `swift test` checks the catalog (`NinaTourTests.swift` and the
Tour suite in `DiaryTests.swift`). The practice page builds its snapshot in
`App/Sources/Tour/TourView.swift` (`PracticePage.snapshot`); the practice data is
`DemoData.seedPractice` in `Shared/Store/DemoData.swift`.
