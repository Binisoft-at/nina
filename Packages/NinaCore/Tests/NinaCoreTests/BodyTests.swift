import Foundation
import Testing
@testable import NinaCore

private var bodyUTC: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

@Suite("Body")
struct BodyTests {
    @Test func valuesEncodeAndDecode() {
        var values = BodyValues(encoded: "waist=84.6;chest=101.25;arm=34.5;sf_chest=12;elbow=27;bad=x;=3;neck")
        #expect(values[.waist] == 84.6)
        #expect(values[.chest] == 101.25)
        #expect(values["sf_chest"] == 12)
        // Unknown keys are kept, broken pairs dropped.
        #expect(values["elbow"] == 27)
        #expect(values.keys == ["arm", "chest", "elbow", "sf_chest", "waist"])
        #expect(values.encoded == "arm=34.5;chest=101.25;elbow=27;sf_chest=12;waist=84.6")
        #expect(BodyValues(encoded: values.encoded) == values)
        #expect(values.sites == [.waist: 84.6, .chest: 101.25, .arm: 34.5])
        values[.armLeft] = 34.1
        values[.waist] = nil
        values["thigh"] = .nan
        #expect(values.encoded == "arm=34.5;arm_l=34.1;chest=101.25;elbow=27;sf_chest=12")
        var assessment = BodyValues()
        assessment.bodyFat = 20
        assessment.leanKg = 64
        assessment.fatKg = 16
        assessment.boneKg = 3.1
        #expect(assessment.encoded == "bodyFat=20;boneKg=3.1;fatKg=16;leanKg=64")
        #expect(BodyValues(encoded: assessment.encoded).bodyFat == 20)
        #expect(BodyValues(encoded: "").isEmpty)
        #expect(BodyValues([.hip: 98]).encoded == "hip=98")
    }

