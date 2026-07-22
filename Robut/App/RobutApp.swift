// RobutApp.swift — @main entry.
//
// LSUIElement is set in Info.plist, so there is no Dock icon, no main
// window, and no app-switcher entry. The menubar item is the whole app.

import SwiftUI

@main
struct RobutApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePane(model: model)
        } label: {
            RobotFace(mood: model.mood)
                .task { model.start() }
        }
        // .window gives a real popover panel rather than an NSMenu, which
        // is what lets the pane render progress bars and live text.
        .menuBarExtraStyle(.window)
    }
}
