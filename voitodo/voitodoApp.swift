import SwiftUI
import SwiftData

@main
struct voitodoApp: App {
    
    // Create the SwiftData container for the VoitodoItem model
    static var sharedModelContainer: ModelContainer = {
        // Assume sync is enabled by default unless the user explicitly turned it off in SettingsView
        let syncDisabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") != nil && UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") == false
        
        let schema = Schema([
            VoitodoItem.self,
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
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
        }
        .modelContainer(voitodoApp.sharedModelContainer)
    }
}
