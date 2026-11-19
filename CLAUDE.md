# Working on Nina

Nina ("Nina - Your Nutrition Buddy") is a calorie and nutrition diary for iPhone, iPad, Mac and
Apple Watch: SwiftUI, SwiftData + CloudKit, Liquid Glass, iOS/macOS/watchOS 26. It follows the
Binisoft handbook (`.binisoft-handbook`, private repo `Binisoft-at/binisoft-handbook`).

The owner sends corrections and features, in German or English, often as a list. The job: build
them, verify them, and get them onto TestFlight. The owner touches nothing except the one CloudKit
click below and the occasional account step you ask for.

## Layout

- `App/Sources`: iPhone/iPad/Mac app. `Shared/`: SwiftData models (`Shared/Model/Models.swift`),
  `NinaStore` (every change to data goes through it), `FoodLibrary` (search over catalog + own
  foods + recipes). Shared with the watch and widgets.
- `Watch/Sources`: watch app. `Widgets/Sources`: iOS widgets and watch complications (one file).
- `Packages/NinaCore`: platform-free logic with Swift Testing tests: nutrients, search, quick-add
  parser ("2 eggs and a toast"), goals, insights, CSV import formats, Open Food Facts parsing, the
  tour. Put anything testable here. `Resources/foods.json` is the bundled catalog (1,079 foods).
