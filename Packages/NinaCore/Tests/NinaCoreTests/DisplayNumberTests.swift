import Foundation
import Testing
@testable import NinaCore

// The Linux side of the display numbers ("," grouping, "." decimals); on Apple platforms they
// follow the person's locale. Made-up values.

@Suite("Display numbers")
struct DisplayNumberTests {
    @Test func plainFormatsOffApplePlatforms() {
        #expect(DisplayNumber.grouped(2150) == "2,150")
        #expect(DisplayNumber.grouped(999.6) == "1,000")
        #expect(DisplayNumber.fixed(74.62, decimals: 1) == "74.6")
        #expect(DisplayNumber.fixed(2, decimals: 1) == "2.0")
        #expect(DisplayNumber.fixed(-0.04, decimals: 1) == "0.0")
        #expect(DisplayNumber.plain(84.5, decimals: 1) == "84.5")
        #expect(DisplayNumber.plain(79, decimals: 1) == "79")
    }

    /// One sign helper with one zero style for every weight and girth change.
    @Test func signedChangesShareOneZeroStyle() {
        #expect(DisplayNumber.signed(1.24, decimals: 1) == "+1.2")
        #expect(DisplayNumber.signed(-0.3, decimals: 1) == "−0.3")
        #expect(DisplayNumber.signed(0.04, decimals: 1) == "0.0")
        #expect(DisplayNumber.signed(-0.004, decimals: 2) == "0.00")
        #expect(DisplayNumber.signed(0.153, decimals: 2) == "+0.15")
        // The share of body weight is left out when it rounds below 0.05 %.
        #expect(DisplayNumber.weightChange(kilograms: 0.012, percent: 0.016, decimals: 2) == "+0.01 kg")
        #expect(DisplayNumber.weightChange(kilograms: 0.4, percent: 0.52) == "+0.4 kg (+0.5 %)")
        #expect(DisplayNumber.weightChange(kilograms: -0.36, percent: -0.46) == "−0.4 kg (−0.5 %)")
        #expect(DisplayNumber.signedPercent(0.049) == nil)
        #expect(DisplayNumber.signedPercent(nil) == nil)
    }
}
