import SwiftUI
import BinisoftKit

// One toast host per visible layer: the window shows the toasts while no app sheet is up, an app
// sheet (`SheetContent`) while it is – also the Undo of a save that just opened the next sheet.
// Screens that can stand alone (the plan editor and Goals in the Mac Settings window) host their
// own, but not inside an app sheet or the Settings window's host, so a toast never shows twice.
// On the Mac the main window's host is silent while the Settings window is key (MainWindow.swift).

extension ToastCenter {
    /// Always empty: what a host shows while another host shows the toasts.
    static let silent = ToastCenter()
}

/// How far toasts sit above the bottom edge.
enum NinaToastInset {
    #if os(macOS)
    /// The main window.
    static let window: CGFloat = 72
    /// A sheet: above the button row macOS puts at a sheet's bottom.
    static let sheet: CGFloat = 64
    #else
    /// The window: above the tab bar and Today's bar with the calories left (its bottom accessory).
    static let window: CGFloat = 128
    /// A sheet: above a pinned bottom button such as Add · 105 kcal or the measure pages' Next.
    static let sheet: CGFloat = 84
    #endif
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
        content.toasts(shownAbove ? ToastCenter.silent : center, bottomPadding: NinaToastInset.sheet)
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
        toasts(center, bottomPadding: NinaToastInset.sheet)
            .environment(\.toastsShownAbove, true)
    }
}
