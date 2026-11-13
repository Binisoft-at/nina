<p align="center"><img src="design/icon-1024.png" width="128" alt="Nina icon"></p>

# Nina – Your Nutrition Buddy

App Store name **Nina - Your Nutrition Buddy** · home-screen name **Nina** · bundle ID `at.binisoft.nina`

Nina is the Binisoft template app: a small list app for iPhone, iPad, Mac and Apple Watch with a
widget. It exists so that every new Binisoft app starts with the same structure, the same CI and the
same building blocks. `tools/new-app.sh` in the [Binisoft handbook](https://github.com/Binisoft-at/binisoft-handbook)
copies it and renames everything.

## What's in it

- **Items in folders** – add, edit, check off, reorder, swipe actions, context menus, Recently Deleted
  (30 days) with Undo on every delete, ⌘Z and shake to undo.
- **One central +** – everything you can create, plus "Import my data".
- **Import & export** – your own CSV directly, the AI import (copy a prompt → any AI writes the CSV →
  preview → import, safe to repeat) and a CSV export. Format: [docs/IMPORT.md](docs/IMPORT.md).
- **Interactive tour** – runs on a practice page, steps tick themselves off, opens once after install,
  later only "What's new"; replay from Settings and Help → Nina Tour. See [docs/TOUR.md](docs/TOUR.md).
- **TipKit hints**, **in-app log with "Copy log"**, **Settings** with iCloud sync status and
  "Where your data lives".
- **iPhone/iPad**: tab bar (sidebar on iPad) with a bottom accessory. **Mac**: split view, menu
  commands, keyboard shortcuts. **Apple Watch**: open items, check off, add by voice. **Widget**: what's next.
- **Sync**: SwiftData in the private database of `iCloud.at.binisoft.nina`. No server, no account.
- Liquid Glass for floating controls only, content on plain cards, one accent colour, light/dark/system.

## Repo layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen spec. `Nina.xcodeproj` is generated, never committed |
| `Makefile` | `make test`, `make check`, `make generate`, `make build-ios`, `make build-mac`, `make build-watch`, `make open` |
| `Config/` | `Base.xcconfig` (every identifier), `ci.env` (CI settings), Info.plist + entitlements per platform |
| `Packages/NinaCore` | All logic that needs no Apple frameworks (CSV, import plan, tour catalog, widget summary). Swift Testing, runs on Linux |
| `Shared/` | SwiftData models, the store every change goes through, persistence, demo data, widget bridge |
| `App/Sources`, `App/Resources` | iOS + macOS app (one source tree, two targets) |
| `Watch/` | Apple Watch app (embedded in the iOS app) |
| `Widgets/` | Home and Lock Screen widgets |
| `Vendor/BinisoftKit` | Shared Binisoft kit – synced from the handbook, never edited here |
| `scripts/ci`, `.github/workflows` | CI – synced from the handbook, never edited here |
| `cloudkit/schema.ckdb` | CloudKit schema (imported by the CloudKit schema workflow) |
| `docs/` | [SETUP](docs/SETUP.md), [ARCHITECTURE](docs/ARCHITECTURE.md), [IMPORT](docs/IMPORT.md), [TOUR](docs/TOUR.md) |
| `.binisoft-handbook` | The handbook version this app follows |

## Build and check

```bash
make check      # no Mac: Core tests (Docker swift:6.2-noble or a toolchain) + syntax of the app code
make test       # Core tests with a local Swift
make open       # Mac: generate the project and open Xcode
```

To run signed on your own devices, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`
and set `DEVELOPMENT_TEAM`.

## CI and TestFlight

- **CI** (every push to `main`, PRs): Core tests on Linux, then unsigned macOS and iOS builds (with
  the watch app and widgets). `[screenshots]` in the commit message adds simulator screenshots.
  Results: `git fetch origin ci-output && git show origin/ci-output:ci/status.txt`.
- **TestFlight** (manual, `v*` tag, or `[testflight]` in the commit message): archive, check
  entitlements, upload; build number = run number. Results on the `ci-testflight` branch.
- **CloudKit schema** (manual): imports `cloudkit/schema.ckdb` into Development; then deploy to
  Production in the CloudKit Console.
- **App Store Connect status** (manual): processing state of the latest builds.

Setup (portal, App Store Connect, secrets, CloudKit): [docs/SETUP.md](docs/SETUP.md).
