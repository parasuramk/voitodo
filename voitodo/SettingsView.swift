import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = true
    @AppStorage("silenceThreshold") private var silenceThreshold: Double = 3.0
    @AppStorage("undoDurationMinutes") private var undoDurationMinutes: Double = 60.0
    @AppStorage("autoTriageToCalendar") private var autoTriageToCalendar = false
    @AppStorage("appTheme") private var appTheme: Theme = .system
    @AppStorage("isShoppingSuggestionsEnabled") private var isShoppingSuggestionsEnabled = false

    var body: some View {
        Form {
            Section(header: Text("Appearance")) {
                Picker("Theme", selection: $appTheme) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section(header: Text("Triage"), footer: Text("Automatically push thoughts older than 3 days into your iOS Calendar.")) {
                Toggle("Auto-Triage to Calendar", isOn: $autoTriageToCalendar)
            }
            
            Section(header: Text("Data"), footer: Text("Disabling iCloud sync keeps all thoughts strictly on this device. Changes to this setting require an app restart to take effect.")) {
                Toggle("iCloud Sync", isOn: $iCloudSyncEnabled)
            }
            
            Section(header: Text("Inbox Actions"), footer: Text("After marked complete or add to calendar, the action cannot be undone after this time passes")) {
                VStack {
                    HStack {
                        Text("Undo Window")
                        Spacer()
                        Text("\(Int(undoDurationMinutes)) min")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $undoDurationMinutes, in: 0...120, step: 10)
                }
            }
            
            if AffiliateService.shared.isIndiaRegion() {
                Section(header: Text("Smart Integrations"), footer: Text("AI detects products you mention and adds a quick shop link to the swipe menu.")) {
                    Toggle("Smart Shopping Suggestions", isOn: $isShoppingSuggestionsEnabled)
                }
            }
            
            Section(header: Text("Recording"), footer: Text("Adjust how long the app waits in silence before automatically stopping the recording.")) {
                VStack {
                    HStack {
                        Text("Auto-Stop Delay")
                        Spacer()
                        Text(String(format: "%.1f sec", silenceThreshold))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $silenceThreshold, in: 1.0...5.0, step: 0.5)
                }
            }
            
            Section(header: Text("About")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        // Write every setting change back to iCloud KV Store so it survives reinstalls
        .onChange(of: iCloudSyncEnabled)   { _, v in pushToiCloud("iCloudSyncEnabled", v) }
        .onChange(of: silenceThreshold)    { _, v in pushToiCloud("silenceThreshold", v) }
        .onChange(of: undoDurationMinutes) { _, v in pushToiCloud("undoDurationMinutes", v) }
        .onChange(of: autoTriageToCalendar){ _, v in pushToiCloud("autoTriageToCalendar", v) }
        .onChange(of: appTheme)            { _, v in pushToiCloud("appTheme", v.rawValue) }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

// MARK: - Helpers

private func pushToiCloud(_ key: String, _ value: Any) {
    NSUbiquitousKeyValueStore.default.set(value, forKey: key)
    NSUbiquitousKeyValueStore.default.synchronize()
}
