import SwiftUI
import TipKit

/// Contextual hints (TipKit). Each shows once until dismissed; Settings → Show Hints Again.
enum NinaTips {
    struct CreateTip: Tip {
        var title: Text { Text("Create anything here") }
        var message: Text? { Text("New items and folders – or import the list you already have.") }
        var image: Image? { Image(systemName: "plus.circle.fill") }
    }

    struct SwipeTip: Tip {
        var title: Text { Text("Swipe for quick actions") }
        var message: Text? { Text("Swipe right to check an item off, left to delete it. Touch and hold for everything else.") }
        var image: Image? { Image(systemName: "hand.draw") }
    }
}
