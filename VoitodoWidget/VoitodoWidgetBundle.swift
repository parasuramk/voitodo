//
//  VoitodoWidgetBundle.swift
//  VoitodoWidget
//
//  Created by Parasuram Krishnan on 12/03/26.
//

import WidgetKit
import SwiftUI

@main
struct VoitodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoitodoWidget()
        VoitodoWidgetControl()
    }
}
