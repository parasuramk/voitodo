import SwiftUI
import SwiftData
import EventKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoitodoItem.timestamp, order: .reverse) private var items: [VoitodoItem]

    // Tracks items visually marked complete but not yet moved in the list.
    // Two-phase: strikethrough appears instantly; the row moves to bottom after a delay.
    @State private var pendingCompleted: Set<UUID> = []
    
    @AppStorage("hideCompleted") private var hideCompleted = false
    @AppStorage("undoDurationMinutes") private var undoDurationMinutes: Double = 60.0
    @AppStorage("autoTriageToCalendar") private var autoTriageToCalendar = false

    // Calculates opacity based on how old the thought is (Visual Decay)
    private func decayOpacity(for timestamp: Date) -> Double {
        let ageInDays = Date().timeIntervalSince(timestamp) / (60 * 60 * 24)
        if ageInDays < 1.0 {
            // Day 1: Fresh
            return 1.0
        } else if ageInDays < 2.0 {
            // Day 2: Getting older
            return 0.6
        } else {
            // Day 3+: Urgent warning before Triage kicks in
            return 0.3
        }
    }

    // Items in pendingCompleted are still treated as "active" for sort purposes.
    private var sortedItems: [VoitodoItem] {
        let filteredItems = hideCompleted ? items.filter { !$0.isCompleted || pendingCompleted.contains($0.id) } : items
        
        return filteredItems.sorted { lhs, rhs in
            let lhsSettled = lhs.isCompleted && !pendingCompleted.contains(lhs.id)
            let rhsSettled = rhs.isCompleted && !pendingCompleted.contains(rhs.id)
            if lhsSettled != rhsSettled { return !lhsSettled }
            return lhs.timestamp > rhs.timestamp
        }
    }

    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var speechRecognizer = SpeechRecognizer()

    @State private var isRecording = false
    @State private var hasPermissions = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // The Big Record Area
                ZStack {
                    Color(UIColor.systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Text(speechRecognizer.isTranscribing ? speechRecognizer.transcribedText : "Tap to Capture Thought")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .frame(height: 60)
                        
                        Button(action: {
                            toggleRecording()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(isRecording ? Color.red : Color.blue)
                                    .frame(width: 150, height: 150)
                                    .shadow(color: (isRecording ? Color.red : Color.blue).opacity(0.4), radius: 20, x: 0, y: 10)
                                
                                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.white)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        // Pulse animation when recording
                        .scaleEffect(isRecording ? 1.1 : 1.0)
                        .animation(isRecording ? Animation.easeInOut(duration: 1).repeatForever(autoreverses: true) : .default, value: isRecording)
                        
                        // Cancel button
                        if isRecording {
                            Button(action: {
                                cancelRecording()
                            }) {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(20)
                            }
                            .transition(.opacity)
                        } else {
                            // Invisible placeholder to keep layout from jumping
                            Text("Cancel")
                                .font(.subheadline)
                                .padding(.vertical, 8)
                                .opacity(0)
                        }
                    }
                    .padding(.vertical, 40)
                }
                .frame(maxHeight: 330)
                
                // Fixed Header
                HStack {
                    Text("Captured Thoughts")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            hideCompleted.toggle()
                        }
                    }) {
                        Image(systemName: hideCompleted ? "eye.slash" : "eye")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(hideCompleted ? .blue : .secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 4)
                
                // The Inbox List
                List {
                    ForEach(sortedItems) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.summary ?? item.text)
                                    .font(.body)
                                    .strikethrough(item.isCompleted)
                                    .foregroundColor((item.isCalendared ?? false) ? .red : .primary)
                                    .opacity(item.isCompleted ? ((item.isCalendared ?? false) ? 1.0 : 0.3) : decayOpacity(for: item.timestamp))
                                
                                HStack {
                                    Text("\(item.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        
                                    if item.isCalendared ?? false {
                                        Image(systemName: "calendar")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                            .padding(.leading, 4)
                                    }
                                    
                                    Spacer()
                                    
                                    if let reminderDate = item.reminderDate, !item.isCompleted {
                                        HStack(spacing: 4) {
                                            Image(systemName: "bell.fill")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                            Text(reminderDate, style: .time)
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .cornerRadius(4)
                                    }
                                    
                                    if let audioURL = item.audioFileURL {
                                        Button(action: {
                                            // The iOS Simulator changes the app's UUID Sandbox path on every build.
                                            // We must dynamically reconstruct the file URL using the saved filename.
                                            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                            let currentURL = documentsPath.appendingPathComponent(audioURL.lastPathComponent)
                                            AudioPlayer.shared.play(url: currentURL)
                                        }) {
                                            Image(systemName: "play.circle.fill")
                                                .foregroundColor(.blue)
                                                .font(.title3)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if item.isCompleted {
                                    if let completedAt = item.completionDate, Date().timeIntervalSince(completedAt) <= (undoDurationMinutes * 60) {
                                        Button(action: { toggleComplete(item) }) {
                                            Label("Undo", systemImage: "arrow.uturn.backward")
                                        }
                                        .tint(.green)
                                    }
                                } else {
                                    Button(action: { toggleComplete(item) }) {
                                        Label("Complete", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !(item.isCalendared ?? false) {
                                    if !item.isCompleted {
                                        Button(role: .destructive, action: {
                                            withAnimation {
                                                deleteItem(item)
                                            }
                                        }) {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    
                                    Button(action: {
                                        addToCalendar(item)
                                    }) {
                                        Label("Calendar", systemImage: "calendar.badge.plus")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                        // Removed standard .onDelete to prevent default delete swipes on protected items.
                }
                // Custom list style to minimize default inset grouped padding at the top
                .listStyle(.insetGrouped)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: sortedItems.map(\.id))
            }
            .navigationTitle("Whatodo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.primary)
                    }
                }
            }
            .onAppear {
                requestPermissions()
                ReminderService.shared.updateBadgeCount()
                speechRecognizer.onSilenceDetected = {
                    if isRecording {
                        toggleRecording()
                    }
                }
                runAutoTriage()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CaptureIntentTriggered"))) { _ in
                // If launched via Action Button or Siri, immediately start recording if not already doing so
                if !isRecording {
                    toggleRecording()
                }
            }
            .onOpenURL { url in
                // Handle the lock screen widget deep link
                if url.scheme == "voitodo" && url.host == "capture" {
                    if !isRecording {
                        toggleRecording()
                    }
                }
            }
        }
    }
    
    private func requestPermissions() {
        // Request Notifications First
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("Notification permission granted: \(granted)")
            
            // Then Request Audio & Speech
            DispatchQueue.main.async {
                self.audioRecorder.requestPermission { audioGranted in
                    self.speechRecognizer.requestPermission { speechGranted in
                        self.hasPermissions = audioGranted && speechGranted
                    }
                }
            }
        }
    }
    
    private func cancelRecording() {
        isRecording = false
        audioRecorder.stopRecording()
        speechRecognizer.stopTranscribing()
        
        // Clear text to prevent it from flashing on next open
        speechRecognizer.transcribedText = ""
    }
    
    private func toggleRecording() {
        guard hasPermissions else {
            print("Missing permissions")
            return
        }
        
        // Haptic feedback
        let impactMed = UIImpactFeedbackGenerator(style: .medium)
        impactMed.impactOccurred()
        
        if isRecording {
            // Stop
            isRecording = false
            audioRecorder.stopRecording()
            speechRecognizer.stopTranscribing()
            
            // Save the result
            if !speechRecognizer.transcribedText.isEmpty && speechRecognizer.transcribedText != "Listening..." {
                let rawText = speechRecognizer.transcribedText
                let audioURL = audioRecorder.audioFileURL
                
                Task { @MainActor in
                    let generatedSummary = await AIService.shared.summarize(transcript: rawText)
                    
                    let newItem = VoitodoItem(
                        text: rawText,
                        audioFileURL: audioURL,
                        summary: generatedSummary
                    )
                    
                    // Get the reminder date and schedule the hybrid notification
                    if let scheduledDate = ReminderService.shared.getTomorrow9AM() {
                        newItem.reminderDate = scheduledDate
                        
                        let capturedText = newItem.summary ?? newItem.text
                        let capturedID = newItem.id
                        Task {
                            await ReminderService.shared.scheduleHybridReminder(text: capturedText, id: capturedID, triggerDate: scheduledDate)
                        }
                    }
                    
                    modelContext.insert(newItem)
                    ReminderService.shared.updateBadgeCount()
                }
            }
            
        } else {
            // Start
            do {
                try speechRecognizer.startTranscribing()
                audioRecorder.startRecording()
                isRecording = true
            } catch {
                print("Failed to start recording/transcribing: \(error)")
            }
        }
    }
    
    private func toggleComplete(_ item: VoitodoItem) {
        let itemID = item.id
        if !item.isCompleted {
            // Phase 1: visual strikethrough, row stays in place
            item.isCompleted = true
            item.completionDate = Date()
            ReminderService.shared.updateBadgeCount()
            pendingCompleted.insert(itemID)
            Task { await ReminderService.shared.cancelHybridReminder(for: itemID) }
            // Phase 2: smooth spring move to bottom
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    _ = pendingCompleted.remove(itemID)
                }
            }
        } else {
            // Un-complete logic: if calendared, remove it from iOS Calendar
            if let eventID = item.eventIdentifier, item.isCalendared == true {
                let store = EKEventStore()
                let completion: (Bool, Error?) -> Void = { granted, _ in
                    if granted {
                        if let eventToRemove = store.event(withIdentifier: eventID) {
                            do {
                                try store.remove(eventToRemove, span: .thisEvent)
                            } catch {
                                print("Failed to remove calendar event on Undo: \(error)")
                            }
                        }
                    }
                }
                
                if #available(iOS 17.0, *) {
                    store.requestFullAccessToEvents(completion: completion)
                } else {
                    store.requestAccess(to: .event, completion: completion)
                }
                
                item.isCalendared = false
                item.eventIdentifier = nil
            }
            
            item.completionDate = nil
            
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                _ = pendingCompleted.remove(itemID)
                item.isCompleted = false
                ReminderService.shared.updateBadgeCount()
            }
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let item = sortedItems[index]
                let itemID = item.id
                
                // Cancel pending notification
                Task {
                    await ReminderService.shared.cancelHybridReminder(for: itemID)
                }
                
                modelContext.delete(item)
            }
            ReminderService.shared.updateBadgeCount()
        }
    }
    
    private func deleteItem(_ item: VoitodoItem) {
        let itemID = item.id
        Task {
            await ReminderService.shared.cancelHybridReminder(for: itemID)
        }
        modelContext.delete(item)
        ReminderService.shared.updateBadgeCount()
    }
    
    private func addToCalendar(_ item: VoitodoItem) {
        let store = EKEventStore()
        let completion: (Bool, Error?) -> Void = { granted, error in
            if granted {
                let event = EKEvent(eventStore: store)
                event.title = item.summary ?? item.text
                
                // Creates an "All Day" event for today as a concrete goal
                event.startDate = Date()
                event.endDate = Date()
                event.isAllDay = true
                event.calendar = store.defaultCalendarForNewEvents
                
                do {
                    try store.save(event, span: .thisEvent)
                    let savedID = event.eventIdentifier // Get the generated ID
                    DispatchQueue.main.async {
                        // Keep the thought for Future AI / Memory Vault, just mark it completed and calendared
                        withAnimation {
                            item.isCalendared = true
                            item.eventIdentifier = savedID
                            if !item.isCompleted {
                                toggleComplete(item)
                            }
                        }
                    }
                } catch {
                    print("Failed to save event to calendar: \(error)")
                }
            } else {
                print("Access to calendar denied")
            }
        }

        if #available(iOS 17.0, *) {
            // Must use FullAccess to be able to fetch and delete it during an Undo gesture later.
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
    }
    
    private func runAutoTriage() {
        guard autoTriageToCalendar else { return }
        
        // Find items older than 3 days (e.g. Day 4) that haven't been completed or calendared yet
        let now = Date()
        let staleItems = items.filter { item in
            let ageInDays = now.timeIntervalSince(item.timestamp) / (60 * 60 * 24)
            return !item.isCompleted && !(item.isCalendared ?? false) && ageInDays >= 3.0
        }
        
        guard !staleItems.isEmpty else { return }
        
        let store = EKEventStore()
        let completion: (Bool, Error?) -> Void = { granted, _ in
            if granted {
                // Must interact with SwiftData models on the main thread
                DispatchQueue.main.async {
                    for item in staleItems {
                        let event = EKEvent(eventStore: store)
                        event.title = item.summary ?? item.text
                        // Auto-triage sends it to today as an All-Day goal
                        event.startDate = Date()
                        event.endDate = Date()
                        event.isAllDay = true
                        event.calendar = store.defaultCalendarForNewEvents
                        
                        do {
                            try store.save(event, span: .thisEvent)
                            let savedID = event.eventIdentifier
                            
                            withAnimation {
                                item.isCalendared = true
                                item.eventIdentifier = savedID
                                if !item.isCompleted {
                                    toggleComplete(item)
                                }
                            }
                        } catch {
                            print("Failed to auto-triage event to calendar: \(error)")
                        }
                    }
                }
            }
        }
        
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VoitodoItem.self, inMemory: true)
}
