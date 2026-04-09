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
    
    // Called when the user taps the notification
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        if identifier.starts(with: "item-") {
            let uuidString = identifier.replacingOccurrences(of: "item-", with: "")
            if let id = UUID(uuidString: uuidString) {
                // Ensure atomic execution of both "fired" state and "completed" state if applicable
                Task {
                    await processNotificationAction(id: id, actionIdentifier: response.actionIdentifier)
                    completionHandler()
                }
                return
            }
        }
        completionHandler()
    }
    
    // Called when a notification is delivered while the app is in the foreground (auto-delivery)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let identifier = notification.request.identifier
        if identifier.starts(with: "item-") {
            let uuidString = identifier.replacingOccurrences(of: "item-", with: "")
            if let id = UUID(uuidString: uuidString) {
                Task {
                    await processNotificationAction(id: id, actionIdentifier: nil)
                    completionHandler([.banner, .sound])
                }
                return
            }
        }
        completionHandler([.banner, .sound])
    }
    
    /// Consolidated, atomic handler for notification actions. 
    /// This prevents race conditions where iOS terminates a second task while the first is still saving.
    private func processNotificationAction(id: UUID, actionIdentifier: String?) async {
        await MainActor.run {
            let container = voitodoApp.sharedModelContainer
            let context = container.mainContext
            let descriptor = FetchDescriptor<VoitodoItem>()
            
            if let items = try? context.fetch(descriptor), let item = items.first(where: { $0.id == id }) {
                var requiresSave = false
                
                // 1. Always mark fired (since it was delivered/tapped)
                if !item.notificationFired {
                    item.notificationFired = true
                    requiresSave = true
                }
                
                // 2. Mark complete if requested
                if actionIdentifier == "COMPLETE_ACTION" && !item.isCompleted {
                    item.isCompleted = true
                    item.completionDate = Date()
                    requiresSave = true
                }
                
                if requiresSave {
                    try? context.save()
                    if actionIdentifier == "COMPLETE_ACTION" {
                        updateBadgeCount()
                    }
                }
            }
        }
    }
    
    // Updates the iOS App Icon Badge to reflect the total number of uncompleted tasks.
    func updateBadgeCount() {
        Task { @MainActor in
            let container = voitodoApp.sharedModelContainer
            let context = container.mainContext
            // Note: SwiftData predicate filtering on boolean isn't always stable in early iOS 17. 
            // Using in-memory filter as a safe fallback for the badge count.
            let descriptor = FetchDescriptor<VoitodoItem>()
            if let allItems = try? context.fetch(descriptor) {
                let uncompletedCount = allItems.filter { !$0.isCompleted }.count
                if #available(iOS 16.0, *) {
                    UNUserNotificationCenter.current().setBadgeCount(uncompletedCount)
                } else {
                    Task { @MainActor in
                        // Older method (fallback)
                    }
                }
            }
        }
    }
    
    // Non-async func purely to calculate tomorrow's date for UI display
    // Non-async func to calculate the next 9:00 AM presentation with a minimum 3-hour breathing room
    func getNextReminderDate() -> Date? {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = 9
        components.minute = 0
        components.second = Int.random(in: 0...59) // Randomize second slightly to avoid exact collision
        
        guard let todays9AM = Calendar.current.date(from: components) else { return nil }
        
        let difference = todays9AM.timeIntervalSince(now)
        
        if difference >= 3 * 3600 {
            // It's 3+ hours before today's 9:00 AM (e.g. 5:00 AM), schedule for today at 9:00 AM
            return todays9AM
        } else {
            // Less than 3 hours or already past 9:00 AM, schedule for tomorrow at 9:00 AM
            return Calendar.current.date(byAdding: .day, value: 1, to: todays9AM)
        }
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
            content.title = "Whatodo Reminder"
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
        content.title = "Whatodo Summary"
        content.body = "You captured \(count) thoughts yesterday. Open the app to review them."
        content.sound = .default
        content.threadIdentifier = "voitodo.reminders.daily"
        content.userInfo = ["count": count]
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "summary", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    func cancelHybridReminder(for id: UUID) async {
        let center = UNUserNotificationCenter.current()
        
        // Remove individual notification if it exists for this item
        center.removePendingNotificationRequests(withIdentifiers: ["item-\(id.uuidString)"])
        
        // If there's a summary instead, decrement its count
        let requests = await center.pendingNotificationRequests()
        if let summary = requests.first(where: { $0.identifier == "summary" }),
           let currentCount = summary.content.userInfo["count"] as? Int {
            if currentCount > 1 {
                // Decrement and update the summary
                let dateTrigger = summary.trigger as? UNCalendarNotificationTrigger
                if let dateComponents = dateTrigger?.dateComponents {
                    await updateSummaryNotification(count: currentCount - 1, dateComponents: dateComponents)
                }
            } else {
                // Count dropped to 0, remove the summary entirely
                center.removePendingNotificationRequests(withIdentifiers: ["summary"])
            }
        }
    }
}
