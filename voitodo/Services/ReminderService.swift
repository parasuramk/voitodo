import Foundation
import UserNotifications
import SwiftData

class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()
    
    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // Define Actionable Categories
        let completeAction = UNNotificationAction(identifier: "COMPLETE_ACTION", title: "Mark Complete", options: [])
        let category = UNNotificationCategory(identifier: "VOITODO_ITEM", actions: [completeAction], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        
        requestAuthorization()
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    // Delegate method handles the background action button taps
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "COMPLETE_ACTION" {
            let identifier = response.notification.request.identifier
            if identifier.starts(with: "item-") {
                let uuidString = identifier.replacingOccurrences(of: "item-", with: "")
                if let id = UUID(uuidString: uuidString) {
                    markItemComplete(id: id)
                }
            }
        }
        completionHandler()
    }
    
    private func markItemComplete(id: UUID) {
        Task { @MainActor in
            let container = voitodoApp.sharedModelContainer
            let context = container.mainContext
            let descriptor = FetchDescriptor<VoitodoItem>()
            if let items = try? context.fetch(descriptor), let item = items.first(where: { $0.id == id }) {
                item.isCompleted = true
                try? context.save()
            }
        }
    }
    
    // Non-async func purely to calculate tomorrow's date for UI display
    func getTomorrow9AM() -> Date? {
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
            let tomorrowComponents = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
            dateComponents.year = tomorrowComponents.year
            dateComponents.month = tomorrowComponents.month
            dateComponents.day = tomorrowComponents.day
            dateComponents.hour = 9
            dateComponents.minute = 0
            dateComponents.second = Int.random(in: 0...59)
            return Calendar.current.date(from: dateComponents)
        }
        return nil
    }

    func scheduleHybridReminder(text: String, id: UUID, triggerDate: Date) async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        
        let itemRequests = requests.filter { $0.identifier.starts(with: "item-") }
        let summaryRequest = requests.first { $0.identifier == "summary" }
        
        let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
        
        // Hybrid Logic
        if let summary = summaryRequest {
            // We already passed the 5-item threshold earlier today.
            let currentCount = summary.content.userInfo["count"] as? Int ?? 4
            await updateSummaryNotification(count: currentCount + 1, dateComponents: dateComponents)
        } else if itemRequests.count >= 4 {
            // This is our 5th item. We switch from individual notifications to a summary notification.
            let identifiersToCancel = itemRequests.map { $0.identifier }
            center.removePendingNotificationRequests(withIdentifiers: identifiersToCancel)
            await updateSummaryNotification(count: 5, dateComponents: dateComponents)
        } else {
            // Under 5 limit. Schedule as an individual actionable notification.
            let content = UNMutableNotificationContent()
            content.title = "Voitodo Reminder"
            content.body = text
            content.sound = .default
            content.categoryIdentifier = "VOITODO_ITEM"
            content.threadIdentifier = "voitodo.reminders.daily"
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(identifier: "item-\(id.uuidString)", content: content, trigger: trigger)
            
            do {
                try await center.add(request)
            } catch {
                print("Failed to schedule item push: \(error)")
            }
        }
    }
    
    private func updateSummaryNotification(count: Int, dateComponents: DateComponents) async {
        let content = UNMutableNotificationContent()
        content.title = "Voitodo Summary"
        content.body = "You captured \(count) thoughts yesterday. Open the app to review them."
        content.sound = .default
        content.threadIdentifier = "voitodo.reminders.daily"
        content.userInfo = ["count": count]
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "summary", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
