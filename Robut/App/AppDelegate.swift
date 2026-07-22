// AppDelegate.swift — a guaranteed launch hook.
//
// Menubar-only SwiftUI apps have no reliable scene-lifecycle callback:
// `MenuBarExtra`'s label backs an NSStatusItem rather than appearing in a
// normal view hierarchy, so a `.task` on it never fires, and kicking work
// off from `App.init()` races object lifetime (see `AppModel.shared`).
//
// `applicationDidFinishLaunching` has neither problem. NSApplication
// retains its delegate for the process lifetime and calls this exactly
// once, after AppKit is fully up.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("applicationDidFinishLaunching")
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }
}
