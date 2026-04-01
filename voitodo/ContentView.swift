import SwiftUI
import SwiftData
import EventKit
import AudioToolbox

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \VoitodoItem.timestamp, order: .reverse) private var items: [VoitodoItem]

    // Tracks items visually marked complete but not yet moved in the list.
    // Two-phase: strikethrough appears instantly; the row moves to bottom after a delay.
    @State private var pendingCompleted: Set<UUID> = []
    
    @AppStorage("hideCompleted") private var hideCompleted = false
    @AppStorage("undoDurationMinutes") private var undoDurationMinutes: Double = 60.0
    @AppStorage("autoTriageToCalendar") private var autoTriageToCalendar = false
    @AppStorage("hasSeenRecordingTip") private var hasSeenRecordingTip = false
    
    @State private var intelligenceItem: VoitodoItem? = nil

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

    // Returns a human-friendly relative day label for a timestamp
    private func relativeDayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return "Older"
        }
    }
    
    // Formats the reminder date dynamically based on the current day context
    private func formattedReminderTime(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeString = formatter.string(from: date)
        
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow \(timeString)"
        }
        return timeString
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
    
    // Helper to extract 10 AM tomorrow for specific calendar blocking
    private func getTomorrow10AM() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? Date()
    }

    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var speechRecognizer = SpeechRecognizer()

    @State private var isRecording = false
    @State private var hasPermissions = false
    @State private var isBreathing = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    // The Big Record Area permanently rendered
                    ZStack {
                        LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.08), Color(UIColor.systemGroupedBackground)]), startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 12) {
                            Button(action: {
                                toggleRecording()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(colorScheme == .dark ? Color(red: 192/255.0, green: 132/255.0, blue: 252/255.0) : Color.blue)
                                        .frame(width: 220, height: 220)
                                        .shadow(
                                            color: colorScheme == .dark ? Color(red: 192/255.0, green: 132/255.0, blue: 252/255.0).opacity(0.7) : Color.blue.opacity(0.4),
                                            radius: colorScheme == .dark ? 35 : 20,
                                            x: 0,
                                            y: colorScheme == .dark ? 0 : 10
                                        )
                                    
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : .white)
                                }
                            }
                            .scaleEffect(!isRecording && isBreathing ? 1.09 : 1.0)
                            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isBreathing)
                            
                            // One-time first-launch hint — fades out the moment recording starts
                            if !hasSeenRecordingTip && !isRecording {
                                VStack(spacing: 4) {
                                    Text("Also try:")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .textCase(.uppercase)
                                        .tracking(0.5)
                                    
                                    Text("Action Button · Lock Screen Widget")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    
                                    Text("\"Hey Siri, Capture a thought in Whatodo\"")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.horizontal, 32)
                                .transition(.opacity)
                            }
                        }
                        .padding(.top, 5)
                        .padding(.bottom, 10)
                    }
                    .zIndex(1)
                
                // Fixed Header removed dynamically to rely cleanly on Toolbar navigation
                
                // The Inbox List
                List {
                    ForEach(sortedItems) { item in
                            HStack(alignment: .top, spacing: 12) {
                                // Subtle Left Vertical Bar
                                RoundedRectangle(cornerRadius: 1)
                                    .fill((item.isCalendared ?? false) ? Color.orange : Color.gray.opacity(0.4))
                                    .frame(width: 3)
                                    .padding(.vertical, 2)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.summary ?? item.text)
                                        .font(.system(size: 17, weight: .medium, design: .default))
                                        .strikethrough(item.isCompleted)
                                        .foregroundColor((item.isCalendared ?? false) ? .orange : .primary)
                                        .opacity(item.isCompleted ? ((item.isCalendared ?? false) ? 1.0 : 0.3) : decayOpacity(for: item.timestamp))
                                        .lineSpacing(2)
                                        .textSelection(.enabled)
                                    
                                    HStack {
                                        if item.isCalendared ?? false {
                                            Image(systemName: "calendar")
                                                .font(.system(size: 11))
                                                .foregroundColor(.orange)
                                        }
                                        
                                        Text(relativeDayLabel(for: item.timestamp))
                                            .font(.system(size: 13, weight: .regular, design: .default))
                                            .foregroundColor(Color(UIColor.lightGray))
                                        
                                        if let reminderDate = item.reminderDate, !item.isCompleted, reminderDate > Date() {
                                            Text("•")
                                                .font(.system(size: 13))
                                                .foregroundColor(Color(UIColor.lightGray))
                                                
                                            HStack(spacing: 4) {
                                                Image(systemName: "bell.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(Color(UIColor.lightGray))
                                                Text(formattedReminderTime(for: reminderDate))
                                                    .font(.system(size: 13))
                                                    .foregroundColor(Color(UIColor.lightGray))
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        if let audioURL = item.audioFileURL {
                                            Button(action: {
                                                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                                let currentURL = documentsPath.appendingPathComponent(audioURL.lastPathComponent)
                                                AudioPlayer.shared.play(url: currentURL)
                                            }) {
                                                Image(systemName: "waveform")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(Color(UIColor.lightGray))
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 1, x: 0, y: 1)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .contextMenu {
                                if UIDevice.supportsAppleIntelligence {
                                    Button {
                                        intelligenceItem = item
                                    } label: {
                                        Label("Writing Tools", systemImage: "wand.and.stars")
                                    }
                                    Divider()
                                }
                                Button {
                                    UIPasteboard.general.string = item.summary ?? item.text
                                } label: {
                                    Label("Copy Text", systemImage: "doc.on.doc")
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
                // Custom list style to precisely close vertical gaps
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: sortedItems.map(\.id))
                } // End of underlying VStack layout
                
                // Dark Active Recording Overlay
                if isRecording {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        
                        VStack {
                            Spacer()
                            
                            ScrollView {
                                VStack(alignment: .center) {
                                    Spacer(minLength: 40)
                                    Text(speechRecognizer.isTranscribing ? speechRecognizer.transcribedText : "Listening...")
                                        .font(.system(size: 26, weight: .medium, design: .default))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 30)
                                }
                                .frame(maxWidth: .infinity, alignment: .bottom)
                            }
                            .frame(height: 150)
                            .defaultScrollAnchor(.bottom)
                            
                            Spacer().frame(height: 40)
                            
                            // Huge Centered Red Stop Button
                            Button(action: {
                                toggleRecording()
                            }) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.red.opacity(0.5), lineWidth: 4)
                                        .frame(width: 180, height: 180)
                                        .scaleEffect(1.15)
                                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isRecording)
                                    
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 140, height: 140)
                                        .shadow(color: Color.red.opacity(0.6), radius: 30, x: 0, y: 10)
                                    
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.bottom, 50)
                            
                            // Small Cancel at very bottom
                            Button(action: {
                                cancelRecording()
                            }) {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.bottom, 50)
                        }
                    }
                    .transition(.opacity)
                }
            } // End of root ZStack
            .fullScreenCover(item: $intelligenceItem) { item in
                IntelligenceTextEditorView(item: item)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(isRecording ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isRecording {
                        HStack(spacing: 16) {
                            Button(action: {
                                withAnimation {
                                    hideCompleted.toggle()
                                }
                            }) {
                                Image(systemName: hideCompleted ? "eye.slash" : "eye")
                                    .foregroundColor(hideCompleted ? .blue : .primary)
                            }
                            
                            NavigationLink(destination: SettingsView()) {
                                Image(systemName: "gearshape")
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .onAppear {
                // Delay breathing start so layout settles first, preventing top-left fly-in bug
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isBreathing = true
                }
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
            
            // Haptic and Audio cue AFTER session ends with a small delay for full volume
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                AudioServicesPlaySystemSound(1114)
            }
            
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
                    if let scheduledDate = ReminderService.shared.getNextReminderDate() {
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
            // Start — dismiss the one-time tip with a fade
            withAnimation { hasSeenRecordingTip = true }
            
            // Haptic and Audio cue BEFORE session starts to ensure audibility
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            AudioServicesPlaySystemSound(1113)
            
            // Tiny delay to ensure the chime plays at full volume before the mic ducks it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                do {
                    try speechRecognizer.startTranscribing()
                    audioRecorder.startRecording()
                    isRecording = true
                } catch {
                    print("Failed to start recording/transcribing: \(error)")
                }
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
                
                // Block the calendar for 30 minutes at 10 AM tomorrow
                let start = self.getTomorrow10AM()
                event.startDate = start
                event.endDate = start.addingTimeInterval(30 * 60)
                event.isAllDay = false
                event.calendar = store.defaultCalendarForNewEvents
                
                // Add a 10-minute alert
                event.addAlarm(EKAlarm(relativeOffset: -10 * 60))
                
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
                        
                        // Block 30 minutes at 10 AM tomorrow
                        let start = self.getTomorrow10AM()
                        event.startDate = start
                        event.endDate = start.addingTimeInterval(30 * 60)
                        event.isAllDay = false
                        event.calendar = store.defaultCalendarForNewEvents
                        
                        // Add a 10-minute alert
                        event.addAlarm(EKAlarm(relativeOffset: -10 * 60))
                        
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

// MARK: - Writing Tools Modal

struct IntelligenceTextEditorView: View {
    @Bindable var item: VoitodoItem
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            IntelligenceTextView(item: item)
                .ignoresSafeArea(.keyboard)
            
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.body)
                    .foregroundColor(.red)
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        try? item.modelContext?.save()
                        item.modelContext?.processPendingChanges()
                        dismiss()
                    }
                }
                .font(.headline)
            }
            .padding()
        }
    }
}

