# Nina – setup

The account steps for Nina, from the Binisoft handbook's
[SETUP_CHECKLIST.md](https://github.com/Binisoft-at/binisoft-handbook/blob/main/SETUP_CHECKLIST.md) (private)
with Nina's values. Claude turns them into a numbered claude.ai checklist and ticks steps off.

| | |
|---|---|
| App Store name | **Nina - Your Nutrition Buddy** |
| Home-screen name | Nina |
| GitHub repo | `Binisoft-at/nina` (public) |
| Bundle ID (iOS + macOS) = SKU | `at.binisoft.nina` |
| Watch app | `at.binisoft.nina.watchkitapp` (ships inside the iOS app) |
| Watch complications | `at.binisoft.nina.watchkitapp.widgets` (inside the watch app) |
| Widgets | `at.binisoft.nina.widgets` |
| Own iCloud container | `iCloud.at.binisoft.nina` |
| Shared iCloud container / App Group | `iCloud.at.binisoft.shared` / `group.at.binisoft.shared` (exist – only tick them) |
| Shared keychain group | `$(AppIdentifierPrefix)at.binisoft.shared` (no portal step) |
| Capabilities | iOS + Mac: iCloud (CloudKit, both containers), App Groups, Push Notifications, HealthKit (iOS) · Watch: iCloud, App Groups, Push · Widgets and complications: App Groups |
| iPhone → watch face | Today's numbers go device to device (WatchConnectivity) – no capability, no portal step |
| TestFlight group | `Binisoft Team`, automatic distribution |

All identifiers are defined in [`Config/Base.xcconfig`](../Config/Base.xcconfig).

## Steps

1. **GitHub** – empty public repo `Binisoft-at/nina`; the Claude GitHub app has access to it.
2. **Portal** – iCloud container `iCloud.at.binisoft.nina`; App IDs `at.binisoft.nina` (App Groups,
   iCloud with CloudKit, Push Notifications, HealthKit), `at.binisoft.nina.watchkitapp` (App Groups,
   iCloud, Push), `at.binisoft.nina.widgets` and `at.binisoft.nina.watchkitapp.widgets` (App Groups);
   App Group `group.at.binisoft.shared` and both containers ticked where they apply.
3. **App Store Connect** – "Nina - Your Nutrition Buddy" (iOS + macOS), SKU `at.binisoft.nina`;
   TestFlight → Internal Testing → `Binisoft Team`, automatic distribution.
4. **Repository secrets** – `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
   `CLOUDKIT_MANAGEMENT_TOKEN`.
5. **CloudKit** – Actions → CloudKit schema → Run workflow; then CloudKit Console →
   `iCloud.at.binisoft.nina` → Development → **Deploy Schema Changes** → Deploy.
   Until this is done, TestFlight builds keep data on each device (Settings shows "Not syncing").
6. **TestFlight** – a commit with `[testflight]`, a `v*` tag, or Actions → TestFlight → Run workflow.
   Build number = workflow run number; builds show up in TestFlight 5–30 minutes after upload
   (Actions → App Store Connect status).

## After a model change

`Shared/Model/Models.swift` → `python3 tools/cloudkit-schema.py` (rewrites `cloudkit/schema.ckdb`) →
CloudKit schema workflow → Deploy Schema Changes to Production → TestFlight.
New fields are optional or have a default; never rename or remove a synced field.

## Rebuilding the food catalog

`python3 scripts/build_food_db.py --sr28 <folder with the USDA SR28 txt files>` – see
[data/README.md](../data/README.md).

## Local development

```bash
make check                                             # no Mac needed: Core tests + syntax check
cp Config/Local.xcconfig.example Config/Local.xcconfig # set DEVELOPMENT_TEAM (Mac, signed runs)
make open                                              # generates Nina.xcodeproj with XcodeGen
```

CI results without the Actions logs: `git fetch origin ci-output && git show origin/ci-output:ci/status.txt`
(also `ci-testflight`, `ci-cloudkit`; screenshots under `ci/shots/` after a `[screenshots]` run).
