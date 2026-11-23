import Testing
import BinisoftKitCore
@testable import NinaCore

/// The coach steps of tour version 3 (day types, daily checks, protein per meal, weigh-in,
/// measurements, Progress, check-in), the steps of version 4 (progress photos, the coach on the
/// watch, body data from Apple Health, importing the weight & body history) and version 6: recents
/// per meal, day types in the Plan tab, the iPhone's Health numbers on the watch, Thalia (one switch
/// for all devices, now with the morning weight – version 5's step, shown again), backing up
/// everything and moving entries to another day, the weekly backup, Siri and controls, the Coach
/// widget, and the Mac's names and menu bar. Version 5 (Thalia alone) is on TestFlight.
@Suite("Coach tour")
struct CoachTourTests {
    static let coachSteps = ["daytype", "plan-ahead", "checks", "protein", "weigh-in", "measure", "progress", "checkin"]
    static let versionFourSteps = ["photos", "watchCoach", "healthBody", "history"]
    /// Version 5's only step (Thalia) moved to version 6 with its new texts.
    static let versionFiveSteps: [String] = []
    static let versionSixSteps = ["recentsPerMeal", "planDayTypes", "watchHealth", "thalia", "backup", "autobackup",
                                  "siri", "coachWidget", "menubar"]

    @Test func versionThreeAddsTheCoachSteps() {
        let ids = NinaTour.catalog.steps.filter { $0.since == 3 }.map(\.id)
        #expect(ids == Self.coachSteps)
        for step in NinaTour.catalog.steps where step.since == 3 {
            #expect(step.macBody != step.body, "\(step.id) needs its own Mac text")
            #expect(!step.macBody.isEmpty)
        }
    }

    @Test func versionFourAddsPhotosWatchHealthAndHistory() {
        let ids = NinaTour.catalog.steps.filter { $0.since == 4 }.map(\.id)
        #expect(ids == Self.versionFourSteps)
        for step in NinaTour.catalog.steps where step.since == 4 {
            #expect(step.macBody != step.body, "\(step.id) needs its own Mac text")
            #expect(!step.macBody.isEmpty)
            #expect(step.goal.isManual, "\(step.id) is read-only: nothing on the practice page to tick it off")
        }
    }

    /// Thalia (version 5) comes back in version 6: the morning weight too, and one switch for all
    /// devices (Settings → Thalia → An Thalia liefern).
    @Test func thaliaComesBackWithTheWeightAndOneSwitch() throws {
        #expect(NinaTour.catalog.steps.filter { $0.since == 5 }.isEmpty)
        let step = try #require(NinaTour.catalog.steps.first { $0.id == "thalia" })
        #expect(step.since == 6)
        #expect(step.goal.isManual, "read-only: the practice page has no Thalia")
        #expect(step.macBody != step.body)
        #expect(step.body.contains("morning weight"))
        #expect(step.body.contains("One switch for all your devices: Settings → Thalia → An Thalia liefern"))
        #expect(step.macBody.contains("Settings (⌘,) → General → Thalia → An Thalia liefern"))
    }

    /// Version 6: Back Up Everything and Move to Day…; on the Mac also Search in the sidebar,
    /// ⌫ for the selected entries and ⌘C / ⌘V. Every version 6 step is read-only with its own
    /// Mac text.
    @Test func versionSixAddsBackupMoveAndFind() throws {
        #expect(NinaTour.version == 6)
        let ids = NinaTour.catalog.steps.filter { $0.since == 6 }.map(\.id)
        #expect(ids == Self.versionSixSteps)
        for step in NinaTour.catalog.steps where step.since == 6 {
            #expect(step.goal.isManual, "\(step.id) is read-only: nothing on the practice page to tick it off")
            #expect(step.macBody != step.body, "\(step.id) needs its own Mac text")
            #expect(!step.macBody.isEmpty)
        }
        let step = try #require(NinaTour.catalog.steps.first { $0.id == "backup" })
        #expect(step.body.contains("Settings → Import & Export → Back Up Everything"))
        #expect(step.body.contains("in one folder"))
        #expect(step.body.contains("Move to Day…"))
        #expect(step.macBody.contains("File → Back Up Nina… (⇧⌘B)"))
        #expect(step.macBody.contains("in one folder"))
        #expect(step.macBody.contains("Search in the sidebar (⇧⌘F)"))
        #expect(step.macBody.contains("On Today, ⌫"))
        #expect(step.macBody.contains("⌘C"))
        #expect(step.macBody.contains("Move to Day…"))
    }

