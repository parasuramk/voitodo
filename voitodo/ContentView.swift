import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VoitodoItem.timestamp, order: .reverse) private var items: [VoitodoItem]

    // Tracks items visually marked complete but not yet moved in the list.
    // Two-phase: strikethrough appears instantly; the row moves to bottom after a delay.
    @State private var pendingCompleted: Set<UUID> = []

    // Items in pendingCompleted are still treated as "active" for sort purposes.
    private var sortedItems: [VoitodoItem] {
        items.sorted { lhs, rhs in
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
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 4)
                
                // The Inbox List
                List {
                    ForEach(sortedItems) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.text)
                                    .font(.body)
                                    .strikethrough(item.isCompleted)
                                
                                HStack {
                                    Text(item.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
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
                                Button(action: { toggleComplete(item) }) {
                                    Label(item.isCompleted ? "Undo" : "Complete", systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                        .onDelete(perform: deleteItems)
                }
                // Custom list style to minimize default inset grouped padding at the top
                .listStyle(.insetGrouped)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: sortedItems.map(\.id))
            }
            .navigationTitle("Whatodo")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                requestPermissions()
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
                let newItem = VoitodoItem(
                    text: speechRecognizer.transcribedText,
                    audioFileURL: audioRecorder.audioFileURL
                )
                
                // Get the reminder date and schedule the hybrid notification
                if let scheduledDate = ReminderService.shared.getTomorrow9AM() {
                    newItem.reminderDate = scheduledDate
                    
                    let capturedText = newItem.text
                    let capturedID = newItem.id
                    Task {
                        await ReminderService.shared.scheduleHybridReminder(text: capturedText, id: capturedID, triggerDate: scheduledDate)
                    }
                }
                
                modelContext.insert(newItem)
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
            pendingCompleted.insert(itemID)
            Task { await ReminderService.shared.cancelHybridReminder(for: itemID) }
            // Phase 2: smooth spring move to bottom
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    _ = pendingCompleted.remove(itemID)
                }
            }
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                _ = pendingCompleted.remove(itemID)
                item.isCompleted = false
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
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VoitodoItem.self, inMemory: true)
}