struct IntelligenceTextView: UIViewRepresentable {
    @Bindable var item: VoitodoItem

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 18, weight: .regular)
        textView.backgroundColor = .systemGroupedBackground
        textView.textContainerInset = UIEdgeInsets(top: 60, left: 16, bottom: 20, right: 16)
        textView.isEditable = true
        textView.delegate = context.coordinator
        textView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 18.0, *) {
            textView.writingToolsBehavior = .complete
            textView.allowsEditingTextAttributes = true
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text.isEmpty && !item.text.isEmpty {
            uiView.text = item.text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: IntelligenceTextView
        init(_ parent: IntelligenceTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.item.text = textView.text
            parent.item.summary = nil
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            parent.item.text = textView.text
            parent.item.summary = nil
        }
    }
}

extension UIDevice {
    static var supportsAppleIntelligence: Bool {
        guard #available(iOS 18.1, *) else { return false }
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        if ["i386", "x86_64", "arm64"].contains(identifier) { return true }
        if ["iPad13", "iPad14", "iPad15", "iPad16"].contains(where: { identifier.hasPrefix($0) }) { return true }
        if identifier.hasPrefix("iPhone"),
           let major = Int(identifier.replacingOccurrences(of: "iPhone", with: "").components(separatedBy: ",")[0]),
           major >= 16 { return true }
        return false
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VoitodoItem.self, inMemory: true)
}
