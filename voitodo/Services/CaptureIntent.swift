import Foundation
import AppIntents
import SwiftData

struct CaptureThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Thought"
    static var description = IntentDescription("Immediately starts recording a new thought in voitodo.")
    
    // This allows it to appear when configuring the iPhone Action Button
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // In a real implementation with heavy background support, we could start recording here directly.
        // For the MVP, since we require microphone and speech permissions that are tied to the main app lifecycle,
        // we use `openAppWhenRun = true` to bring the user directly to the app's recording state.
        
        // We can communicate to the main app via NotificationCenter that an intent was triggered,
        // so it automatically starts recording upon launch.
        NotificationCenter.default.post(name: Notification.Name("CaptureIntentTriggered"), object: nil)
        
        return .result()
    }
}

// Ensure the AppIntent is discoverable by Siri and Shortcuts without needing user setup
struct VoitodoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureThoughtIntent(),
            phrases: [
                "Capture a thought in \(.applicationName)",
                "Record a note in \(.applicationName)",
                "Add a task to \(.applicationName)"
            ],
            shortTitle: "Capture Thought",
            systemImageName: "mic.fill"
        )
    }
}
