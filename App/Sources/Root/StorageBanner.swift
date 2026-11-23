import SwiftUI
import BinisoftKit
import NinaCore

/// Storage and sync problems where they can't be missed: at the top of every tab on iPhone and
/// iPad, under the Mac sidebar. Red when Nina runs on an empty temporary store (nothing typed is
/// kept), orange when it doesn't sync – this device only, not signed in to iCloud, iCloud full, or
/// a sync error that has lasted a day (`NinaStorageNotice` decides). Each links to Settings
/// (iCloud & Data, App Log). Nothing shows while all is well, and never in the demo – except for
/// `-DemoScreen banner`, which shows the red one for a screenshot.
struct StorageBanner: View {
    @Environment(AppModel.self) private var app
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let notice = notice(at: context.date) {
                StorageBannerRow(notice: notice) { showSettings() }
            }
        }
        .onChange(of: app.sync.state, initial: true) { _, state in
            StorageBannerClock.record(state)
        }
    }

    private func notice(at now: Date) -> NinaStorageNotice? {
        if app.launch.isDemo, app.launch.screen == "banner" {
            return NinaStorageNotice.current(state: SyncState(mode: .memory(reason: nil)), errorSince: nil, now: now, appName: AppInfo.name)
        }
        return NinaStorageNotice.current(state: app.sync.state, errorSince: StorageBannerClock.errorSince, now: now,
                                         appName: AppInfo.name)
    }

    private func showSettings() {
        #if os(macOS)
        openSettings()
        #else
        app.present(.settings)
        #endif
    }
}

/// When the current sync error was first seen, on this device only (UserDefaults, never synced).
enum StorageBannerClock {
    static let key = "nina.sync.errorSince"

    static var errorSince: Date? {
        UserDefaults.standard.object(forKey: key) as? Date
    }

    static func record(_ state: SyncState) {
        let before = errorSince
        let after = NinaSyncErrorClock.update(before, state: state, now: Date())
        guard after != before else { return }
        if let after {
            UserDefaults.standard.set(after, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// The banner itself: red and white when nothing is saved, a light orange otherwise.
private struct StorageBannerRow: View {
    let notice: NinaStorageNotice
    let showSettings: () -> Void

    private var isCritical: Bool { notice.level == .critical }
    private var textColor: Color { isCritical ? .white : .primary }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isCritical ? "exclamationmark.octagon.fill" : "exclamationmark.icloud.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(isCritical ? Color.white : Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                Text(notice.message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: showSettings) {
                    Text("Open Settings")
                        .font(.caption.weight(.semibold))
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(textColor)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCritical ? Color.red : Color.orange.opacity(0.18))
    }
}

extension View {
    /// iPhone and iPad: the storage banner above a tab's navigation bar (nothing when all is well).
    func storageBannerOnTop() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            StorageBanner()
        }
    }
}
