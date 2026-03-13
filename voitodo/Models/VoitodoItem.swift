import Foundation
import SwiftData

@Model
final class VoitodoItem {
    var id: UUID
    var text: String
    var audioFileURL: URL?
    var timestamp: Date
    var isCompleted: Bool
    var reminderDate: Date? // Newly added field to track the reminder time
    
    init(text: String, audioFileURL: URL? = nil, timestamp: Date = Date(), isCompleted: Bool = false, reminderDate: Date? = nil) {
        self.id = UUID()
        self.text = text
        self.audioFileURL = audioFileURL
        self.timestamp = timestamp
        self.isCompleted = isCompleted
        self.reminderDate = reminderDate
    }
}
