//
//  VoitodoWidgetControl.swift
//  VoitodoWidget
//
//  Created by Parasuram Krishnan on 12/03/26.
//

import AppIntents
import SwiftUI
import WidgetKit

struct WhatodoControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "pakrishn.voitodo.WhatodoControl",
            provider: Provider()
        ) { value in
            ControlWidgetButton(action: CaptureThoughtIntent()) {
                Label("Capture Thought", systemImage: "sparkles")
            }
        }
        .displayName("Capture Thought")
        .description("Instantly open Whatodo to capture a new thought.")
    }
}

struct CaptureThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Thought"
    static var description = IntentDescription("Immediately starts recording a new thought in Whatodo.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: Notification.Name("CaptureIntentTriggered"), object: nil)
        return .result()
    }
}

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
            systemImageName: "sparkles"
        )
    }
}

extension WhatodoControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { false }
    }
}
