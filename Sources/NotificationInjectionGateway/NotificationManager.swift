import Foundation
import UserNotifications
import SwiftUI

// MARK: - Config Models

public struct NotificationConfig: Codable {
    public let config: ConfigMeta
    public let notificationContent: NotificationContent
    public let schedules: [NotificationSchedule]
}

public struct ConfigMeta: Codable {
    public let version: String
    public let description: String
    public let isPersistent: Bool
    public let fixedTime: String      // "HH:mm"
    public let weekdaysOnly: Bool

    public init(version: String, description: String, isPersistent: Bool, fixedTime: String, weekdaysOnly: Bool) {
        self.version = version
        self.description = description
        self.isPersistent = isPersistent
        self.fixedTime = fixedTime
        self.weekdaysOnly = weekdaysOnly
    }
}

public struct NotificationContent: Codable {
    public let title: String
    public let subtitle: String

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

public struct NotificationSchedule: Codable {
    public let id: Int
    public let dayOffset: Int
    public let description: String
    public let title: String?
    public let subtitle: String?

    public init(id: Int, dayOffset: Int, description: String, title: String?, subtitle: String?) {
        self.id = id
        self.dayOffset = dayOffset
        self.description = description
        self.title = title
        self.subtitle = subtitle
    }
}

// MARK: - Config Manager

public final class NotificationConfigManager {
    private let configEndpoint: String

    public init(endpoint: String) {
        self.configEndpoint = endpoint
    }

    public func getNotificationConfig(completion: @escaping (NotificationConfig?) -> Void) {
        guard let url = URL(string: configEndpoint) else {
            print("❌ Invalid URL endpoint: \(configEndpoint)")
            completion(nil)
            return
        }

        print("🌐 Downloading config: \(configEndpoint)")

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let err = error {
                print("❌ Config download error: \(err.localizedDescription)")
                completion(nil)
                return
            }

            guard let http = response as? HTTPURLResponse else {
                print("❌ No HTTP response")
                completion(nil)
                return
            }

            guard (200...299).contains(http.statusCode) else {
                print("❌ Bad status code: \(http.statusCode)")
                completion(nil)
                return
            }

            guard let data = data else {
                print("❌ Empty config response")
                completion(nil)
                return
            }

            do {
                let decoder = JSONDecoder()
                let config = try decoder.decode(NotificationConfig.self, from: data)
                print("✅ Config decoded successfully, version: \(config.config.version)")
                completion(config)
            } catch let DecodingError.keyNotFound(key, context) {
                print("❌ Key not found: \(key.stringValue)")
                print("   Path: \(context.codingPath.map(\.stringValue).joined(separator: " -> "))")
                completion(nil)
            } catch let DecodingError.typeMismatch(type, context) {
                print("❌ Type mismatch: \(type)")
                print("   Path: \(context.codingPath.map(\.stringValue).joined(separator: " -> "))")
                completion(nil)
            } catch let DecodingError.valueNotFound(type, context) {
                print("❌ Value not found: \(type)")
                print("   Path: \(context.codingPath.map(\.stringValue).joined(separator: " -> "))")
                completion(nil)
            } catch {
                print("❌ Decoding error: \(error.localizedDescription)")
                completion(nil)
            }
        }

        task.resume()
    }
}

// MARK: - Scheduled Notification Info

public struct ScheduledNotificationInfo: Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let fireDate: Date?

    public init(request: UNNotificationRequest) {
        self.identifier = request.identifier
        self.title = request.content.title
        self.body = request.content.body
        if let trigger = request.trigger as? UNCalendarNotificationTrigger {
            self.fireDate = trigger.nextTriggerDate()
        } else {
            self.fireDate = nil
        }
    }
}

// MARK: - Notification Scheduler

