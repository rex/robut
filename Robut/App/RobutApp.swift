// RobutApp.swift — @main entry.
//
// LSUIElement is set in Info.plist, so there is no Dock icon, no main
// window, and no app-switcher entry. The menubar item is the whole app.

import SwiftUI

@main
struct RobutApp: App {
    // Startup runs from applicationDidFinishLaunching, NOT from a `.task`
    // on the MenuBarExtra label (never fires) and NOT from `init()`
    // (races the model's lifetime). See AppDelegate for the full story.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            UsagePane(model: model)
        } label: {
            // MUST be an Image backed by a CONCRETE bitmap. A SwiftUI
            // Canvas renders zero-width here, and so does a lazy
            // drawingHandler-based NSImage — in both cases the app runs
            // fine and simply never appears in the menubar. See RobotIcon.
            Image(nsImage: RobotIcon.image(for: model.mood))
        }
        // .window gives a real popover panel rather than an NSMenu, which
        // is what lets the pane render progress bars and live text.
        .menuBarExtraStyle(.window)
    }
}
