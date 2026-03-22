import SwiftUI
import SwiftData
import EventKit

enum Theme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// All UserDefaults keys that should be mirrored to iCloud KV Store.
private let iCloudSyncedKeys = [
    "iCloudSyncEnabled",
    "silenceThreshold",
    "undoDurationMinutes",
    "autoTriageToCalendar",
    "appTheme"
]

@main
struct voitodoApp: App {
    @AppStorage("appTheme") private var appTheme: Theme = .system
    
    // Create the SwiftData container for the VoitodoItem model
    static var sharedModelContainer: ModelContainer = {
        // Assume sync is enabled by default unless the user explicitly turned it off in SettingsView
        let syncDisabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") != nil && UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") == false
        
        let schema = Schema([
            VoitodoItem.self,
        ])
        
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.pakrishn.voitodo")?
            .appendingPathComponent("default.store") ?? URL.documentsDirectory.appendingPathComponent("default.store")
        
        let modelConfiguration = ModelConfiguration(
            url: url,
            cloudKitDatabase: syncDisabled ? .none : .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appTheme.colorScheme)
                .onAppear {
                    migrateNotificationFiredFlags()
                    requestCalendarPermissionIfNeeded()
                    syncSettingsFromiCloud()
                    
                    // Listen for iCloud KV changes pushed from other devices
                    NotificationCenter.default.addObserver(
                        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                        object: NSUbiquitousKeyValueStore.default,
                        queue: .main
                    ) { _ in
                        syncSettingsFromiCloud()
                    }
                    NSUbiquitousKeyValueStore.default.synchronize()
                }
        }
        .modelContainer(voitodoApp.sharedModelContainer)
    }
    
    // MARK: - Calendar Permission
    
    /// Requests calendar access upfront so the dialog appears on first launch,
    /// not the first time the user tries to add a thought to the calendar.
    private func requestCalendarPermissionIfNeeded() {
        let store = EKEventStore()
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents { _, _ in }
        } else {
            store.requestAccess(to: .event) { _, _ in }
        }
    }
    
    // MARK: - iCloud Settings Sync
    
    /// Pulls settings from iCloud KV Store into UserDefaults on every launch.
    /// This ensures settings survive a delete-and-reinstall.
    private func syncSettingsFromiCloud() {
        let kvStore = NSUbiquitousKeyValueStore.default
        for key in iCloudSyncedKeys {
            if let value = kvStore.object(forKey: key) {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }
    
    // MARK: - Legacy Migration
    
    /// One-time silent migration: for existing thoughts whose reminder date has
    /// already passed, mark `notificationFired = true` so the bell icon is removed.
    private func migrateNotificationFiredFlags() {
        Task { @MainActor in
            let context = voitodoApp.sharedModelContainer.mainContext
            let descriptor = FetchDescriptor<VoitodoItem>()
            guard let items = try? context.fetch(descriptor) else { return }
            
            var didChange = false
            let now = Date()
            for item in items where !item.notificationFired {
                if let reminderDate = item.reminderDate, reminderDate < now {
                    item.notificationFired = true
                    didChange = true
                }
            }
            if didChange { try? context.save() }
        }
    }
}