    /// The round's new things, each where it really is.
    @Test func versionSixTextsNameThePathsThatExist() throws {
        let byID = Dictionary(uniqueKeysWithValues: NinaTour.catalog.allSteps.map { ($0.id, $0) })
        let backup = try #require(byID["autobackup"])
        #expect(backup.body.contains("keeps the last 4"))
        #expect(backup.body.contains("On My iPhone → Nina"))
        #expect(backup.body.contains("Choose Folder…"))
        #expect(backup.macBody.contains("Back Up Automatically Every Week"))
        #expect(backup.macBody.contains("off on the Mac"))
        #expect(byID["recentsPerMeal"]?.body.contains("\u{201C}Mostly at breakfast\u{201D}") == true)
        #expect(byID["planDayTypes"]?.body.contains("Back to Schedule") == true)
        #expect(byID["planDayTypes"]?.macBody.contains("Plan (⌘4)") == true)
        #expect(byID["siri"]?.body.contains("Log weight in Nina") == true)
        #expect(byID["siri"]?.body.contains("Heute ist ein Tennistag in Nina") == true)
        #expect(byID["siri"]?.body.contains("Add a Control → Nina") == true)
        #expect(byID["coachWidget"]?.body.contains("Coach widget") == true)
        #expect(byID["coachWidget"]?.macBody.contains("On your iPhone") == true)
        #expect(byID["watchHealth"]?.macBody.contains("can't read Apple Health") == true)
        let menuBar = try #require(byID["menubar"])
        #expect(menuBar.macBody.contains("Today (⌘1)"))
        #expect(menuBar.macBody.contains("Nutrition (⌘5)"))
        #expect(menuBar.macBody.contains("Settings (⌘,) → General → Menu Bar"))
        #expect(menuBar.body.contains("Progress → Nutrition"))
        // Nina is kcal only, its Mac pages are Today and Nutrition, and Back Up Everything is a folder.
        for step in NinaTour.catalog.allSteps {
            for text in [step.body, step.macBody] {
                #expect(!text.contains("kJ"), "\(step.id) names kJ")
                #expect(!text.contains("Insights"), "\(step.id) names Insights")
                #expect(!text.contains("In the diary"), "\(step.id) names the old Mac page")
                #expect(!text.contains("one file"), "\(step.id): a backup is a folder")
            }
        }
    }

    /// What's new keeps the tour's order, so the version 6 steps sit next to their topics
    /// (recents after logging, day types in Plan after planning ahead, the watch's Health numbers
    /// after the watch coach).
    @Test func peopleWhoTookVersionTwoSeeTheCoachAndTheNewerSteps() {
        let ids = NinaTour.catalog.steps(newerThan: 2).map(\.id)
        let newer: [String] = ["recentsPerMeal", "daytype", "plan-ahead", "planDayTypes", "checks", "protein", "weigh-in",
                               "measure", "progress", "checkin", "photos", "watchCoach", "watchHealth", "healthBody", "history",
                               "thalia", "backup", "autobackup", "siri", "coachWidget", "menubar"]
        #expect(ids == ["whats-new"] + newer + ["finish"])
        let all: [String] = Self.coachSteps + Self.versionFourSteps + Self.versionFiveSteps + Self.versionSixSteps
        #expect(Set(newer) == Set(all))
    }

    @Test func peopleWhoTookVersionThreeSeeTheVersionFourFiveAndSixSteps() {
        let ids = NinaTour.catalog.steps(newerThan: 3).map(\.id)
        let newer: [String] = ["recentsPerMeal", "planDayTypes", "photos", "watchCoach", "watchHealth", "healthBody", "history",
                               "thalia", "backup", "autobackup", "siri", "coachWidget", "menubar"]
        #expect(ids == ["whats-new"] + newer + ["finish"])
        let all: [String] = Self.versionFourSteps + Self.versionFiveSteps + Self.versionSixSteps
        #expect(Set(newer) == Set(all))
    }

    @Test func peopleWhoTookVersionFourSeeTheVersionSixSteps() {
        let ids = NinaTour.catalog.steps(newerThan: 4).map(\.id)
        #expect(ids == ["whats-new"] + Self.versionFiveSteps + Self.versionSixSteps + ["finish"])
    }

    /// Version 5 is on TestFlight: those testers get the version 6 steps as "What's new" – Thalia
    /// again, with its new texts.
    @Test func peopleWhoTookVersionFiveSeeTheVersionSixSteps() {
        let ids = NinaTour.catalog.steps(newerThan: 5).map(\.id)
        #expect(ids == ["whats-new"] + Self.versionSixSteps + ["finish"])
        #expect(NinaTour.catalog.steps(newerThan: 6).isEmpty)
    }