    @Test func sites() {
        #expect(BodySite(rawValue: "waist_narrow") == .waistNarrow)
        #expect(BodySite(rawValue: "arm_l") == .armLeft)
        #expect(BodySite.waist.tem == 0.4 && BodySite.waist.mdc == 1.0)
        #expect(BodySite.arm.tem == 0.2 && BodySite.arm.mdc == 0.5)
        #expect(BodySite.neck.mdc == 0.5 && BodySite.calfLeft.mdc == 0.5)
        #expect(BodySite.thigh.mdc == 1.0 && BodySite.thighLeft.tem == 0.4)
        #expect(BodySite.hip.plausibleRange == 60...200)
        #expect(BodySite.armFlexed.isPlausible(40))
        #expect(!BodySite.arm.isPlausible(8.5))
        #expect(BodySite.armLeft.base == .arm && BodySite.armLeft.isLeft)
        #expect(BodySite.arm.left == .armLeft && BodySite.chest.left == nil)
        #expect(BodySite.thigh.sites(for: .both) == [.thigh, .thighLeft])
        #expect(BodySite.thigh.sites(for: .left) == [.thighLeft])
        #expect(BodySite.chest.sites(for: .both) == [.chest])
        #expect(BodySite.calfLeft.hasSides)
        // One site on its own: both sides when both are measured, else the key asked for.
        #expect(BodySite.arm.measuredSites(side: .both) == [.arm, .armLeft])
        #expect(BodySite.armLeft.measuredSites(side: .both) == [.arm, .armLeft])
        #expect(BodySite.arm.measuredSites(side: .right) == [.arm])
        #expect(BodySite.arm.measuredSites(side: .left) == [.arm])
        #expect(BodySite.thighLeft.measuredSites(side: .left) == [.thighLeft])
        #expect(BodySite.waist.measuredSites(side: .both) == [.waist])
        #expect(BodySite.waist.landmark.contains("navel"))
        #expect(BodySite.defaultSites(sex: .male) == [.waist, .hip, .chest, .arm, .thigh])
        #expect(BodySite.defaultSites(sex: .female, trackingMethod: .navy, side: .both)
                == [.waistNarrow, .hip, .chest, .arm, .armLeft, .thigh, .thighLeft, .neck])
    }

    @Test func methods() {
        #expect(BodyMethod(rawValue: "bia_pro") == .biaPro)
        #expect(BodyMethod.dexa.errorBand == 1.5)
        #expect(BodyMethod.navy.errorBand == 3.5)
        #expect(BodyMethod.estimate.errorBand == nil)
        #expect(BodyMethod.scale.errorText == "±4–5")
        #expect(BodyMethod.dexa.errorText == "±1.5")
        #expect(BodyMethod.biaPro.errorText == "±3")
        #expect(BodyMethod.accuracyOrder.map(\.rawValue) == ["dexa", "bodpod", "bia_pro", "skinfold", "navy", "scale", "estimate"])
        #expect(BodyMethod.skinfold.accuracyRank < BodyMethod.navy.accuracyRank)
        #expect(BodyMethod.trackingDefault(counts: [.scale: 5, .navy: 2, .dexa: 1]) == .navy)
        #expect(BodyMethod.trackingDefault(counts: [.estimate: 1]) == nil)
    }

    @Test func protocolAndStandardReadings() {
        #expect(BodyProtocol.isStandard("morning,fasted"))
        #expect(BodyProtocol.isStandard(" Fasted , morning "))
        #expect(BodyProtocol.isStandard([.morning, .fasted, .morning]))
        #expect(!BodyProtocol.isStandard("morning,fasted,high_salt"))
        #expect(!BodyProtocol.isStandard("morning"))
        #expect(!BodyProtocol.isStandard("later"))
        #expect(!BodyProtocol.isStandard(""))
        #expect(!BodyProtocol.isStandard("morning,fasted,something_new"))
        #expect(BodyProtocol.encode([.morning, .fasted, .afterTraining, .fasted]) == "morning,fasted,after_training")
        #expect(BodyProtocol.tags("morning, ,FASTED,morning") == ["morning", "fasted"])
        let early = Date(timeIntervalSince1970: 1_894_006_800 - 2 * 3600) // 07:00 UTC
        let noon = Date(timeIntervalSince1970: 1_894_006_800 + 3 * 3600) // 12:00 UTC
        #expect(BodyProtocol.automatic(at: early, cutoffMinutes: 660, hasEaten: false, calendar: bodyUTC) == [.morning, .fasted])
        #expect(BodyProtocol.automatic(at: early, cutoffMinutes: 660, hasEaten: true, calendar: bodyUTC) == [.later])
        #expect(BodyProtocol.automatic(at: noon, cutoffMinutes: 660, hasEaten: false, calendar: bodyUTC) == [.later])
        #expect(BodyCondition.highSalt.isException && !BodyCondition.fasted.isException)
        #expect(!BodyCondition.exceptions(for: .male).contains(.menstrualPhase))
        #expect(BodyCondition.exceptions(for: .female).contains(.menstrualPhase))
        #expect(!BodyProtocol.checklist.isEmpty)
    }

    @Test func readingMerge() {
        // Full set: two readings, a third when they differ by more than 0.5 cm.
        #expect(BodyReadings.needsAnother([]))
        #expect(BodyReadings.needsAnother([84.4]))
        #expect(!BodyReadings.needsAnother([84.4, 84.8]))
        #expect(!BodyReadings.needsAnother([84.4, 84.9]))
        #expect(BodyReadings.needsAnother([84.4, 85.0]))
        #expect(!BodyReadings.needsAnother([84.4, 85.0, 84.6]))
        #expect(BodyReadings.merged([]) == nil)
        #expect(BodyReadings.merged([84.4]) == 84.4)
        #expect(BodyReadings.merged([84.4, 84.7]) == 84.55)
        #expect(BodyReadings.merged([84.4, 85.0, 84.6]) == 84.6)
        #expect(BodyReadings.merged([85.0, 84.4, 84.5, 84.7]) == 84.6)
        // Weekly: one reading, a second when it moved more than 1.0 cm since last time.
        #expect(!BodyReadings.needsAnother([85.0], twoReadings: false))
        #expect(!BodyReadings.needsAnother([85.0], twoReadings: false, previous: 84.0))
        #expect(BodyReadings.needsAnother([85.2], twoReadings: false, previous: 84.0))
        #expect(BodyReadings.needsAnother([82.9], twoReadings: false, previous: 84.0))
        #expect(BodyReadings.needsAnother([85.2, 84.2], twoReadings: false, previous: 84.0))
        // "Same spot as last time?" for more than 3 cm within 7 days.
        #expect(BodyReadings.isSuspiciousJump(82.1, previous: 79.0, daysApart: 5))
        #expect(!BodyReadings.isSuspiciousJump(82.0, previous: 79.0, daysApart: 5))
        #expect(!BodyReadings.isSuspiciousJump(84, previous: 79.0, daysApart: 14))
        #expect(!BodyReadings.isSuspiciousJump(84, previous: nil, daysApart: 1))
    }
}
