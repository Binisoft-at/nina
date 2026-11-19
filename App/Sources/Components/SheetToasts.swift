import SwiftUI
import BinisoftKit

// One toast host per visible layer: the window shows the toasts while no app sheet is up, an app
// sheet (`SheetContent`) while it is – also the Undo of a save that just opened the next sheet.
// Screens that can stand alone (the plan editor and Goals in the Mac Settings window) host their
// own, but not inside an app sheet, so a toast never shows twice.

extension ToastCenter {
    /// Always empty: what a host shows while another host shows the toasts.
    static let silent = ToastCenter()
}

private struct ToastsShownAboveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside an app sheet, which shows the toasts itself.
    var toastsShownAbove: Bool {
        get { self[ToastsShownAboveKey.self] }
        set { self[ToastsShownAboveKey.self] = newValue }
    }
}

/// See `View.ownToasts(_:)`.
private struct OwnToasts: ViewModifier {
    let center: ToastCenter
    @Environment(\.toastsShownAbove) private var shownAbove

    func body(content: Content) -> some View {
        content.toasts(shownAbove ? ToastCenter.silent : center, bottomPadding: 16)
    }
}

extension View {
    /// The toasts of a screen that is also shown outside an app sheet (the Mac Settings window):
    /// here, unless an app sheet around it shows them already.
    func ownToasts(_ center: ToastCenter) -> some View {
        modifier(OwnToasts(center: center))
    }

    /// An app sheet's toast host (`SheetContent`): screens inside leave the toasts to it.
    func sheetToasts(_ center: ToastCenter) -> some View {
        toasts(center, bottomPadding: 16)
            .environment(\.toastsShownAbove, true)
    }
}
