import Foundation
import Testing
@testable import NinaCore

// Made-up photos and body values in 2030.

private var photoUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func photoDay(_ raw: String) -> DayKey { DayKey(raw)! }

private func photo(_ raw: String, _ pose: PhotoPose, minutes: Int = 420) -> PhotoRecord {
    let day = photoDay(raw)
    return PhotoRecord(id: UUID(), day: day, time: day.date(minutes: minutes, calendar: photoUTC), pose: pose)
}

private func morning(_ raw: String, _ kilograms: Double) -> WeightSignal.Reading {
    let day = photoDay(raw)
    return WeightSignal.Reading(day: day, time: day.date(minutes: 420, calendar: photoUTC), kilograms: kilograms)
}

@Suite("Progress photos")
struct ProgressPhotosTests {
    @Test func poses() {
        #expect(PhotoPose.session == [.front, .side, .back])
        #expect(PhotoPose(stored: "Side") == .side)
        #expect(PhotoPose(stored: "flexed") == .other)
        #expect(PhotoPose(stored: "") == .other)
        #expect(PhotoPose.allCases.map(\.order) == [0, 1, 2, 3])
        #expect(PhotoPose.allCases.allSatisfy { !$0.title.isEmpty && !$0.hint.isEmpty })
    }

    @Test func fittedSize() {
        let portrait = ProgressPhotos.fittedSize(width: 3024, height: 4032, maxPixels: 2048)
        #expect(portrait.width == 1536 && portrait.height == 2048)
        let landscape = ProgressPhotos.fittedSize(width: 4032, height: 3024, maxPixels: 2048)
        #expect(landscape.width == 2048 && landscape.height == 1536)
        let thumb = ProgressPhotos.fittedSize(width: 1536, height: 2048, maxPixels: 360)
        #expect(thumb.width == 270 && thumb.height == 360)
        let square = ProgressPhotos.fittedSize(width: 5000, height: 5000, maxPixels: 2048)
        #expect(square.width == 2048 && square.height == 2048)
        // Never larger than the original.
        let small = ProgressPhotos.fittedSize(width: 800, height: 600, maxPixels: 2048)
        #expect(small.width == 800 && small.height == 600)
        // Very thin images keep at least one pixel.
        let thin = ProgressPhotos.fittedSize(width: 10_000, height: 2, maxPixels: 360)
        #expect(thin.width == 360 && thin.height == 1)
        let empty = ProgressPhotos.fittedSize(width: 0, height: 0, maxPixels: 360)
        #expect(empty.width == 1 && empty.height == 1)
    }

    @Test func latestAndDays() {
        let photos = [
            photo("2030-03-01", .front), photo("2030-01-07", .front), photo("2030-01-07", .side),
            photo("2030-03-01", .front, minutes: 430), photo("2030-02-04", .back),
        ]
        let latest = ProgressPhotos.latest(photos)
        #expect(latest[.front]?.day == photoDay("2030-03-01"))
        #expect(latest[.front]?.id == photos[3].id)  // the later one that day
        #expect(latest[.side]?.day == photoDay("2030-01-07"))
        #expect(latest[.other] == nil)
        #expect(ProgressPhotos.days(of: .front, in: photos) == [photoDay("2030-01-07"), photoDay("2030-03-01")])
        #expect(ProgressPhotos.photo(of: .front, on: photoDay("2030-03-01"), in: photos)?.id == photos[3].id)
        #expect(ProgressPhotos.photo(of: .back, on: photoDay("2030-03-01"), in: photos) == nil)
        #expect(ProgressPhotos.timeline(of: .front, in: photos).map(\.id) == [photos[1].id, photos[0].id, photos[3].id])
        #expect(ProgressPhotos.poses(photos) == [.front, .side, .back])
        #expect(ProgressPhotos.ghost(for: .front, in: photos)?.id == photos[3].id)
        #expect(ProgressPhotos.ghost(for: .other, in: photos) == nil)
    }

