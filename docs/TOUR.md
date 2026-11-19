# Nina – tour

The interactive tour runs the real diary on a separate practice day (in memory, never synced) with
a coach card on top. Each step ticks itself off once the practice page shows it was done.

- Opens by itself **once after install**; after an update that added steps it shows only those as
  **"What's new"**; otherwise never by itself.
- Replay: Settings → Replay the Tour, the ••• menu on iPhone, Help → Nina Tour on the Mac.
- While it is open, Mac menu commands (⌘N, ⌥⌘M …) act on the practice page.
- The practice day has a small made-up plan a week in (Gym on Monday, Wednesday and Friday, Tennis
  twice a week, Rest otherwise, creatine as a daily check, weighed in this morning), so the
  day-type chip, the week strip's menu and the checks strip can be tried. Nothing there touches
  your real plan.

## Steps

The catalog is `Packages/NinaCore/Sources/NinaCore/NinaTour.swift` (version 3). Every step has its
own Mac text (click, right-click, menus and shortcuts instead of tap and touch and hold).

| id | Since | Teaches | Ticks off when |
|---|---|---|---|
| welcome | 1 | what the tour is | – (Continue) |
| create | 1 | the central + | the create sheet opens |
| setup-ai | 2 | the setup prompt for another AI in + → Import My Data | – (Continue) |
| log | 1 | search and add a food | an entry is eaten |
| quick | 1 | type a whole meal like a message | another entry is eaten |
| undo | 1 | delete and Undo | an entry is deleted and restored |
| move | 1 | move an entry to another meal | the meal layout changes |
| plan | 1 | confirm a planned meal | a planned entry is confirmed |
| water | 1 | water in one tap | water goes up |
| daytype | 3 | the day-type chip on the summary card (Mac: also Day → Day Type, ⌃⌘1–⌃⌘4) | today's day type changes |
| plan-ahead | 3 | touch and hold (Mac: right-click) a day in the week strip to pick its type | another day gets a day type |
| checks | 3 | the daily checks strip: tap to tick off, touch and hold for Not Today | a check is ticked done |
| protein | 3 | the protein pill in the meal headers and the "+8 g protein to reach 25" hint in search | – (Continue) |
| weigh-in | 3 | the weigh-in sheet from the strip or + → Weight (Mac: File → Log Weight…), a reason under More | a weigh-in is saved |
| measure | 3 | + → Measurements (Mac: File → Log Measurements…, ⌥⌘M) | a measurement is saved |
| progress | 3 | Progress → Body (Mac: Body in the sidebar, ⌘6) | – (Continue) |
| checkin | 3 | the weekly check-in card, Apply and Undo | – (Continue) |
| everywhere | 1 | sync, watch, widgets, Health | – (Continue) |
| finish | 1 | where to replay | – (Done) |

People who finished version 2 get "What's new" with the eight coach steps (daytype … checkin).

To teach a new feature: add a step with `since: <version + 1>`, bump `NinaTour.version`; people who
took the tour get only the new steps. `swift test` checks the catalog (`NinaTourTests.swift` and the
Tour suite in `DiaryTests.swift`). The practice page builds its snapshot in
`App/Sources/Tour/TourView.swift` (`PracticePage.snapshot`); the practice data is
`DemoData.seedPractice` in `Shared/Store/DemoData.swift`.