- Coach & body: the plan is JSON in `NinaProfile.coachPlan` (`CoachPlan.swift`, edits in
  `PlanEdits.swift`); tape and body fat are `BodyMeasurement`, day types, check ticks, check-ins
  and phase decisions are `DayMark` (read and written in `Shared/Store/NinaStore+Coach.swift`, each
  write returns a `CoachUndo`). NinaCore: `WeightSignal`, `Body`, `BodyComposition`,
  `BodySchedule`, `ProteinMeals`, `Adherence`, `CheckInEngine`, `CoachGlue`, `CoachBoard` (what
  Today shows), `CoachReminders`, `CoachCopy`, `SettingsCSV+Plan` (the plan in the import).
  App: `App/Sources/Coach/` – `CoachContext` (one day's coach data in one go), `TodayCoach*`,
  `BodySheets*`, `ProgressHome`, `BodyPage*`, `BodyDetails`, `CheckInSheet*`, `PhaseSheets*`,
  `PlanEditor*`. Demo coach data: `DemoCoach` in `Shared/Store/DemoData.swift` (made-up numbers).
- `project.yml` (XcodeGen) generates the Xcode project; never committed. All identifiers live in
  `Config/Base.xcconfig`; entitlements use its variables.
- `cloudkit/schema.ckdb` is generated from the models: `python3 tools/cloudkit-schema.py`
  (`--check` verifies it matches).
- Catalog: `scripts/build_food_db.py` builds `foods.json` from USDA SR28 + `data/` (see
  `data/README.md`). 19 foods marked `label` have approximate values.
- Synced from the handbook, never edit here: `Vendor/BinisoftKit`, `scripts/ci`,
  `.github/workflows`. Change them in the handbook and run its `tools/sync.sh`.
- Owner docs: `README.md`, `docs/SETUP.md`, `docs/IMPORT.md` (CSV formats and the AI prompts),
  `docs/BODY.md` (measuring, the check-in, phases, coach reminders), `docs/HEALTH.md`,
  `docs/TOUR.md`, `docs/ARCHITECTURE.md`.

## The loop (no Mac in the session)

1. Change the code. Logic goes into NinaCore with tests.
2. `make check`: Core tests plus `swiftc -parse` of the app code. It needs Docker
   (`swift:6.2-noble`) or a Swift 6.2 toolchain. If `docker info` fails in a cloud session,
   start the daemon first:
   `sudo -E env HTTPS_PROXY=$HTTPS_PROXY HTTP_PROXY= NO_PROXY=$NO_PROXY nohup dockerd >/tmp/dockerd.log 2>&1 &`
   then `sudo chmod 666 /var/run/docker.sock`.
3. Commit to `main` and push (no pull requests). Put `[screenshots]` in the message to get
   simulator screenshots (light and dark) of the screens in `Config/ci.env`.
4. Read CI with git (about 20–30 minutes, Linux tests then GitHub's free Macs):
   `git fetch origin ci-output && git show origin/ci-output:ci/status.txt` names the run and the
   commit. Also `ci/errors.txt` (compiler errors), `ci/core-tests.log`, `ci/shots/*.png`.
   Poll in the background until `status.txt` names the pushed commit. Pushing again cancels a
   running build, so batch fixes.
5. Fix and repeat until green. Look at the screenshots of anything that changed visibly. New
   screens get a case in `AppModel.applyLaunchOptions` (`-Demo -DemoScreen <name>`) and an entry
   in `SCREENSHOT_SCREENS` in `Config/ci.env`.
6. Ship: once the last commit is green, push an empty commit whose message contains `[testflight]`:
   `git commit --allow-empty -m "Release: <what's in it> [testflight]" && git push -u origin main`.
   The result is on the `ci-testflight` branch (`status.txt`); build number = run number. Builds
   reach the owner's TestFlight ("Binisoft Team", automatic distribution) 10–30 minutes later.
   App Store Connect status:
   `gh api -X POST repos/Binisoft-at/nina/actions/workflows/asc-status.yml/dispatches -f ref=main`,
   then `git show origin/ci-output:asc/status.txt`. (Sessions can start workflows with this REST
   call; `gh workflow run` needs GraphQL, which sessions can't use.)
7. Reply in the handbook's format (HOW_WE_WORK section 6): what was built, where it is in the app,
   TestFlight build number, what to try, the owner's next steps, open questions as A/B options,
   verified vs. not verified.

## CloudKit schema: the one manual step

TestFlight and App Store builds sync through CloudKit **Production**, and only a person can deploy
the schema there.

- Avoid schema changes. New nutrients need none (nutrients are stored as text,
  `NutrientValues.encoded`). Prefer an existing text field over a new one when it fits.
- A real model change: edit `Shared/Model/Models.swift` (new attributes need defaults,
  relationships stay optional with inverses, never `@Attribute(.unique)`, never rename or delete),
  run `python3 tools/cloudkit-schema.py`, push, then start the import:
  `gh api -X POST repos/Binisoft-at/nina/actions/workflows/cloudkit-schema.yml/dispatches -f ref=main`
  and read `git show origin/ci-cloudkit:status.txt`.
- Before the TestFlight build that uses it, ask the owner to deploy:
  https://icloud.developer.apple.com/dashboard → CloudKit Database → `iCloud.at.binisoft.nina` →
  Development → Deploy Schema Changes… → Deploy.

## Data rules

- Each app keeps its data in its own container (`iCloud.at.binisoft.nina`). Only small cross-app
  summaries may go to `iCloud.at.binisoft.shared` / `group.at.binisoft.shared`; never the schema.
- No Apple Health data in iCloud (guideline 5.1.3(ii)). Values read from Health (weight, active
  energy) are shown live; the record of what Nina wrote to Health stays on the device
  (`HealthLedger`, not synced).
- Open Food Facts (ODbL) is only queried at runtime for barcodes; never bundle its data.
- The repository is public: no secrets, personal food logs or tester emails in commits, tests or
  CI output. Demo and test data are made up.

## Conventions and pitfalls

- Swift 5 language mode. `#Predicate` captures plain local values (`let key = day.rawValue`) and
  arrays, not sets or properties of `self`. `#expect` can't take mutating calls; compute first.
- Deleting is soft (`deletedAt`, 30-day trash) and every destructive action shows a toast with Undo.
- New gestures or features go into the tour (`Packages/NinaCore/.../NinaTour.swift`): a step with
  `since: version + 1`, then bump `version`, so existing users get "What's new".
- UI text is English; food names follow the food-language setting (English or German), with
  Austrian names as aliases (Paradeiser, Semmel, Topfen …).
- No model names in commits, code or docs. Commits end with
  `Co-Authored-By: Claude <noreply@anthropic.com>` and the session's `Claude-Session:` line.
- Write for the owner in plain words: exact links and clicks, no jargon.