    @Test func comparePairs() {
        let photos = [
            photo("2030-01-07", .front), photo("2030-02-04", .front), photo("2030-03-04", .front),
            photo("2030-01-07", .side), photo("2030-03-04", .back), photo("2030-03-04", .back, minutes: 500),
        ]
        #expect(ProgressPhotos.comparablePoses(photos) == [.front])
        #expect(ProgressPhotos.comparePose(photos) == .front)
        #expect(ProgressPhotos.comparePose(photos, preferred: .back) == .front)  // one day only
        #expect(ProgressPhotos.comparePose([photo("2030-01-07", .front)]) == nil)

        let pair = ProgressPhotos.defaultPair(for: .front, in: photos)
        #expect(pair == ProgressPhotos.Pair(photoDay("2030-01-07"), photoDay("2030-03-04")))
        #expect(pair?.days(calendar: photoUTC) == 56)
        #expect(ProgressPhotos.defaultPair(for: .back, in: photos) == nil)

        // The pair stays ordered whatever is picked.
        let reversed = ProgressPhotos.Pair(photoDay("2030-03-04"), photoDay("2030-01-07"))
        #expect(reversed.before == photoDay("2030-01-07"))
        let days = ProgressPhotos.days(of: .front, in: photos)
        let start = ProgressPhotos.Pair(photoDay("2030-01-07"), photoDay("2030-03-04"))
        let middle = ProgressPhotos.pair(start, picking: photoDay("2030-02-04"), asBefore: true, days: days)
        #expect(middle == ProgressPhotos.Pair(photoDay("2030-02-04"), photoDay("2030-03-04")))
        let after = ProgressPhotos.pair(start, picking: photoDay("2030-02-04"), asBefore: false, days: days)
        #expect(after == ProgressPhotos.Pair(photoDay("2030-01-07"), photoDay("2030-02-04")))
        #expect(ProgressPhotos.pair(start, picking: photoDay("2030-03-04"), asBefore: true, days: days) == start)
        #expect(ProgressPhotos.pair(start, picking: photoDay("2030-05-01"), asBefore: true, days: days) == start)
    }

    @Test func spanText() {
        #expect(ProgressPhotos.spanText(days: 0) == "Same day")
        #expect(ProgressPhotos.spanText(days: 1) == "1 day")
        #expect(ProgressPhotos.spanText(days: 12) == "12 days")
        #expect(ProgressPhotos.spanText(days: 14) == "2 weeks")
        #expect(ProgressPhotos.spanText(days: 36) == "5 weeks 1 day")
        #expect(ProgressPhotos.spanText(days: 59) == "8 weeks 3 days")
        #expect(ProgressPhotos.spanText(days: -21) == "3 weeks")
    }

    @Test func nearest() {
        let values: [(day: DayKey, value: Double)] = [
            (photoDay("2030-01-01"), 80.0), (photoDay("2030-01-09"), 79.5), (photoDay("2030-01-11"), 79.0),
        ]
        // Two days either side: the earlier wins the tie.
        let tie = ProgressPhotos.nearest(values, to: photoDay("2030-01-05"), within: 7, calendar: photoUTC)
        #expect(tie?.day == photoDay("2030-01-01"))
        let close = ProgressPhotos.nearest(values, to: photoDay("2030-01-10"), calendar: photoUTC)
        #expect(close?.day == photoDay("2030-01-09"))
        let same = ProgressPhotos.nearest(values, to: photoDay("2030-01-11"), calendar: photoUTC)
        #expect(same?.value == 79.0)
        #expect(ProgressPhotos.nearest(values, to: photoDay("2030-02-01"), calendar: photoUTC) == nil)
        #expect(ProgressPhotos.nearest([], to: photoDay("2030-02-01"), calendar: photoUTC) == nil)
    }

    @Test func exifDates() {
        let utc = TimeZone(identifier: "UTC")!
        let date = ProgressPhotos.exifDate("2030:01:07 07:12:30", timeZone: utc)
        let expected = photoDay("2030-01-07").date(minutes: 432, calendar: photoUTC).addingTimeInterval(30)
        #expect(date == expected)
        #expect(ProgressPhotos.exifDate("2030-01-07T07:12", timeZone: utc) == photoDay("2030-01-07").date(minutes: 432, calendar: photoUTC))
        #expect(ProgressPhotos.exifDate("0000:00:00 00:00:00", timeZone: utc) == nil)
        #expect(ProgressPhotos.exifDate("", timeZone: utc) == nil)
        #expect(ProgressPhotos.exifDate("yesterday", timeZone: utc) == nil)
    }

