import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entries: [SimpleEntry] = [SimpleEntry(date: Date())]
        let timeline = Timeline(entries: entries, policy: .never) // Widget is static
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct VoitodoWidgetEntryView : View {
    var entry: Provider.Entry
    
    // Check if we are rendering in the small circular lock screen context
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            if family == .accessoryCircular {
                // Lock screen circular widget — use SF Symbol for reliable rendering
                Image(systemName: "mic.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .widgetAccentable()
            } else {
                // Home screen widget
                VStack {
                    Image(systemName: "mic.fill")
                        .font(.largeTitle)
                    Text("Capture Thought")
                        .font(.caption)
                }
            }
        }
        // When tapped, use a custom URL scheme to open the app and trigger recording
        .widgetURL(URL(string: "voitodo://capture"))
    }
}

struct VoitodoWidget: Widget {
    let kind: String = "VoitodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            VoitodoWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Capture Thought")
        .description("Instantly open Whatodo to capture a new thought.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

#Preview(as: .accessoryCircular) {
    VoitodoWidget()
} timeline: {
    SimpleEntry(date: .now)
}
