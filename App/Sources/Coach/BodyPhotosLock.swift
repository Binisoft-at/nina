import SwiftUI
import LocalAuthentication
import BinisoftKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// "Lock Photos with Face ID" (this device only, UserDefaults): the photos stay blurred until Face
/// ID, Touch ID or the device passcode (the Mac's password) unlocks them, and lock again when Nina
/// goes to the background, the Mac sleeps or Nina is hidden. Off in the demo.
@MainActor
@Observable
final class BodyPhotoLock {
    static let shared = BodyPhotoLock()
    static let key = "nina.photos.lock"

    private(set) var isEnabled: Bool
    private(set) var isUnlocked = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        isEnabled = !LaunchOptions.current.isDemo && UserDefaults.standard.bool(forKey: BodyPhotoLock.key)
        observeBackground()
    }

    /// Blurred right now.
    var isLocked: Bool { isEnabled && !isUnlocked }

    /// "Face ID", "Touch ID", "Optic ID", else "Passcode" (iPhone, iPad) or "Password" (Mac).
    static let methodName: String = {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return PlatformInfo.isMac ? "Password" : "Passcode"
        }
    }()

    /// The device can check who it is (a passcode or password is set).
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Asks for Face ID (or the passcode); true when the photos may show.
    @discardableResult
    func unlock() async -> Bool {
        guard isLocked else { return true }
        let allowed = await BodyPhotoLock.authenticate(reason: "Show your progress photos")
        if allowed { isUnlocked = true }
        return allowed
    }

    func lock() {
        isUnlocked = false
    }

    /// Turning the lock on is immediate; turning it off asks first.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        if !enabled, !isUnlocked {
            let allowed = await BodyPhotoLock.authenticate(reason: "Turn off the photo lock")
            guard allowed else { return }
        }
        isEnabled = enabled
        isUnlocked = enabled
        UserDefaults.standard.set(enabled, forKey: BodyPhotoLock.key)
    }

    private static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        // Without a passcode there is nothing to check with; the switch says so.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    private func observeBackground() {
        #if os(iOS)
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        })
        #elseif os(macOS)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            })
        }
        #endif
    }
}

extension View {
    /// Blurred with a lock while the photos are locked.
    func bodyPhotoLocked(_ locked: Bool, compact: Bool = true) -> some View {
        modifier(BodyPhotoLockCover(locked: locked, compact: compact))
    }
}

private struct BodyPhotoLockCover: ViewModifier {
    let locked: Bool
    let compact: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: locked ? (compact ? 14 : 40) : 0, opaque: true)
            .overlay {
                if locked {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(compact ? Font.title3 : Font.largeTitle)
                        if !compact {
                            Text("Locked – tap to unlock")
                                .font(.callout.weight(.medium))
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Locked photo")
                }
            }
    }
}

/// The "Lock Photos with Face ID" switch (the Photos card's menu, the photos page).
struct BodyPhotoLockToggle: View {
    var body: some View {
        let lock = BodyPhotoLock.shared
        Toggle("Lock Photos with \(BodyPhotoLock.methodName)", systemImage: "lock", isOn: Binding(
            get: { lock.isEnabled },
            set: { enabled in Task { await lock.setEnabled(enabled) } }
        ))
        .disabled(!lock.isEnabled && !BodyPhotoLock.isAvailable)
    }
}
