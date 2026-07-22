// RobutApp.swift — @main entry.
//
// LSUIElement is set in Info.plist, so there is no Dock icon, no main
// window, and no app-switcher entry. The menubar item is the whole app.

import SwiftUI

@main
struct RobutApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)

        // Startup is kicked off here, NOT from a `.task` on the
        // MenuBarExtra label.
        //
        // The label view backs an NSStatusItem rather than appearing in a
        // normal view hierarchy, so its `.task` never fires — the app
        // silently never polls. Learned the hard way: the symptom is an
        // icon that renders fine and a history file that stays empty.
        Task { @MainActor in model.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePane(model: model)
        } label: {
            RobotFace(mood: model.mood)
        }
        // .window gives a real popover panel rather than an NSMenu, which
        // is what lets the pane render progress bars and live text.
        .menuBarExtraStyle(.window)
    }
}
