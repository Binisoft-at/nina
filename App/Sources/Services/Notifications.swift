import Foundation
import SwiftData
import UserNotifications
import BinisoftKit
import NinaCore

/// Local notifications: "Lunch planned – eaten?" with ✓ Eaten / Skipped right in the banner
/// (also on the Apple Watch), and optional meal reminders that disappear once the meal is logged.
@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()

    static let plannedCategory = "nina.planned"
    static let reminderCategory = "nina.reminder"
    static let remindersKey = "nina.reminders.meals"
    static let plannedKey = "nina.reminders.planned"
    static let delayKey = "nina.reminders.delay"

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func activate() {
        center.delegate = self
        let eaten = UNNotificationAction(identifier: "eaten", title: "Eaten ✓", options: [])
        let skip = UNNotificationAction(identifier: "skip", title: "Skipped", options: [])
        let log = UNNotificationAction(identifier: "log", title: "Log Now", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.plannedCategory, actions: [eaten, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.reminderCategory, actions: [log], intentIdentifiers: []),
        ])
        if UserDefaults.standard.object(forKey: Self.plannedKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.plannedKey)
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    var reminderMeals: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.remindersKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.remindersKey) }
    }

    var plannedEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.plannedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.plannedKey) }
    }

    /// Minutes after a meal's usual time before its reminder.
    var reminderDelay: Int {
        get { UserDefaults.standard.object(forKey: Self.delayKey) as? Int ?? 60 }
        set { UserDefaults.standard.set(newValue, forKey: Self.delayKey) }
    }

    /// Replaces every pending notification with the current plan and reminders (next 3 days).
    func reschedule(context: ModelContext, settings: NinaSettings) {
        let store = NinaStore(context: context)
        let now = Date()
        let today = settings.today(now: now)
        var requests: [UNNotificationRequest] = []

        if plannedEnabled {
            let rules = Dictionary(store.planRules().map { ($0.uuid.uuidString, $0.notify) }, uniquingKeysWith: { first, _ in first })
            let planned = store.entries(from: today, through: today.adding(days: 2)).filter { $0.isPlanned && $0.time > now }
            let groups = Dictionary(grouping: planned) { entry -> String in
                entry.groupID.isEmpty ? (entry.planKey.isEmpty ? entry.uuid.uuidString : entry.planKey) : entry.groupID
            }
            for (key, entries) in groups {
                guard let first = entries.min(by: { $0.time < $1.time }) else { continue }
                if first.planKey.hasPrefix("rule:") {
                    let ruleID = first.planKey.split(separator: ":").dropFirst().first.map(String.init) ?? ""
                    if rules[ruleID] == false { continue }
                }
                let slot = settings.meal(first.meal)
                let content = UNMutableNotificationContent()
                content.title = "\(slot.emoji) \(slot.name) · planned"
                let energy = entries.map(\.energy).reduce(0, +)
                content.body = "\(entries.map(\.displayName).joined(separator: ", ")) · \(Fmt.energy(energy, unit: settings.energyUnit)). Eaten?"
                content.categoryIdentifier = Self.plannedCategory
                content.userInfo = ["entries": entries.map(\.uuid.uuidString), "day": first.day]
                content.sound = .default
                requests.append(request("nina.plan.\(key)", content, at: first.time))
            }
        }

        let meals = reminderMeals
        if !meals.isEmpty {
            for offset in 0..<3 {
                let day = today.adding(days: offset)
                let logged = Set(store.entries(on: day).filter(\.isEaten).map(\.meal))
                for slot in settings.meals where meals.contains(slot.id) && !logged.contains(slot.id) {
                    let date = day.date(minutes: slot.minutes + reminderDelay)
                    guard date > now else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = "\(slot.emoji) \(slot.name) logged?"
                    content.body = "Type it like a message – \u{201C}2 eggs and a toast\u{201D} – and you're done."
                    content.categoryIdentifier = Self.reminderCategory
                    content.userInfo = ["meal": slot.id, "day": day.rawValue]
                    requests.append(request("nina.remind.\(slot.id).\(day.rawValue)", content, at: date))
                }
            }
        }

        let center = self.center
        center.removeAllPendingNotificationRequests()
        for request in requests {
            center.add(request) { error in
                if let error { AppLog.warning("Notification not scheduled: \(error.localizedDescription)", category: "notifications") }
            }
        }
    }

    private func request(_ id: String, _ content: UNNotificationContent, at date: Date) -> UNNotificationRequest {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let ids = (info["entries"] as? [String]) ?? []
        let meal = info["meal"] as? String
        await MainActor.run {
            NotificationScheduler.shared.handle(action: action, entryIDs: ids, meal: meal)
        }
    }

    private func handle(action: String, entryIDs: [String], meal: String?) {
        let context = Persistence.shared.container.mainContext
        let store = NinaStore(context: context)
        let uuids = entryIDs.compactMap(UUID.init(uuidString:))
        let entries = uuids.isEmpty ? [] : ((try? context.fetch(FetchDescriptor<LogEntry>(predicate: #Predicate<LogEntry> { uuids.contains($0.uuid) }))) ?? [])
        switch action {
        case "eaten":
            store.confirm(entries)
            AppLog.info("Planned meal confirmed from a notification (\(entries.count) foods)", category: "notifications")
        case "skip":
            store.setStatus(entries, .skipped)
        case "log":
            if let url = URL(string: "\(AppInfo.urlScheme)://add") {
                NotificationCenter.default.post(name: .ninaOpenURL, object: url)
            }
        default:
            break
        }
    }
}

extension Notification.Name {
    /// A URL the app should open (from a notification action).
    static let ninaOpenURL = Notification.Name("at.binisoft.nina.openURL")
}
