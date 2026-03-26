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
                Label("Capture Thought", systemImage: "mic.fill")
            }
        }
        .displayName("Capture Thought")
        .description("Instantly open Whatodo to capture a new thought.")
    }
}

extension WhatodoControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { false }
    }
}
