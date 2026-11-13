# Nina – tour

The interactive tour runs the real Items screen on a separate practice store (in memory, never
synced) with a coach card on top. Each step ticks itself off once the practice page shows it was done.

- Opens by itself **once after install**; after an update that added steps it shows only those as
  **"What's new"**; otherwise never by itself.
- Replay: Settings → Replay the Tour, the ••• menu on iPhone, Help → Nina Tour on the Mac.
- While it is open, Mac menu commands (⌘N …) act on the practice page.

## Steps

The catalog is `Packages/NinaCore/Sources/NinaCore/NinaTour.swift`:

| id | Teaches | Ticks off when |
|---|---|---|
| welcome | – | Let's Go |
| create | the central + | the create sheet is open |
| add | New Item | an item was added |
| done | check off | an item is done |
| undo | delete + Undo | an item went to the trash and came back |
| reorder | drag to reorder | the order changed |
| edit | the editor | the editor is open |
| everywhere | sync, Mac, watch, widget, Settings | Continue |
| finish | where to replay | Done |

## Adding a step for a new feature

1. Add a `TourStep` with `since: NinaTour.version + 1` at the end of its topic, with a `body`
   (touch) and a `macBody` (pointer, menus, shortcuts) and a goal over `NinaTourSnapshot`
   (add a field there if needed and fill it in `TourView.PracticePage.snapshot`).
2. Bump `NinaTour.version`.
3. `make check` – the Core tests check the catalog.
4. People who took the tour before see only the new steps as "What's new".
