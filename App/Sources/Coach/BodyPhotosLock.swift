import SwiftUI
import LocalAuthentication
import BinisoftKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// "Lock Photos with Face ID" (this device only, UserDefaults): the photos stay blurred until Face
/// ID, Touch ID or the device passcode (the Mac's password) unlocks them, and lock again as soon as
/// Nina stops being active on iPhone and iPad (the app switcher, Control Center, a call – early
/// enough for the blur to be in the app switcher's picture), goes to the background, the Mac
/// sleeps or Nina is hidden. On the Mac also after a minute behind other apps (a quick ⌘-Tab
/// doesn't ask again) and when the screen locks. Off in the demo.
@MainActor
@Observable
final class BodyPhotoLock {
    static let shared = BodyPhotoLock()
    static let key = "nina.photos.lock"
    /// How long Nina may sit behind other apps on the Mac before the photos lock again.
    static let backgroundGrace: Duration = .seconds(60)
    /// Password or Touch ID prompts showing right now (they take the focus from Nina).
    private static var authenticating = 0

    private(set) var isEnabled: Bool
    private(set) var isUnlocked = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var backgroundLock: Task<Void, Never>?

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
        authenticating += 1
        defer { authenticating -= 1 }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    /// Mac: Nina went behind another app; the photos lock once it stays there for
    /// `backgroundGrace` (not while a password prompt has the focus).
    private func scheduleBackgroundLock() {
        guard BodyPhotoLock.authenticating == 0 else { return }
        backgroundLock?.cancel()
        backgroundLock = Task { [weak self] in
            try? await Task.sleep(for: BodyPhotoLock.backgroundGrace)
            guard !Task.isCancelled else { return }
            self?.lock()
        }
    }

    private func cancelBackgroundLock() {
        backgroundLock?.cancel()
        backgroundLock = nil
    }

    private func observeBackground() {
        #if os(iOS)
        // Resigning active comes before the app switcher takes its picture; entering the background
        // can be too late for the blur to be drawn. (Face ID's own prompt also resigns active – the
        // photos are locked then anyway.)
        let names = [UIApplication.willResignActiveNotification, UIScene.willDeactivateNotification,
                     UIApplication.didEnterBackgroundNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            })
        }
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
        // The screen locked (without the display sleeping).
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil,
                                                 queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        })
        // Behind other apps for a minute.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleBackgroundLock() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelBackgroundLock() }
        })
        #endif
    }
}

/// The hint on a locked photo.
private enum BodyPhotoLockModifierText {
    static var unlockHint: String {
        #if os(macOS)
        "Locked – click to unlock"
        #else
        "Locked – tap to unlock"
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
                            Text(BodyPhotoLockModifierText.unlockHint)
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

/// The "Lock Photos with Face ID" switch (the Photos card's menu, the photos page), with
/// "This device only": each device has its own switch.
struct BodyPhotoLockToggle: View {
    var body: some View {
        let lock = BodyPhotoLock.shared
        Toggle(isOn: Binding(
            get: { lock.isEnabled },
            set: { enabled in Task { await lock.setEnabled(enabled) } }
        )) {
            Label {
                Text("Lock Photos with \(BodyPhotoLock.methodName)")
                Text("This device only")
            } icon: {
                Image(systemName: "lock")
            }
        }
        .disabled(!lock.isEnabled && !BodyPhotoLock.isAvailable)
    }
}
