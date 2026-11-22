// swift-tools-version: 6.0
import PackageDescription

// NinaCore: all of Nina's logic that doesn't need Apple frameworks (Foundation only): nutrients,
// the bundled food catalog (Resources/foods.json, built by scripts/build_food_db.py), search, the
// quick-add parser, goals, insights, plans, CSV import/export, the AI prompts and the Binisoft
// exchange with Thalia (ExchangeFormat, ThaliaFeed, ThaliaExchangeWriter).
// Tested with Swift Testing on Linux in CI, so keep UIKit/SwiftUI/SwiftData out of here.
let package = Package(
    name: "NinaCore",
    platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
    products: [
        .library(name: "NinaCore", targets: ["NinaCore"]),
    ],
    dependencies: [
        .package(path: "../../Vendor/BinisoftKit"),
    ],
    targets: [
        .target(
            name: "NinaCore",
            dependencies: [.product(name: "BinisoftKitCore", package: "BinisoftKit")],
            resources: [.copy("Resources/foods.json")]
        ),
        // Fixtures/exchange: the Binisoft exchange files from Thalia's tests (ThaliaExchangeTests).
        .testTarget(name: "NinaCoreTests", dependencies: ["NinaCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
