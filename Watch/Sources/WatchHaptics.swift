import WatchKit

enum WatchHaptics {
    enum Kind { case success, click }

    static func play(_ kind: Kind) {
        switch kind {
        case .success: WKInterfaceDevice.current().play(.success)
        case .click: WKInterfaceDevice.current().play(.click)
        }
    }
}
