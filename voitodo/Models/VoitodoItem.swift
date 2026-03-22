import Foundation
import SwiftData

@Model
final class VoitodoItem {
    var id: UUID = UUID()
    var text: String = ""
    var audioFileURL: URL?
    var timestamp: Date = Date()
    var isCompleted: Bool = false
    var reminderDate: Date? // Newly added field to track the reminder time
    var summary: String? // Added for AI Summarization
    var isCalendared: Bool? // Optional to support smooth schema migrations for existing installs
    var eventIdentifier: String? // Added to support Undo calendar
    var completionDate: Date? // Track when it was completed for Undo timeouts
    var notificationFired: Bool = false // True once the reminder notification has been delivered
    
    init(text: String, audioFileURL: URL? = nil, timestamp: Date = Date(), isCompleted: Bool = false, reminderDate: Date? = nil, summary: String? = nil, isCalendared: Bool? = nil, eventIdentifier: String? = nil, completionDate: Date? = nil, notificationFired: Bool = false) {
        self.id = UUID()
        self.text = text
        self.audioFileURL = audioFileURL
        self.timestamp = timestamp
        self.isCompleted = isCompleted
        self.reminderDate = reminderDate
        self.summary = summary
        self.isCalendared = isCalendared
        self.eventIdentifier = eventIdentifier
        self.completionDate = completionDate
        self.notificationFired = notificationFired
    }
}
