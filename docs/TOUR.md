# Nina – tour

The interactive tour runs the real diary on a separate practice day (in memory, never synced) with
a coach card on top. Each step ticks itself off once the practice page shows it was done.

- Opens by itself **once after install**; after an update that added steps it shows only those as
  **"What's new"**; otherwise never by itself.
- Replay: Settings → Replay the Tour, the ••• menu on iPhone, Help → Nina Tour on the Mac.
- While it is open, Mac menu commands (⌘N …) act on the practice page.

## Steps

The catalog is `Packages/NinaCore/Sources/NinaCore/NinaTour.swift` (version 1):

| id | Teaches | Ticks off when |
|---|---|---|
| welcome | what the tour is | – (Continue) |
| create | the central + | the create sheet opens |
| log | search and add a food | an entry is eaten |
| quick | type a whole meal like a message | another entry is eaten |
| undo | delete and Undo | an entry is deleted and restored |
| move | move an entry to another meal | the meal layout changes |
| plan | confirm a planned meal | a planned entry is confirmed |
| water | water in one tap | water goes up |
| everywhere | sync, watch, widgets, Health | – (Continue) |
| finish | where to replay | – (Done) |

To teach a new feature: add a step with `since: <version + 1>`, bump `NinaTour.version`; people who
took the tour get only the new steps. `swift test` checks the catalog.
