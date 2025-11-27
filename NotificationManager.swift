import Foundation
import UserNotifications
import SwiftUI

// MARK: - Config Models
struct NotificationConfig: Codable {
    let config: ConfigMeta
    let notificationContent: NotificationContent
    let schedules: [NotificationSchedule]
}

struct ConfigMeta: Codable {
    let version: String
    let description: String
    let isPersistent: Bool
    let fixedTime: String
    let weekdaysOnly: Bool
}

struct NotificationContent: Codable {
    let title: String
    let subtitle: String
}

struct NotificationSchedule: Codable {
    let id: Int
    let dayOffset: Int
    let description: String
    let title: String?
    let subtitle: String?
}

// MARK: - Config Manager
class NotificationConfigManager {
    private let configEndpoint: String
    
    init(endpoint: String) {
        self.configEndpoint = endpoint
    }
    
    func getNotificationConfig(completion: @escaping (NotificationConfig?) -> Void) {
        print("🔍 Loading config from server...")
        fetchConfigFromServer(completion: completion)
    }
    
    private func fetchConfigFromServer(completion: @escaping (NotificationConfig?) -> Void) {
        guard let url = URL(string: configEndpoint) else {
            print("❌ Invalid URL endpoint: \(configEndpoint)")
            completion(nil)
            return
        }
        
        print("🌐 Starting config download from: \(configEndpoint)")
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("❌ No data from server")
                completion(nil)
                return
            }
            
            print("📦 Received data: \(data.count) bytes")
            
        
            if let rawString = String(data: data, encoding: .utf8) {
                print("📄 Raw JSON:\n\(rawString.prefix(500))")
            }
            
            do {
                let decoder = JSONDecoder()
                let config = try decoder.decode(NotificationConfig.self, from: data)
                print("✅ Config successfully parsed!")
                print("   - Version: \(config.config.version)")
                print("   - Notifications: \(config.schedules.count)")
                completion(config)
            } catch let DecodingError.keyNotFound(key, context) {
                print("❌ Missing key: \(key.stringValue)")
                print("   Path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                print("   Description: \(context.debugDescription)")
                completion(nil)
            } catch let DecodingError.typeMismatch(type, context) {
                print("❌ Invalid data type: expected \(type)")
                print("   Path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                print("   Description: \(context.debugDescription)")
                completion(nil)
            } catch let DecodingError.valueNotFound(type, context) {
                print("❌ Value not found for type: \(type)")
                print("   Path: \(context.codingPath.map { $0.stringValue }.joined(separator: " -> "))")
                completion(nil)
            } catch {
                print("❌ Unknown parsing error: \(error)")
                print("   Details: \(error.localizedDescription)")
                completion(nil)
            }
        }
        
        task.resume()
    }
}

// MARK: - Notification Scheduler
class NotificationScheduler {
    
    private let center = UNUserNotificationCenter.current()
    private let configManager: NotificationConfigManager
    
    init(endpoint: String) {
        self.configManager = NotificationConfigManager(endpoint: endpoint)
    }
    
    func scheduleAppNotifications() {
        checkAuthorizationAndSchedule()
    }
    
    private func checkAuthorizationAndSchedule() {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
       
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted {
                        print("✅ Notification permission granted")
                        self.processScheduling()
                    } else {
                        print("❌ User denied notification permission")
                    
                        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                            self.checkAuthorizationAndSchedule()
                        }
                    }
                }
            case .denied:
                print("⚠️ Notifications disabled by user. Checking again in 60 sec...")
               
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                    self.checkAuthorizationAndSchedule()
                }
            case .authorized, .provisional, .ephemeral:
                print("✅ Notification permission already granted")
                self.processScheduling()
            @unknown default:
                print("⚠️ Unknown authorization status")
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                    self.checkAuthorizationAndSchedule()
                }
            }
        }
    }
    
    private func processScheduling() {
        print("🔄 Starting notification scheduling process...")
        
   
        center.getPendingNotificationRequests { existingRequests in
            let existingIds = Set(existingRequests.map { $0.identifier })
            
            if !existingIds.isEmpty {
                print("✅ Found \(existingIds.count) already scheduled notifications")
                print("   Identifiers: \(existingIds.sorted())")
                print("⏭️  Skipping re-scheduling")
                return
            }
            
            print("📭 No scheduled notifications found, starting scheduling...")
            
            self.configManager.getNotificationConfig { config in
                guard let config = config else {
                    print("❌ configManager.getNotificationConfig returned nil")
                    return
                }
                
                print("✅ Received config for scheduling")
                print("   - Title: \(config.notificationContent.title)")
                print("   - Notification count: \(config.schedules.count)")
                
                self.scheduleNotifications(config: config)
            }
        }
    }
    
    private func scheduleNotifications(config: NotificationConfig) {
        let calendar = Calendar.current
        let today = Date()
        
        let timeComponents = config.config.fixedTime.split(separator: ":").compactMap { Int($0) }
        let hour = timeComponents.first ?? 7
        let minute = timeComponents.count > 1 ? timeComponents[1] : 0
        
        for schedule in config.schedules {
            guard let rawDate = calendar.date(byAdding: .day, value: schedule.dayOffset, to: today) else {
                continue
            }
            
            let scheduledDate = adjustDateForBusinessDays(
                date: rawDate,
                calendar: calendar,
                hour: hour,
                minute: minute,
                weekdaysOnly: config.config.weekdaysOnly
            )
            
            let content = UNMutableNotificationContent()

            content.title = schedule.title ?? config.notificationContent.title
            content.body = schedule.subtitle ?? config.notificationContent.subtitle
            content.sound = .default
            
            let triggerComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: scheduledDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            
            let identifier = "app_notification_\(schedule.id)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("❌ Scheduling error #\(schedule.id): \(error.localizedDescription)")
                } else {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm"
                    print("📅 Notification #\(schedule.id) '\(content.title)' scheduled for: \(formatter.string(from: scheduledDate)) (in \(schedule.dayOffset) days)")
                }
            }
        }
    }
    
    private func adjustDateForBusinessDays(
        date: Date,
        calendar: Calendar,
        hour: Int,
        minute: Int,
        weekdaysOnly: Bool
    ) -> Date {
        var resultDate = date
        
        resultDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: resultDate) ?? resultDate
        
        if weekdaysOnly {
            let weekday = calendar.component(.weekday, from: resultDate)
            
            if weekday == 7 {
                resultDate = calendar.date(byAdding: .day, value: 2, to: resultDate)!
            } else if weekday == 1 {
                resultDate = calendar.date(byAdding: .day, value: 1, to: resultDate)!
            }
        }
        
        return resultDate
    }
}

// MARK: - SwiftUI View Extension
extension View {
    func notificationManager(url: String) -> some View {
        self.onAppear {
            let scheduler = NotificationScheduler(endpoint: url)
            scheduler.scheduleAppNotifications()
        }
    }
}

// MARK: - Usage Example
/*
 struct ContentView: View {
     var body: some View {
         VStack {
             Text("Hello, World!")
         }
         .notificationManager(url: "https://your-api.com/notification-config.json")
     }
 }
 */
