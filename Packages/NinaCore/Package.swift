// swift-tools-version: 6.0
import PackageDescription

// NinaCore: all of Nina's logic that doesn't need Apple frameworks (Foundation only).
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
            dependencies: [.product(name: "BinisoftKitCore", package: "BinisoftKit")]
        ),
        .testTarget(name: "NinaCoreTests", dependencies: ["NinaCore"]),
    ],
    swiftLanguageModes: [.v5]
)
