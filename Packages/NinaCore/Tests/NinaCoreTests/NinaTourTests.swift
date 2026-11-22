import Testing
import BinisoftKitCore
@testable import NinaCore

/// The coach steps of tour version 3 (day types, daily checks, protein per meal, weigh-in,
/// measurements, Progress, check-in) and the steps of version 4 (progress photos, the coach on the
/// watch, body data from Apple Health, importing the weight & body history).
@Suite("Coach tour")
struct CoachTourTests {
    static let coachSteps = ["daytype", "plan-ahead", "checks", "protein", "weigh-in", "measure", "progress", "checkin"]
    static let versionFourSteps = ["photos", "watchCoach", "healthBody", "history"]

    @Test func versionThreeAddsTheCoachSteps() {
        let ids = NinaTour.catalog.steps.filter { $0.since == 3 }.map(\.id)
        #expect(ids == Self.coachSteps)
        for step in NinaTour.catalog.steps where step.since == 3 {
            #expect(step.macBody != step.body, "\(step.id) needs its own Mac text")
            #expect(!step.macBody.isEmpty)
        }
    }

    @Test func versionFourAddsPhotosWatchHealthAndHistory() {
        #expect(NinaTour.version == 4)
        let ids = NinaTour.catalog.steps.filter { $0.since == 4 }.map(\.id)
        #expect(ids == Self.versionFourSteps)
        for step in NinaTour.catalog.steps where step.since == 4 {
            #expect(step.macBody != step.body, "\(step.id) needs its own Mac text")
            #expect(!step.macBody.isEmpty)
            #expect(step.goal.isManual, "\(step.id) is read-only: nothing on the practice page to tick it off")
        }
    }

    @Test func peopleWhoTookVersionTwoSeeTheCoachAndTheVersionFourSteps() {
        let ids = NinaTour.catalog.steps(newerThan: 2).map(\.id)
        #expect(ids == ["whats-new"] + Self.coachSteps + Self.versionFourSteps + ["finish"])
    }

    /// Version 3 is on TestFlight: those testers get only the four new steps as "What's new".
    @Test func peopleWhoTookVersionThreeSeeOnlyTheVersionFourSteps() {
        let ids = NinaTour.catalog.steps(newerThan: 3).map(\.id)
        #expect(ids == ["whats-new"] + Self.versionFourSteps + ["finish"])
        #expect(NinaTour.catalog.steps(newerThan: 4).isEmpty)
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
        let everywhere = everything.firstIndex(of: "everywhere") ?? 0
        #expect(water < daytype)
        #expect(daytype < checkin)
        #expect(checkin < photos)
        #expect(photos < history)
        #expect(history < everywhere)
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
        #expect(byID["measure"]?.macBody.contains("File → Log Measurements…") == true)
        // Version 4: the history import sits under Import My Data's Body format, photos on the body page.
        #expect(byID["history"]?.body.contains("⋯ → Create… → Import My Data → Body") == true)
        #expect(byID["history"]?.macBody.contains("File → Import My Data… (⇧⌘I) → Body") == true)
        #expect(byID["photos"]?.body.contains("Progress → Body → Photos") == true)
        #expect(byID["photos"]?.macBody.contains("Body → Photos → Add Photos") == true)
    }

    @Test func readOnlyStepsSayContinue() {
        for id in ["protein", "progress", "checkin"] + Self.versionFourSteps {
            let progress = TourProgress(steps: NinaTour.catalog.allSteps, start: NinaTourSnapshot(), startAt: id)
            #expect(progress.step?.id == id)
            #expect(progress.primaryTitle == "Continue")
        }
    }
}
