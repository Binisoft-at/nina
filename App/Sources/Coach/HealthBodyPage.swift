import Foundation
import NinaCore

// Apple Health on the body page (spec F22): Health's body fat per source app on the composition
// card and Health's waist on the waist tile, each a series of its own next to Nina's records,
// never merged into them, never tracking the goal and never stored. Foundation and NinaCore only.

/// Apple Health's waist series on the waist tile: the latest reading and its change since the
/// phase start, computed within the Health series only.
struct BodyPageHealthWaist {
    let latest: GirthReading
    let change: GirthChange?
    let count: Int

    /// "Health 84.2 cm".
    var text: String { "Health " + BodyPageText.centimeters(latest.value) }
}

extension BodyPageTile {
    /// The waist tile (waist or narrow waist) with Health's waist series; other tiles unchanged.
    func addingHealth(_ health: HealthBodySnapshot, since: DayKey?, calendar: Calendar) -> BodyPageTile {
        guard site.base == .waist || site.base == .waistNarrow, let latest = health.latestWaist else { return self }
        var tile = self
        tile.health = BodyPageHealthWaist(latest: latest, change: HealthBody.waistChange(health.waist, since: since, calendar: calendar),
                                          count: health.waist.count)
        return tile
    }
}

extension BodyPageData {
    /// Adds Health's body-fat series after Nina's own: their points (with the method's error band)
    /// and a row each, marked Health, never the tracking series.
    static func appendHealth(_ health: [HealthBodyFatSeries], points: inout [BodyPageFatPoint],
                             series: inout [BodyPageFatSeries], calendar: Calendar) {
        for item in health {
            guard let latest = item.latest else { continue }
            let band = item.errorBand
            for (index, reading) in item.readings.enumerated() {
                points.append(BodyPageFatPoint(
                    id: "\(item.id)-\(index)", series: item.title, date: reading.day.date(calendar: calendar),
                    bodyFat: reading.bodyFat, low: band.map { reading.bodyFat - $0 }, high: band.map { reading.bodyFat + $0 }))
            }
            series.append(BodyPageFatSeries(id: item.id, title: item.title, latest: latest.bodyFat, latestDay: latest.day,
                                            band: item.method.errorText, count: item.count, isTracking: false,
                                            isHealth: true, leanKg: latest.leanKg))
        }
    }
}

/// Health's waist for the waist detail screen: points for the chart and the readings, newest first.
struct BodyDetailsHealthWaist {
    struct Point: Identifiable {
        let id: String
        let day: DayKey
        let date: Date
        let value: Double
    }

    let points: [Point]
    let change: GirthChange?

    var latest: Point? { points.last }
    /// Newest first.
    var rows: [Point] { points.reversed() }

    /// `waist`: Health's waist series (`HealthBodyReader.waist`). nil when the site isn't a waist
    /// or Health has no waist readings.
    init?(site: BodySite, waist: [GirthReading], since: DayKey?, calendar: Calendar) {
        guard site.base == .waist || site.base == .waistNarrow, !waist.isEmpty else { return nil }
        points = waist.map { reading in
            Point(id: "h-" + reading.day.rawValue, day: reading.day, date: reading.day.date(calendar: calendar), value: reading.value)
        }
        change = HealthBody.waistChange(waist, since: since, calendar: calendar)
    }
}
