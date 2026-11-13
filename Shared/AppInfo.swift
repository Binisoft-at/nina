import Foundation

/// Names used in texts and file paths. Identifiers live in Config/Base.xcconfig, not here.
enum AppInfo {
    static let name = "Nina"
    /// What the app keeps, in the person's words.
    static let dataNoun = "diary"
    /// URL scheme for widgets and shortcuts: nina://add, nina://water?ml=250, nina://today
    static let urlScheme = "nina"
}
