# Nina – architecture

```
Packages/NinaCore   logic without Apple frameworks: CSV format, import plans, tour catalog,
                       widget summary. Swift Testing, runs on Linux in CI.
Shared/                compiled into the app, the Mac app and the watch app:
  Item, Folder         SwiftData models (CloudKit rules: defaults, optional relationships with inverses, nothing unique)
  ItemStore            every change goes through here: order, timestamps, soft delete, save, widget snapshot
  Persistence          opens the store via BinisoftKit ModelStore (+ the tour's practice store)
  DemoData             sample data for -Demo launches and the tour (in-memory, never synced)
  WidgetBridge         the small snapshot in the shared App Group (also compiled into the widgets)
App/Sources            iOS + macOS app (targets Nina and NinaMac, one source tree)
  AppModel             UI state: tab / sidebar, the one sheet, toasts, tour, launch arguments
  RootView             iPhone/iPad tab bar with bottom accessory; Mac split view; sheets; tour
  ItemListView         Items / Done / Recently Deleted, swipe actions, context menus, empty states
  Editors              item and folder editors, the central "+" sheet
  ImportView           own CSV, AI import (prompt → CSV → preview → import), export
  SettingsView         appearance, tour, hints, iCloud & data, import/export, app log, version
  TourView             the tour: ItemListView on the practice store + the coach card
Watch/Sources          watch app: open items, check off, add by voice (syncs on its own)
Widgets/Sources        "Open items" widget (Home Screen, Lock Screen)
Vendor/BinisoftKit     shared kit (synced from the handbook)
```

## Data and sync

- SwiftData, `ModelConfiguration("Nina", groupContainer: .none, cloudKitDatabase:
  .private("iCloud.at.binisoft.nina"))` – the container name comes from Info.plist
  (`AppCloudKitContainer`), set from `Config/Base.xcconfig`.
- Debug builds push the full CloudKit schema once; `cloudkit/schema.ckdb` is the same schema for
  the CloudKit schema workflow.
- Without iCloud (unsigned CI builds, no entitlement) the same store runs on the device only;
  Settings → iCloud & Data says so.
- The watch app uses the same models and store code and syncs through the same container.
- The shared App Group only gets `Nina/snapshot.json` (open count, next titles) for the widget.
- Deleting moves items to Recently Deleted (30 days); every delete shows Undo; ⌘Z and shake work for
  every change because the window's undo manager is attached to the model context.

## Design

Native SwiftUI on iOS/macOS/watchOS 26. Liquid Glass only for floating controls (bottom accessory,
toasts, tour coach); content on plain lists and cards. One accent colour (AccentColor asset, from
the icon) for primary actions. Appearance System / Light / Dark.

## Launch arguments (screenshots in CI)

`-Demo` (sample data in memory) with `-DemoScreen items|done|trash|search|create|new|edit|import|settings`,
`-Tour`, `-TourStep <id>`, `-ResetTour`. The screens CI captures are listed in `Config/ci.env`.
