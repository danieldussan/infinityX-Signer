import Foundation
import UserNotifications
import InfinityXCore

/// Local notifications ahead of certificate expiry (7 days and 1 day before), one pair per distinct expiry date.
enum ExpiryAlerts {
    private static let prefix = "cert-expiry-"

    /// Asks permission the first time, then replaces every pending reminder with the current set.
    static func reschedule(for records: [AppRecord]) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let groups = Dictionary(grouping: records.compactMap { r in r.cert?.expiresAt.map { ($0, r) } },
                                    by: { Int($0.0.timeIntervalSince1970) })
            center.getPendingNotificationRequests { pending in
                let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
                center.removePendingNotificationRequests(withIdentifiers: old)
                for (stamp, items) in groups {
                    let expiry = Date(timeIntervalSince1970: TimeInterval(stamp))
                    let count = items.count
                    for reminder in expiryReminders(expiry: expiry) {
                        let content = UNMutableNotificationContent()
                        content.title = "Certificado por vencer"
                        let when = reminder.daysBefore == 1 ? "mañana" : "en \(reminder.daysBefore) días"
                        content.body = "\(count) app\(count == 1 ? "" : "s") firmada\(count == 1 ? "" : "s") dejará\(count == 1 ? "" : "n") de abrir \(when). Re-fírmalas con un certificado nuevo."
                        content.sound = .default
                        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                                    from: reminder.fire)
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                        center.add(UNNotificationRequest(identifier: "\(prefix)\(stamp)-\(reminder.daysBefore)",
                                                         content: content, trigger: trigger))
                    }
                }
            }
        }
    }
}
