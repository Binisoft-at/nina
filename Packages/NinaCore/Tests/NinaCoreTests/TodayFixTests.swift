import Foundation
import Testing
@testable import NinaCore

private func calendar(_ zone: String = "Europe/Vienna") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone) ?? .current
    return calendar
}

private func day(_ raw: String) throws -> DayKey { try #require(DayKey(raw)) }

@Suite("Diary entry edits")
struct DiaryEntryEditsTests {

    // MARK: Moving to another day

    @Test func moveKeepsTheClockTime() throws {
        let vienna = calendar()
        let source = try day("2030-05-14")
        let target = try day("2030-05-11")
        let breakfast = source.date(minutes: 8 * 60 + 15, calendar: vienna).addingTimeInterval(20)
        let moved = DiaryEntryEdits.movedTime(breakfast, from: source, to: target, calendar: vienna)
        #expect(DayKey(date: moved, calendar: vienna) == target)
        #expect(ClockTime.minutes(of: moved, calendar: vienna) == 8 * 60 + 15)
        #expect(vienna.component(.second, from: moved) == 20)
    }

    @Test func movingWithinTheSameDayKeepsTheTime() throws {
        let vienna = calendar()
        let source = try day("2030-05-14")
        let time = source.date(minutes: 12 * 60 + 40, calendar: vienna)
        #expect(DiaryEntryEdits.movedTime(time, from: source, to: source, calendar: vienna) == time)
    }

    @Test func aLateSnackStaysAtTheEndOfTheTargetDay() throws {
        let vienna = calendar()
        // With the day starting at 3:00, 00:30 on 15 May still counts for 14 May.
        let source = try day("2030-05-14")
        let snack = source.date(minutes: 24 * 60 + 30, calendar: vienna)
        #expect(DayKey(date: snack, calendar: vienna, dayStartHour: 3) == source)
        let target = try day("2030-05-20")
        let moved = DiaryEntryEdits.movedTime(snack, from: source, to: target, dayStartHour: 3, calendar: vienna)
        #expect(DayKey(date: moved, calendar: vienna, dayStartHour: 3) == target)
        #expect(DayKey(date: moved, calendar: vienna) == target.adding(days: 1, calendar: vienna))
        #expect(ClockTime.minutes(of: moved, calendar: vienna) == 30)
        // Without a late day start the same snack lands on the target's own date.
        let plain = DiaryEntryEdits.movedTime(snack, from: source, to: target, calendar: vienna)
        #expect(DayKey(date: plain, calendar: vienna) == target)
    }

    @Test func movedTimesStayOnTheWallClockAcrossDaylightSaving() throws {
        let vienna = calendar()
        // The clocks go forward on 31 Mar 2030 and back on 27 Oct 2030.
        let source = try day("2030-03-25")
        let dinner = source.date(minutes: 19 * 60, calendar: vienna)
        for raw in ["2030-03-31", "2030-10-27"] {
            let target = try day(raw)
            let moved = DiaryEntryEdits.movedTime(dinner, from: source, to: target, calendar: vienna)
            #expect(DayKey(date: moved, calendar: vienna) == target)
            #expect(ClockTime.minutes(of: moved, calendar: vienna) == 19 * 60)
        }
    }

    @Test func aMovedEntryBelongsToTheTargetDayEvenIfItsTimeWasOff() throws {
        // Logged in New York in the evening, moved later in Vienna: the clock time is read here
        // and the entry lands on the day it was moved to.
        let newYork = calendar("America/New_York")
        let vienna = calendar()
        let source = try day("2030-06-10")
        let evening = source.date(minutes: 21 * 60, calendar: newYork) // 03:00 on 11 June in Vienna
        let target = try day("2030-06-12")
        let moved = DiaryEntryEdits.movedTime(evening, from: source, to: target, calendar: vienna)
        #expect(DayKey(date: moved, calendar: vienna) == target)
        #expect(ClockTime.minutes(of: moved, calendar: vienna) == 3 * 60)
    }

    // MARK: Editing an entry

    @Test func anUntouchedDateKeepsTheStoredDay() throws {
        let vienna = calendar()
        let newYork = calendar("America/New_York")
        // Dinner at 20:00 in New York counts for 10 June; in Vienna it reads 11 June, 02:00.
        let stored = try day("2030-06-10")
        let time = stored.date(minutes: 20 * 60, calendar: newYork)
        #expect(DayKey(date: time, calendar: vienna) == stored.adding(days: 1, calendar: vienna))
        // Only the amount or note changed:
        #expect(DiaryEntryEdits.editedDay(stored: stored, originalTime: time, newTime: time, calendar: vienna) == stored)
        // Only the clock time changed (same date in the picker):
        let later = time.addingTimeInterval(45 * 60)
        #expect(DiaryEntryEdits.editedDay(stored: stored, originalTime: time, newTime: later, calendar: vienna) == stored)
    }

    @Test func aLateSnackKeepsItsDayWhenOnlyTheAmountChanges() throws {
        let vienna = calendar()
        let stored = try day("2030-06-10")
        let snack = stored.date(minutes: 24 * 60 + 40, calendar: vienna) // 00:40 on 11 June
        #expect(DiaryEntryEdits.editedDay(stored: stored, originalTime: snack, newTime: snack, dayStartHour: 3,
                                          calendar: vienna) == stored)
        // A routine planned at 00:30 on its own calendar date (before the day start) stays too.
        let early = stored.date(minutes: 30, calendar: vienna)
        #expect(DiaryEntryEdits.editedDay(stored: stored, originalTime: early, newTime: early, dayStartHour: 3,
                                          calendar: vienna) == stored)
    }

    @Test func aNewDateCountsForItsOwnDay() throws {
        let vienna = calendar()
        let stored = try day("2030-06-10")
        let lunch = stored.date(minutes: 12 * 60, calendar: vienna)
        let nextDay = vienna.date(byAdding: .day, value: 1, to: lunch) ?? lunch
        #expect(DiaryEntryEdits.editedDay(stored: stored, originalTime: lunch, newTime: nextDay, calendar: vienna)
                    == stored.adding(days: 1, calendar: vienna))
        // A new date at 01:30 with the day starting at 3:00 counts for the evening before.
        let night = try day("2030-06-13").date(minutes: 90, calendar: vienna)
        #expect(DiaryEntryEdits.editedDay(stored: stored, originalTime: lunch, newTime: night, dayStartHour: 3,
                                          calendar: vienna) == (try day("2030-06-12")))
    }

    @Test func quickNumbersNeverTurnTypingMistakesIntoZero() {
        // Energy: needed, 0 or more.
        #expect(DiaryEntryEdits.quickValue("350", isEnergy: true) == 350)
        #expect(DiaryEntryEdits.quickValue(" 0 ", isEnergy: true) == 0)
        #expect(DiaryEntryEdits.quickValue("", isEnergy: true) == nil)
        #expect(DiaryEntryEdits.quickValue("-200", isEnergy: true) == nil)
        #expect(DiaryEntryEdits.quickValue("12.,3", isEnergy: true) == nil)
        // Macros: empty is 0, a decimal comma works, negative counts as 0, junk blocks.
        #expect(DiaryEntryEdits.quickValue("", isEnergy: false) == 0)
        #expect(DiaryEntryEdits.quickValue("12,5", isEnergy: false) == 12.5)
        #expect(DiaryEntryEdits.quickValue("-4", isEnergy: false) == 0)
        #expect(DiaryEntryEdits.quickValue("12..3", isEnergy: false) == nil)
        #expect(DiaryEntryEdits.quickValue("7a", isEnergy: false) == nil)
    }

    // MARK: Searching the diary

    @Test func searchNeedlesFoldLikeEverySearch() {
        #expect(DiaryEntryEdits.searchNeedle("#Restaurant") == "restaurant")
        #expect(DiaryEntryEdits.searchNeedle("Café-Latte") == "cafe latte")
        #expect(DiaryEntryEdits.searchNeedle("Straße") == "strasse")
        #expect(DiaryEntryEdits.searchNeedle("a") == nil)
        #expect(DiaryEntryEdits.searchNeedle("#") == nil)
    }

    @Test func entriesMatchOnNameNoteTagsAndBrand() throws {
        let latte = try #require(DiaryEntryEdits.searchNeedle("cafe latte"))
        #expect(DiaryEntryEdits.matches(latte, name: "Café-Latte", note: "", tags: "", brand: ""))
        let street = try #require(DiaryEntryEdits.searchNeedle("strasse"))
        #expect(DiaryEntryEdits.matches(street, name: "Kebab", note: "Straßenfest", tags: "", brand: ""))
        let tag = try #require(DiaryEntryEdits.searchNeedle("#cheat day"))
        #expect(DiaryEntryEdits.matches(tag, name: "Pizza", note: "", tags: "restaurant|cheat day", brand: ""))
        let brand = try #require(DiaryEntryEdits.searchNeedle("berglandmilch"))
        #expect(DiaryEntryEdits.matches(brand, name: "Joghurt", note: "", tags: "", brand: "Berglandmilch"))
        #expect(!DiaryEntryEdits.matches(latte, name: "Espresso", note: "with milk", tags: "", brand: ""))
    }
}
