import Foundation

/// The small snapshot widgets read from the shared App Group (never the full data).
public struct ItemSummary: Codable, Equatable, Sendable {
    public static let fileName = "snapshot.json"

    public var openCount: Int
    public var doneCount: Int
    /// The next few open items, top of the list first.
    public var next: [String]
    public var updatedAt: Date

    public init(openCount: Int, doneCount: Int, next: [String], updatedAt: Date) {
        self.openCount = openCount
        self.doneCount = doneCount
        self.next = next
        self.updatedAt = updatedAt
    }

    public static let placeholder = ItemSummary(openCount: 3, doneCount: 1,
                                                next: ["Water the plants", "Send the invoice", "Call grandma"],
                                                updatedAt: Date(timeIntervalSince1970: 0))

    /// - Parameter open: open item titles in list order.
    public static func make(open: [String], doneCount: Int, now: Date = Date(), limit: Int = 3) -> ItemSummary {
        ItemSummary(openCount: open.count, doneCount: doneCount, next: Array(open.prefix(limit)), updatedAt: now)
    }

    /// Same numbers and titles (ignores the time), so widgets reload only when something changed.
    public func hasSameContent(as other: ItemSummary?) -> Bool {
        guard let other else { return false }
        return openCount == other.openCount && doneCount == other.doneCount && next == other.next
    }

    /// "3 open" / "All done".
    public var headline: String {
        openCount == 0 ? "All done" : "\(openCount) open"
    }
}