    @Test func comparison() {
        var readings: [WeightSignal.Reading] = []
        for day in DayKey.range(photoDay("2030-01-01"), through: photoDay("2030-01-07"), calendar: photoUTC) {
            readings.append(morning(day.rawValue, 74.0))
        }
        for day in DayKey.range(photoDay("2030-03-01"), through: photoDay("2030-03-07"), calendar: photoUTC) {
            readings.append(morning(day.rawValue, 75.5))
        }
        let signal = WeightSignal(readings, calendar: photoUTC)
        let tape = [
            BodyTapeRecord(day: photoDay("2030-01-06"), values: BodyValues([.waist: 82.0, .arm: 33.0]), conditions: "morning,fasted"),
            BodyTapeRecord(day: photoDay("2030-03-07"), values: BodyValues([.waist: 81.2]), conditions: "morning,fasted"),
        ]
        let pair = ProgressPhotos.Pair(photoDay("2030-01-07"), photoDay("2030-03-07"))
        let comparison = PhotoComparison(pair: pair, signal: signal, tape: tape, calendar: photoUTC)
        #expect(comparison.days == 59)
        #expect(comparison.before.weight == 74.0)
        #expect(comparison.after.weight == 75.5)
        #expect(comparison.weightChange == 1.5)
        #expect(comparison.waistSite == .waist)
        #expect(comparison.before.waist == 82.0 && comparison.before.waistDay == photoDay("2030-01-06"))
        #expect(comparison.after.waist == 81.2)
        #expect(abs((comparison.waistChange ?? 0) - (-0.8)) < 0.0001)

        // No average without four mornings; the narrow waist when there is no waist.
        let narrow = [BodyTapeRecord(day: photoDay("2030-01-07"), values: BodyValues([.waistNarrow: 71.0]), conditions: "")]
        let sparse = WeightSignal([morning("2030-01-07", 74.0)], calendar: photoUTC)
        let other = PhotoComparison(pair: pair, signal: sparse, tape: narrow, calendar: photoUTC)
        #expect(other.before.weight == nil && other.weightChange == nil)
        #expect(other.waistSite == .waistNarrow)
        #expect(other.before.waist == 71.0 && other.after.waist == nil && other.waistChange == nil)

        // The same tape record near both days is no change.
        let close = ProgressPhotos.Pair(photoDay("2030-01-05"), photoDay("2030-01-07"))
        let once = PhotoComparison(pair: close, signal: signal, tape: tape, calendar: photoUTC)
        #expect(once.before.waist == 82.0 && once.after.waist == 82.0 && once.waistChange == nil)
    }

    @Test func session() {
        let session = PhotoSession()
        #expect(session.steps == [.intro, .pose(.front), .pose(.side), .pose(.back), .review])
        #expect(session.first == .intro)
        #expect(session.next(after: .intro) == .pose(.front))
        #expect(session.next(after: .pose(.back)) == .review)
        #expect(session.next(after: .review) == nil)
        #expect(session.previous(before: .pose(.front)) == .intro)
        #expect(session.previous(before: .intro) == nil)
        #expect(session.nextTitle(after: .intro) == "Start")
        #expect(session.nextTitle(after: .pose(.front)) == "Next: Side")
        #expect(session.nextTitle(after: .pose(.back)) == "Review")
        #expect(session.nextTitle(after: .review) == "Done")
        #expect(session.position(of: .side) == "Side · 2 of 3")
        #expect(session.position(of: .other) == nil)

        let quick = PhotoSession(poses: [.front], showsIntro: false)
        #expect(quick.steps == [.pose(.front), .review])
        #expect(quick.first == .pose(.front))
        #expect(PhotoSession(poses: []).poses == PhotoPose.session)
    }
}
