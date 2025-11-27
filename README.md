# NotificationInjectionGateway

---

# 📬 Swift Notification Scheduler

A lightweight, fully automatic **remote-configurable notification scheduling system** for iOS.
It loads a JSON config from your server, parses it, and schedules one-time notifications with progressive delays — without requiring any manual logic inside the app.

---

## 🚀 Features

* Fetches notification configuration from a remote JSON file
* Schedules **one-time notifications** based on `dayOffset`
* Supports **custom titles & subtitles per notification**
* Automatically avoids weekends (`weekdaysOnly`)
* Prevents duplicates: schedules notifications **only once** per install
* Auto-retries permission check if user denies it
* Clean SwiftUI integration via `.notificationManager()` modifier
* Fully configurable without updating the app

---

## 📂 Project Structure

### 🔧 Core Library

Located in: **NotificationManager.swift**


Contains:

* `NotificationConfigManager` — loads and decodes JSON config
* `NotificationScheduler` — schedules notifications
* SwiftUI `.notificationManager(url:)` View extension

### 📄 JSON Configuration Example

Stored as: **notification-config.json**


Defines:

* Global settings
* Default notification content
* List of notifications with offsets

---

## 📡 JSON Configuration Format

Here is the structure expected by the library:

```json
{
  "config": {
    "version": "1.0",
    "description": "Description of your schedule",
    "isPersistent": true,
    "fixedTime": "07:00",
    "weekdaysOnly": true
  },
  "notificationContent": {
    "title": "Default title",
    "subtitle": "Default subtitle"
  },
  "schedules": [
    {
      "id": 1,
      "dayOffset": 1,
      "description": "Example",
      "title": "Optional override",
      "subtitle": "Optional override"
    }
  ]
}
```

### Key Parameters

| Field              | Meaning                                            |
| ------------------ | -------------------------------------------------- |
| `dayOffset`        | Days from today when the notification is scheduled |
| `fixedTime`        | Time of day (HH:mm) to schedule each notification  |
| `weekdaysOnly`     | Moves notifications from Sat/Sun to Monday         |
| `title`/`subtitle` | Overrides default content if provided              |

---

## 🧩 Installation

Just drop `NotificationManager.swift` into your project.

No other dependencies required.

---

## 🛠 Usage (SwiftUI)

Call the `.notificationManager(url:)` modifier anywhere in your view tree:

```swift
struct ContentView: View {
    var body: some View {
        Text("Hello")
            .notificationManager(url: "https://your-domain.com/notification-config.json")
    }
}
```

That's it — the library will:

1. Ask for notification permission
2. Check whether notifications are already scheduled
3. Download remote config
4. Parse JSON
5. Schedule notifications only once

---

## 🔁 Scheduling Logic

### How it chooses the date:

1. `today + dayOffset`
2. Applies fixed time (`fixedTime`)
3. If `weekdaysOnly = true`:

   * Saturday → +2 days
   * Sunday → +1 day
4. Creates a `UNCalendarNotificationTrigger`

### Identifiers

Every notification uses:

```
app_notification_<id>
```

### Persistence

If notifications already exist → scheduling is skipped.
This protects user experience.

---

## 🧪 Debug Output

The library prints everything:

* Raw JSON preview
* Parsed config validate
* Scheduler progress
* Errors: decoding, HTTP, permissions, scheduling failures

Perfect for testing + TestFlight logs.

---

## 🌐 Hosting Requirements

Your JSON must be accessible via HTTPS, for example:

```
https://your-domain.com/notification-config.json
```

Content-type is not strict, JSON decoding is automatic.

---

## 🛡 Requirements

* iOS 15+
* Swift 5.7+
* SwiftUI

---

## ❗ Notes & Limitations

* Repeating notifications are **not** supported — this library is designed for **one-shot sequences**.
* Editing JSON on the server changes notifications **only before scheduling**.
* Once notifications are created, iOS requires manual cleanup (app reinstall or manual cancellation) if you want to reschedule.

---

## 🤝 Contributing

Pull requests and improvements are welcome!

---

## 📄 License

CampStudio License

---
