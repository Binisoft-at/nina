import Foundation
import SwiftData
import UserNotifications
import BinisoftKit
import NinaCore

/// Local notifications: "Lunch planned – eaten?" with ✓ Eaten / Skipped right in the banner
/// (also on the Apple Watch), optional meal reminders that disappear once the meal is logged, and
/// the coach's reminders (morning weigh-in, daily checks, the evening before a full measurement,
/// the weekly check-in, phase dates – planned in `CoachReminders`). Everything is rebuilt on every
/// data change, so a task done on any device takes its notification away.
@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()

    static let plannedCategory = "nina.planned"
    static let reminderCategory = "nina.reminder"
    static let remindersKey = "nina.reminders.meals"
    static let plannedKey = "nina.reminders.planned"
    static let delayKey = "nina.reminders.delay"
    // Coach reminders: device-only, never synced.
    static let coachDeviceKey = "nina.coach.reminders.device"
    static let coachOffKey = "nina.coach.reminders.off"
    static let coachAskedKey = "nina.coach.reminders.asked"
    static let coachReviewKey = "nina.coach.reminders.review"
    /// The "is that right?" notification after a weight typed into the banner that needs a look.
    static let weighCheckID = "nina.weigh.check"
    /// The same for a tape value ("Waist…").
    static let tapeCheckID = "nina.tape.check"

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    /// The coach categories registered last (they follow the plan).
    private var coachCategories: [CoachReminders.Category]?
    /// A nina:// link a notification asked to open that no window has opened yet: on a cold start
    /// the answer can come before the window listens, so RootView also takes it when it appears.
    private var pendingURL: URL?

    /// The link a notification asked to open, once (nil when there is none or it was opened).
    func takePendingURL() -> URL? {
        let url = pendingURL
        pendingURL = nil
        return url
    }

    func activate() {
        center.delegate = self
        registerCategories(coach: [])
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

    // MARK: Coach settings (this device)

    /// This device schedules the coach's reminders: on by default on the iPhone (the Apple Watch
    /// shows them too), off on iPad and Mac until turned on there.
    var coachOnThisDevice: Bool {
        get { UserDefaults.standard.object(forKey: Self.coachDeviceKey) as? Bool ?? PlatformInfo.isPhone }
        set { UserDefaults.standard.set(newValue, forKey: Self.coachDeviceKey) }
    }

    /// The coach reminders turned on (all of them unless turned off one by one).
    var coachKinds: Set<CoachReminders.Kind> {
        get {
            let off = Set(UserDefaults.standard.stringArray(forKey: Self.coachOffKey) ?? [])
            return Set(CoachReminders.Kind.allCases.filter { !off.contains($0.rawValue) })
        }
        set {
            let off = CoachReminders.Kind.allCases.filter { !newValue.contains($0) }.map(\.rawValue)
            UserDefaults.standard.set(off, forKey: Self.coachOffKey)
        }
    }

    /// "Turn on coach reminders?" was asked on this device.
    var coachAsked: Bool {
        get { UserDefaults.standard.bool(forKey: Self.coachAskedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.coachAskedKey) }
    }

    /// When each phase's review notification was first planned: it comes once.
    private var reviewPlannedAt: [String: Date] {
        get {
            let stored = UserDefaults.standard.dictionary(forKey: Self.coachReviewKey) as? [String: Double] ?? [:]
            return stored.mapValues { Date(timeIntervalSince1970: $0) }
        }
        set { UserDefaults.standard.set(newValue.mapValues { $0.timeIntervalSince1970 }, forKey: Self.coachReviewKey) }
    }

    /// Ask "Turn on coach reminders?" now: a plan was just set up and this device never asked.
    /// The plan editor and the settings import call it with the plan before and after a save.
    func shouldOfferCoachReminders(before: CoachPlan, after: CoachPlan) -> Bool {
        !coachAsked && !before.isSetUp && after.isSetUp
    }

    /// The answer to "Turn on coach reminders?": yes turns them all on for this device and asks
    /// for permission; no turns them off here (Settings > Reminders can change both).
    func answerCoachReminders(_ yes: Bool, context: ModelContext, settings: NinaSettings) async {
        coachAsked = true
        coachOnThisDevice = yes
        if yes {
            coachKinds = Set(CoachReminders.Kind.allCases)
            _ = await requestAuthorization()
        }
        AppLog.info("Coach reminders \(yes ? "turned on" : "left off") on this device", category: "notifications")
        reschedule(context: context, settings: settings)
    }

    // MARK: Scheduling

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

        // The coach: categories follow the plan (the morning's actions change from day to day).
        let coach = coachSchedule(store: store, settings: settings, now: now, today: today)
        registerCategories(coach: coach.categories)
        rememberReviews(coach)
        for item in coach.pending(after: now) {
            requests.append(request(item))
        }

        let center = self.center
        center.removeAllPendingNotificationRequests()
        for request in requests {
            center.add(request) { error in
                if let error { AppLog.warning("Notification not scheduled: \(error.localizedDescription)", category: "notifications") }
            }
        }
        removeDeliveredCoach(keeping: coach.ids)
    }

    /// The coach's notifications of the next 3 days (none without a set-up plan, or when this
    /// device doesn't schedule them).
    func coachSchedule(store: NinaStore, settings: NinaSettings, now: Date, today: DayKey) -> CoachReminders.Schedule {
        let plan = settings.plan
        let kinds = coachKinds
        guard plan.isSetUp, coachOnThisDevice, !kinds.isEmpty else { return .empty }
        var input = CoachReminders.Input(plan: plan, now: now, today: today, kinds: kinds)
        input.dayTypeMarks = settings.dayTypeMarks
        input.energyUnit = settings.energyUnit
        input.meals = settings.meals
        let health = CoachContext.latestHealthReadings
        let signal = store.weightSignal(adding: health, settings: settings)
        let schedule = store.bodySchedule(plan: plan, signal: signal, today: today)
        for offset in 0..<CoachReminders.windowDays {
            let day = today.adding(days: offset)
            input.targets[day] = settings.targets(for: day)
            if signal.morning(on: day) != nil { input.weighedIn.insert(day) }
            input.checkStates[day] = store.checkStates(on: day)
        }
        // One day more: the evening before a full set on the day after the window.
        for offset in 0...CoachReminders.windowDays {
            let day = today.adding(days: offset)
            input.bodyDue[day] = schedule.dueItems(on: day)
        }
        input.lastWeight = store.weightReadings(adding: health).max { $0.time < $1.time }?.kilograms
        input.lastTape = CoachReminders.lastTape(store.tapeRecords())
        input.checkInKeys = store.checkInKeys()
        input.lastFullSet = schedule.fullDays.last
        input.checkpoint = signal.checkpointCrossing(in: plan, through: today)
        input.reviews = store.phaseReviews()
        input.reviewPlannedAt = reviewPlannedAt
        return CoachReminders.plan(input)
    }

    /// A review notification comes once: the first time it is planned is kept.
    private func rememberReviews(_ schedule: CoachReminders.Schedule) {
        let prefix = CoachReminders.idPrefix + "phase.review."
        var stored = reviewPlannedAt
        var changed = false
        for item in schedule.requests where item.id.hasPrefix(prefix) {
            let phaseID = String(item.id.dropFirst(prefix.count))
            if stored[phaseID] == nil {
                stored[phaseID] = item.date
                changed = true
            }
        }
        if changed { reviewPlannedAt = stored }
    }

    /// Delivered coach notifications whose task is done (or whose day is over) leave the
    /// Notification Center.
    private func removeDeliveredCoach(keeping ids: Set<String>) {
        let prefix = CoachReminders.idPrefix
        center.getDeliveredNotifications { notifications in
            let stale = notifications.map(\.request.identifier).filter { $0.hasPrefix(prefix) && !ids.contains($0) }
            guard !stale.isEmpty else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    private func registerCategories(coach: [CoachReminders.Category]) {
        guard coachCategories != coach else { return }
        coachCategories = coach
        let eaten = UNNotificationAction(identifier: "eaten", title: "Eaten ✓", options: [])
        let skip = UNNotificationAction(identifier: "skip", title: "Skipped", options: [])
        let log = UNNotificationAction(identifier: "log", title: "Log Now", options: [.foreground])
        var categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: Self.plannedCategory, actions: [eaten, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.reminderCategory, actions: [log], intentIdentifiers: []),
        ]
        for category in coach {
            let actions = category.actions.map { notificationAction($0) }
            categories.insert(UNNotificationCategory(identifier: category.id, actions: actions, intentIdentifiers: []))
        }
        center.setNotificationCategories(categories)
    }

    private func notificationAction(_ action: CoachReminders.Action) -> UNNotificationAction {
        switch action.style {
        case .background:
            return UNNotificationAction(identifier: action.id, title: action.title, options: [])
        case .foreground:
            return UNNotificationAction(identifier: action.id, title: action.title, options: [.foreground])
        case .textInput(let button, let placeholder):
            return UNTextInputNotificationAction(identifier: action.id, title: action.title, options: [],
                                                 textInputButtonTitle: button, textInputPlaceholder: placeholder)
        }
    }

    private func request(_ item: CoachReminders.Request) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.categoryIdentifier = item.category.id
        var info: [String: String] = ["coach": item.id, "url": item.url, "day": item.day.rawValue]
        if let checkID = item.checkID { info["check"] = checkID }
        content.userInfo = info
        content.threadIdentifier = "nina.coach"
        content.sound = .default
        return request(item.id, content, at: item.date)
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
        let coach = info["coach"] as? String
        let url = info["url"] as? String
        let day = info["day"] as? String
        let text = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run {
            if coach != nil {
                NotificationScheduler.shared.handleCoach(action: action, text: text, url: url, day: day)
            } else {
                NotificationScheduler.shared.handle(action: action, entryIDs: ids, meal: meal)
            }
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
            open("\(AppInfo.urlScheme)://add")
        default:
            break
        }
    }

    /// A coach notification's button (or a tap on it): written through the store right in the
    /// banner where it can be, else Nina opens where the task is. Checks and day types count for
    /// the notification's own day (`day`), also when it is tapped after midnight.
    private func handleCoach(action: String, text: String?, url: String?, day raw: String?) {
        if action == UNNotificationDefaultActionIdentifier {
            if let url { open(url) }
            return
        }
        guard let command = CoachReminders.command(action: action, text: text) else { return }
        let store = NinaStore(context: Persistence.shared.container.mainContext)
        let today = store.settings.today()
        let day = raw.flatMap { DayKey($0) }.map { min($0, today) } ?? today
        switch command {
        case .open(let link):
            open(link)
        case .check(let checkID, let state):
            store.setCheck(day: day, checkID: checkID, state: state)
            AppLog.info("Check \(checkID) \(state.rawValue) from a notification", category: "notifications")
            followUp(store)
        case .dayType(let typeID):
            store.setDayType(day: day, typeID: typeID)
            AppLog.info("Day type \(typeID) picked from a notification", category: "notifications")
            followUp(store)
        case .weight(let kilograms):
            if logWeight(kilograms, typed: text ?? "", store: store) { followUp(store) }
        case .tape(let site, let centimeters):
            if logTape(site, centimeters, typed: text ?? "", store: store) { followUp(store) }
        }
    }

    /// After a write from a banner the notifications follow at once (the morning one loses its
    /// button, a done check its reminder), also when the app was started in the background for it.
    private func followUp(_ store: NinaStore) {
        reschedule(context: store.context, settings: store.coachSettings(adding: CoachContext.latestHealthReadings))
    }

    /// "Weight…" in the morning banner: a plausible weight is saved (and written to Apple Health
    /// when that's on); anything else – not a number, outside 25–300 kg, more than 3 kg from the
    /// 7-day average – comes back as "Is that right?", which opens the weigh-in sheet prefilled.
    /// Returns whether the weight was saved.
    @discardableResult
    private func logWeight(_ kilograms: Double?, typed: String, store: NinaStore) -> Bool {
        let settings = store.settings
        let now = Date()
        let today = settings.today(now: now)
        let signal = store.weightSignal(adding: CoachContext.latestHealthReadings, settings: settings)
        if let kilograms, case .ok = signal.sanity(kilograms, on: today) {
            store.addWeight(kilograms, day: today, time: now)
            let health = HealthService(enabled: true)
            Task { await health.writeWeight(kilograms, date: now) }
            AppLog.info("Weight saved from a notification", category: "notifications")
            return true
        }
        let value = kilograms ?? CoachReminders.number(from: typed)
        let content = UNMutableNotificationContent()
        let shown = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        content.title = value == nil ? "That didn't look like a weight" : "\(shown.isEmpty ? "Your weight" : shown) – is that right?"
        content.body = "Tap to check it in \(AppInfo.name) before it's saved."
        let link = value.map { "\(AppInfo.urlScheme)://weigh?value=\(NumberText.plain($0, decimals: 2))" } ?? "\(AppInfo.urlScheme)://weigh"
        content.userInfo = ["coach": Self.weighCheckID, "url": link]
        content.sound = .default
        center.add(UNNotificationRequest(identifier: Self.weighCheckID, content: content, trigger: nil))
        return false
    }

    /// "Waist…" in the morning banner: a plausible value is saved as a tape measurement for today
    /// (morning and fasted when typed before the morning cutoff with nothing eaten logged yet,
    /// else "later"). Anything else – not a number, outside the site's range, more than 3 cm from
    /// a reading in the last 7 days – comes back as "Is that right?", which opens the measure
    /// sheet. Returns whether it was saved.
    @discardableResult
    private func logTape(_ site: BodySite, _ centimeters: Double?, typed: String, store: NinaStore) -> Bool {
        let settings = store.settings
        let calendar = store.calendar
        let now = Date()
        let today = settings.today(now: now)
        if let centimeters,
           !CoachReminders.tapeNeedsALook(centimeters, site: site, on: today, records: store.tapeRecords(), calendar: calendar) {
            let hasEaten = store.entries(on: today).contains { $0.entryStatus == .eaten && $0.time <= now }
            let conditions = BodyProtocol.automatic(at: now, cutoffMinutes: settings.plan.routine.morningCutoffMinutes,
                                                    hasEaten: hasEaten, calendar: calendar)
            let values = BodyValues([site: centimeters])
            store.addMeasurement(BodyMeasurementDraft(day: today, time: now, kind: .tape, values: values,
                                                      conditions: BodyProtocol.encode(conditions)))
            AppLog.info("Tape value saved from a notification", category: "notifications")
            return true
        }
        let shown = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = UNMutableNotificationContent()
        content.title = shown.isEmpty ? "\(site.title) – is that right?" : "\(site.title) \(shown) – is that right?"
        if centimeters == nil {
            content.body = "That doesn't look like a value in centimeters. Tap to measure in \(AppInfo.name)."
        } else {
            let limit = NumberText.plain(BodyReadings.jumpLimit, decimals: 1)
            content.body = "That's more than \(limit) cm from last time. Tap to check it in \(AppInfo.name) before it's saved."
        }
        content.userInfo = ["coach": Self.tapeCheckID, "url": "\(AppInfo.urlScheme)://measure?mode=weekly"]
        content.sound = .default
        center.add(UNNotificationRequest(identifier: Self.tapeCheckID, content: content, trigger: nil))
        return false
    }

    /// Opens a nina:// URL in the app: kept as pending and announced after a moment, so a window
    /// that is just starting listens. Whoever takes it first opens it (RootView's `.task` on a cold
    /// start, else its `.onReceive`), so it opens once.
    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        pendingURL = url
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            NotificationCenter.default.post(name: .ninaOpenURL, object: url)
        }
    }
}

extension Notification.Name {
    /// A notification asked to open a URL: RootView takes it with
    /// `NotificationScheduler.shared.takePendingURL()` (posted by `NotificationScheduler` only).
    static let ninaOpenURL = Notification.Name("at.binisoft.nina.openURL")
}