    @Test func firstRunHasEverythingInOrder() {
        let everything = NinaTour.catalog.steps(newerThan: 0).map(\.id)
        #expect(everything.first == "welcome")
        #expect(everything.last == "finish")
        #expect(everything.contains("daytype"))
        for id in Self.versionFourSteps { #expect(everything.contains(id)) }
        // The coach steps come after the diary steps, the version 4 steps after the check-in, and
        // all of them before "everywhere".
        let water = everything.firstIndex(of: "water") ?? 0
        let daytype = everything.firstIndex(of: "daytype") ?? 0
        let checkin = everything.firstIndex(of: "checkin") ?? 0
        let photos = everything.firstIndex(of: "photos") ?? 0
        let history = everything.firstIndex(of: "history") ?? 0
        let thalia = everything.firstIndex(of: "thalia") ?? 0
        let backup = everything.firstIndex(of: "backup") ?? 0
        let everywhere = everything.firstIndex(of: "everywhere") ?? 0
        #expect(water < daytype)
        #expect(daytype < checkin)
        #expect(checkin < photos)
        #expect(photos < history)
        #expect(history < thalia)
        #expect(thalia < backup)
        #expect(backup < everywhere)
        // Version 6 steps sit next to their topic: recents after the logging steps, day types in
        // Plan after planning ahead, the watch's Health numbers after the watch coach, the rest
        // before "everywhere".
        func at(_ id: String) -> Int { everything.firstIndex(of: id) ?? -1 }
        #expect(at("quick") < at("recentsPerMeal") && at("recentsPerMeal") < at("undo"))
        #expect(at("plan-ahead") < at("planDayTypes") && at("planDayTypes") < at("checks"))
        #expect(at("watchCoach") < at("watchHealth") && at("watchHealth") < at("healthBody"))
        #expect(backup < at("autobackup") && at("autobackup") < at("siri") && at("siri") < at("coachWidget"))
        #expect(at("coachWidget") < at("menubar") && at("menubar") < everywhere)
    }

    @Test func coachStepsTickOff() {
        var page = NinaTourSnapshot()
        page.dayType = "rest"

        var dayType = TourProgress(steps: NinaTour.catalog.allSteps, start: page, startAt: "daytype")
        page.dayType = "tennis"
        let picked = dayType.observe(page)
        #expect(picked)

        var ahead = TourProgress(steps: NinaTour.catalog.allSteps, start: page, startAt: "plan-ahead")
        let unchanged = ahead.observe(page)
        page.plannedDayTypes = 1
        let planned = ahead.observe(page)
        #expect(!unchanged)
        #expect(planned)

        var checks = TourProgress(steps: NinaTour.catalog.allSteps, start: page, startAt: "checks")
        page.checksDone = 1
        let ticked = checks.observe(page)
        #expect(ticked)

        var weighIn = TourProgress(steps: NinaTour.catalog.allSteps, start: page, startAt: "weigh-in")
        page.weighIns = 9
        let weighed = weighIn.observe(page)
        #expect(weighed)

        var measure = TourProgress(steps: NinaTour.catalog.allSteps, start: page, startAt: "measure")
        page.measureCount = 3
        let saved = measure.observe(page)
        #expect(saved)
    }

    /// On iPhone and iPad the + at the top of Today opens Log Food; Create… (weight, measurements,
    /// import …) lives in the ⋯ menu. On the Mac the toolbar's + is Log Food too, next to Create.
    /// The texts must name the path that really exists.
    @Test func iPhoneTextsUseTheMoreMenuForCreate() {
        for step in NinaTour.catalog.allSteps {
            #expect(!step.body.contains("+ →"), "\(step.id) sends people to + for Create")
            #expect(!step.macBody.contains("+ →"), "\(step.id) sends Mac people to + for Create")
        }
        let byID = Dictionary(uniqueKeysWithValues: NinaTour.catalog.allSteps.map { ($0.id, $0) })
        #expect(byID["create"]?.body.contains("⋯ at the top, then Create…") == true)
        #expect(byID["setup-ai"]?.body.contains("⋯ → Create… → Import My Data") == true)
        #expect(byID["weigh-in"]?.body.contains("⋯ → Create… → Weight") == true)
        #expect(byID["measure"]?.body.contains("⋯ → Create… → Measurements") == true)
        // The Mac has its own Create button in the toolbar and the File menu.
        #expect(byID["create"]?.macBody.contains("Click Create in the toolbar") == true)
        #expect(byID["setup-ai"]?.macBody.contains("Create → Import My Data") == true)
        #expect(byID["measure"]?.macBody.contains("File → Log Measurements… (⇧⌘M)") == true)
        // ⌥⌘M is the Mac's Minimize All.
        for step in NinaTour.catalog.allSteps { #expect(!step.macBody.contains("⌥⌘M"), "\(step.id) names ⌥⌘M") }
        // Version 4: the history import sits under Import My Data's Body format, photos on the body page.
        #expect(byID["history"]?.body.contains("⋯ → Create… → Import My Data → Body") == true)
        #expect(byID["history"]?.macBody.contains("File → Import & Export… (⇧⌘I) → Body") == true)
        #expect(byID["photos"]?.body.contains("Progress → Body → Photos") == true)
        #expect(byID["photos"]?.macBody.contains("Body → Photos → Add Photos") == true)
        // The Mac Settings window: Goals and My Plan as they are named there; Apple Health is iPhone only.
        #expect(byID["everywhere"]?.macBody.contains("Settings (⌘,) has Goals, My Plan") == true)
        #expect(byID["everywhere"]?.macBody.contains("Apple Health") == false)
    }

    @Test func readOnlyStepsSayContinue() {
        for id in ["protein", "progress", "checkin"] + Self.versionFourSteps + Self.versionFiveSteps + Self.versionSixSteps {
            let progress = TourProgress(steps: NinaTour.catalog.allSteps, start: NinaTourSnapshot(), startAt: id)
            #expect(progress.step?.id == id)
            #expect(progress.primaryTitle == "Continue")
        }
    }
}
