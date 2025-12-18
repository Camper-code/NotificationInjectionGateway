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

// MARK: - Notification Scheduler

public final class NotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let configManager: NotificationConfigManager
    private let userDefaults: UserDefaults

    private let udLastAppliedVersionKey = "NIG_lastAppliedConfigVersion"

    public init(endpoint: String, userDefaults: UserDefaults = .standard) {
        self.configManager = NotificationConfigManager(endpoint: endpoint)
        self.userDefaults = userDefaults
    }

    public func scheduleAppNotifications(force: Bool = false) {
        requestPermissionIfNeeded { [weak self] granted in
            guard let self else { return }

            guard granted else {
                print("⚠️ Notifications not granted")
                return
            }

            self.processScheduling(force: force)
        }
    }

    private func requestPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)

            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, err in
                    if let err { print("❌ requestAuthorization error: \(err.localizedDescription)") }
                    completion(granted)
                }

            case .denied:
                completion(false)

            @unknown default:
                completion(false)
            }
        }
    }

    private func processScheduling(force: Bool) {
        center.getPendingNotificationRequests { [weak self] existingRequests in
            guard let self else { return }

            let existingIds = Set(existingRequests.map(\.identifier))
            print("📦 Pending notifications: \(existingIds.count)")

            self.configManager.getNotificationConfig { [weak self] config in
                guard let self else { return }
                guard let config else {
                    print("❌ Config is nil")
                    return
                }

                let lastAppliedVersion = self.userDefaults.string(forKey: self.udLastAppliedVersionKey)
                let shouldSkipBecausePersistent =
                    config.config.isPersistent && !force && (lastAppliedVersion == config.config.version) && !existingIds.isEmpty

                if shouldSkipBecausePersistent {
                    print("✅ Persistent config already applied (version \(config.config.version)). Skipping.")
                    return
                }

                self.applyConfig(config, existingIds: existingIds)
            }
        }
    }

    private func applyConfig(_ config: NotificationConfig, existingIds: Set<String>) {
        print("✅ Applying config v\(config.config.version)")
        let fixed = parseFixedTime(config.config.fixedTime)

        for schedule in config.schedules {
            let identifier = makeIdentifier(configVersion: config.config.version, scheduleId: schedule.id)

            if existingIds.contains(identifier) {
                continue
            }

            let title = schedule.title ?? config.notificationContent.title
            let subtitle = schedule.subtitle ?? config.notificationContent.subtitle

            let targetDate = computeFireDate(
                dayOffset: schedule.dayOffset,
                fixedTime: fixed,
                weekdaysOnly: config.config.weekdaysOnly
            )

            scheduleNotification(
                identifier: identifier,
                title: title,
                subtitle: subtitle,
                fireDate: targetDate
            )
        }

        self.userDefaults.setValue(config.config.version, forKey: self.udLastAppliedVersionKey)
    }

    private func scheduleNotification(identifier: String, title: String, subtitle: String, fireDate: Date) {
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
                print("✅ Scheduled \(identifier) at \(fireDate)")
            }
        }
    }

    private func makeIdentifier(configVersion: String, scheduleId: Int) -> String {
        "NIG_v\(configVersion)_id\(scheduleId)"
    }

    private func parseFixedTime(_ fixedTime: String) -> (hour: Int, minute: Int) {
        
        let parts = fixedTime.split(separator: ":").map(String.init)
        let hour = Int(parts.first ?? "") ?? 9
        let minute = Int(parts.dropFirst().first ?? "") ?? 0
        return (hour, minute)
    }

    private func computeFireDate(dayOffset: Int, fixedTime: (hour: Int, minute: Int), weekdaysOnly: Bool) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current

        let now = Date()
        var date = calendar.date(byAdding: .day, value: max(0, dayOffset), to: now) ?? now

        
        date = calendar.date(bySettingHour: fixedTime.hour, minute: fixedTime.minute, second: 0, of: date) ?? date

        if weekdaysOnly {
            // 1 = Sunday, 7 = Saturday
            while true {
                let weekday = calendar.component(.weekday, from: date)
                if weekday == 1 || weekday == 7 {
                    date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
                    date = calendar.date(bySettingHour: fixedTime.hour, minute: fixedTime.minute, second: 0, of: date) ?? date
                    continue
                }
                break
            }
        }

  
        if date <= now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            date = calendar.date(bySettingHour: fixedTime.hour, minute: fixedTime.minute, second: 0, of: date) ?? date
        }

        return date
    }
}

// MARK: - SwiftUI View Extension (public)

public extension View {

    func notificationManager(url: String, force: Bool = false) -> some View {
        self.onAppear {
            NotificationScheduler(endpoint: url).scheduleAppNotifications(force: force)
        }
    }
}