public final class NotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let configManager: NotificationConfigManager
    private let userDefaults: UserDefaults

    private let udLastAppliedVersionKey = "NIG_lastAppliedConfigVersion"
    private let notificationPrefix = "NIG_v"

    public init(endpoint: String, userDefaults: UserDefaults = .standard) {
        print("🎯 NotificationScheduler init with endpoint: \(endpoint)")
        self.configManager = NotificationConfigManager(endpoint: endpoint)
        self.userDefaults = userDefaults
    }

    // MARK: - Public: Schedule only

    public func scheduleAppNotifications(force: Bool = false) {
        print("🚀 scheduleAppNotifications called, force: \(force)")
        requestPermissionIfNeeded { granted in
            print("🔐 Permission result: \(granted)")
            guard granted else {
                print("⚠️ Notifications not granted")
                return
            }
            self.processScheduling(force: force, completion: nil)
        }
    }

    // MARK: - Public: Schedule then fetch (main combined method)

    public func scheduleAndFetch(force: Bool = false, completion: @escaping ([ScheduledNotificationInfo]) -> Void) {
        print("🚀 scheduleAndFetch called, force: \(force)")
        requestPermissionIfNeeded { granted in
            print("🔐 Permission result: \(granted)")
            guard granted else {
                print("⚠️ Notifications not granted")
                completion([])
                return
            }
            self.processScheduling(force: force) {
                self.getAllScheduledNotifications(completion: completion)
            }
        }
    }

    // MARK: - Permission

    private func requestPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        print("🔍 Checking notification permission...")
        center.getNotificationSettings { settings in
            print("📋 Current authorization status: \(settings.authorizationStatus.rawValue)")
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)

            case .notDetermined:
                print("❓ Permission not determined, requesting...")
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, err in
                    if let err {
                        print("❌ requestAuthorization error: \(err.localizedDescription)")
                    }
                    print("✅ Permission granted: \(granted)")
                    completion(granted)
                }

            case .denied:
                print("🚫 Permission denied by user")
                completion(false)

            @unknown default:
                print("⚠️ Unknown permission status")
                completion(false)
            }
        }
    }

    // MARK: - Scheduling Logic

    private func processScheduling(force: Bool, completion: (() -> Void)?) {
        print("⚙️ Processing scheduling, force: \(force)")
        center.getPendingNotificationRequests { existingRequests in
            let existingIds = Set(existingRequests.map(\.identifier))
            print("📦 Pending notifications: \(existingIds.count)")
            if !existingIds.isEmpty {
                print("   Existing IDs: \(existingIds.sorted())")
            }

            print("📡 Fetching config from server...")
            self.configManager.getNotificationConfig { config in
                guard let config = config else {
                    print("❌ Config is nil")
                    completion?()
                    return
                }

                print("✅ Config received, version: \(config.config.version)")
                print("   isPersistent: \(config.config.isPersistent)")
                print("   schedules count: \(config.schedules.count)")

                let lastAppliedVersion = self.userDefaults.string(forKey: self.udLastAppliedVersionKey)
                print("💾 Last applied version: \(lastAppliedVersion ?? "none")")

                let versionChanged = lastAppliedVersion != nil && lastAppliedVersion != config.config.version

                if versionChanged {
                    print("🔄 Config version changed from \(lastAppliedVersion!) to \(config.config.version)")
                    print("🗑️ Removing all old notifications...")
                    self.removeAllManagedNotifications {
                        print("✅ Old notifications removed, applying new config...")
                        self.applyConfig(config, existingIds: Set(), completion: completion)
                    }
                    return
                }

                let shouldSkipBecausePersistent =
                    config.config.isPersistent &&
                    !force &&
                    (lastAppliedVersion == config.config.version) &&
                    !existingIds.isEmpty

                if shouldSkipBecausePersistent {
                    print("✅ Persistent config already applied (version \(config.config.version)). Skipping.")
                    completion?()
                    return
                }

                print("🔄 Applying config...")
                self.applyConfig(config, existingIds: existingIds, completion: completion)
            }
        }
    }

    private func removeAllManagedNotifications(completion: @escaping () -> Void) {
        center.getPendingNotificationRequests { requests in
            let managedIds = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.notificationPrefix) }

            if managedIds.isEmpty {
                print("   No managed notifications to remove")
                completion()
                return
            }

            print("   Removing \(managedIds.count) notifications:")
            for id in managedIds {
                print("   - \(id)")
            }

            self.center.removePendingNotificationRequests(withIdentifiers: managedIds)
            completion()
        }
    }

    private func applyConfig(_ config: NotificationConfig, existingIds: Set<String>, completion: (() -> Void)?) {
        print("✅ Applying config v\(config.config.version)")
        let fixed = parseFixedTime(config.config.fixedTime)
        print("⏰ Fixed time: \(fixed.hour):\(fixed.minute)")
        print("📅 Weekdays only: \(config.config.weekdaysOnly)")

        var scheduledCount = 0
        var skippedCount = 0
        var usedDates = Set<String>()

        // Collect requests to schedule
        var requestsToSchedule: [(identifier: String, title: String, subtitle: String, fireDate: Date)] = []

        for schedule in config.schedules {
            let identifier = makeIdentifier(configVersion: config.config.version, scheduleId: schedule.id)

            if existingIds.contains(identifier) {
                print("⏭️ Skipping \(identifier) - already exists")
                skippedCount += 1
                continue
            }

            let title = schedule.title ?? config.notificationContent.title
            let subtitle = schedule.subtitle ?? config.notificationContent.subtitle

            var targetDate = computeFireDate(
                dayOffset: schedule.dayOffset,
                fixedTime: fixed,
                weekdaysOnly: config.config.weekdaysOnly
            )

            let calendar = Calendar.current
            let dateKey = makeDateKey(date: targetDate, calendar: calendar)

            if usedDates.contains(dateKey) {
                print("⚠️ Date conflict detected for \(dateKey), moving to next available day")
                targetDate = findNextAvailableDate(
                    startDate: targetDate,
                    usedDates: &usedDates,
                    calendar: calendar,
                    fixedTime: fixed,
                    weekdaysOnly: config.config.weekdaysOnly
                )
            }

            usedDates.insert(makeDateKey(date: targetDate, calendar: calendar))
            requestsToSchedule.append((identifier, title, subtitle, targetDate))
            scheduledCount += 1
        }

        print("📊 Scheduling complete: \(scheduledCount) to schedule, \(skippedCount) skipped")

        guard !requestsToSchedule.isEmpty else {
            self.userDefaults.setValue(config.config.version, forKey: self.udLastAppliedVersionKey)
            print("💾 Saved version to UserDefaults: \(config.config.version)")
            completion?()
            return
        }

        // Use DispatchGroup to wait for all center.add() calls to finish
        let group = DispatchGroup()

        for item in requestsToSchedule {
            group.enter()
            scheduleNotification(
                identifier: item.identifier,
                title: item.title,
                subtitle: item.subtitle,
                fireDate: item.fireDate
            ) {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.userDefaults.setValue(config.config.version, forKey: self.udLastAppliedVersionKey)
            print("💾 Saved version to UserDefaults: \(config.config.version)")
            print("✅ All notifications scheduled, calling completion")
            completion?()
        }
    }

    // MARK: - Schedule single notification with completion

    private func scheduleNotification(
        identifier: String,
        title: String,
        subtitle: String,
        fireDate: Date,
        completion: @escaping () -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = subtitle
        content.sound = .default

        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(req) { err in
            if let err {
                print("❌ Failed to schedule \(identifier): \(err.localizedDescription)")
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                print("✅ Scheduled \(identifier)")
                print("   Title: '\(title)'")
                print("   Fire date: \(formatter.string(from: fireDate))")
            }
            completion()
        }
    }

    // MARK: - Helpers

    private func makeIdentifier(configVersion: String, scheduleId: Int) -> String {
        "NIG_v\(configVersion)_id\(scheduleId)"
    }

    private func parseFixedTime(_ fixedTime: String) -> (hour: Int, minute: Int) {
        let parts = fixedTime.split(separator: ":").map(String.init)
        let hour = Int(parts.first ?? "") ?? 9
        let minute = Int(parts.dropFirst().first ?? "") ?? 0
        return (hour, minute)
    }

    private func makeDateKey(date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year!)-\(components.month!)-\(components.day!)"
    }

    private func computeFireDate(dayOffset: Int, fixedTime: (hour: Int, minute: Int), weekdaysOnly: Bool) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current

        let now = Date()
        let baseDay = calendar.startOfDay(for: now)

        let targetDay = addAvailableDays(from: baseDay, days: max(0, dayOffset), calendar: calendar, weekdaysOnly: weekdaysOnly)
        var date = calendar.date(bySettingHour: fixedTime.hour, minute: fixedTime.minute, second: 0, of: targetDay) ?? targetDay

        if date < now {
            let nextTargetDay = addAvailableDays(from: targetDay, days: 1, calendar: calendar, weekdaysOnly: weekdaysOnly)
            date = calendar.date(bySettingHour: fixedTime.hour, minute: fixedTime.minute, second: 0, of: nextTargetDay) ?? nextTargetDay
        }

        return date
    }

    private func findNextAvailableDate(
        startDate: Date,
        usedDates: inout Set<String>,
        calendar: Calendar,
        fixedTime: (hour: Int, minute: Int),
        weekdaysOnly: Bool
    ) -> Date {
        var date = startDate
        var attempts = 0

        while attempts < 365 {
            let nextDay = addAvailableDays(from: calendar.startOfDay(for: date), days: 1, calendar: calendar, weekdaysOnly: weekdaysOnly)
            date = calendar.date(bySettingHour: fixedTime.hour, minute: fixedTime.minute, second: 0, of: nextDay) ?? nextDay

            let dateKey = makeDateKey(date: date, calendar: calendar)
            if !usedDates.contains(dateKey) {
                return date
            }

            attempts += 1
        }

        return date
    }

    private func addAvailableDays(from startDay: Date, days: Int, calendar: Calendar, weekdaysOnly: Bool) -> Date {
        if days == 0 {
            return weekdaysOnly ? shiftToNextWeekdayIfNeeded(day: startDay, calendar: calendar) : startDay
        }

        var d = startDay
        var remaining = days

        while remaining > 0 {
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
            if weekdaysOnly {
                if isWeekday(d, calendar: calendar) {
                    remaining -= 1
                }
            } else {
                remaining -= 1
            }
        }

        return weekdaysOnly ? shiftToNextWeekdayIfNeeded(day: d, calendar: calendar) : d
    }

    private func isWeekday(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday != 1 && weekday != 7
    }

    private func shiftToNextWeekdayIfNeeded(day: Date, calendar: Calendar) -> Date {
        var d = day
        var guardIt = 0
        while !isWeekday(d, calendar: calendar), guardIt < 14 {
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
            guardIt += 1
        }
        return d
    }

    // MARK: - Public Query

    public func getAllScheduledNotifications(completion: @escaping ([ScheduledNotificationInfo]) -> Void) {
        center.getPendingNotificationRequests { requests in
            let infos = requests
                .filter { $0.identifier.hasPrefix(self.notificationPrefix) }
                .map { ScheduledNotificationInfo(request: $0) }
                .sorted {
                    guard let l = $0.fireDate, let r = $1.fireDate else { return false }
                    return l < r
                }
            completion(infos)
        }
    }

    @available(iOS 15.0, macOS 12.0, *)
    public func getAllScheduledNotifications() async -> [ScheduledNotificationInfo] {
        await withCheckedContinuation { continuation in
            getAllScheduledNotifications { continuation.resume(returning: $0) }
        }
    }

    @available(iOS 15.0, macOS 12.0, *)
    public func scheduleAndFetch(force: Bool = false) async -> [ScheduledNotificationInfo] {
        await withCheckedContinuation { continuation in
            scheduleAndFetch(force: force) { continuation.resume(returning: $0) }
        }
    }
}

// MARK: - SwiftUI View Extension

public extension View {

    /// Только планирует уведомления, ничего не возвращает
    func notificationManager(url: String, force: Bool = false) -> some View {
        self.onAppear {
            print("🔔 notificationManager modifier triggered")
            print("   URL: \(url)")
            print("   Force: \(force)")
            let scheduler = NotificationScheduler(endpoint: url)
            scheduler.scheduleAppNotifications(force: force)
        }
    }

    /// Планирует уведомления, затем возвращает список запланированных
    func onScheduledNotifications(
        url: String,
        force: Bool = false,
        completion: @escaping ([ScheduledNotificationInfo]) -> Void
    ) -> some View {
        self.onAppear {
            print("🔔 onScheduledNotifications modifier triggered")
            print("   URL: \(url)")
            print("   Force: \(force)")
            let scheduler = NotificationScheduler(endpoint: url)
            scheduler.scheduleAndFetch(force: force) { notifications in
                DispatchQueue.main.async {
                    completion(notifications)
                }
            }
        }
    }
}
