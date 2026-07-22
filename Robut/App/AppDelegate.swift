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
        // ⛔️ Do NOT start the refresh loop under XCTest.
        //
        // A unit-test bundle for an app target uses the app itself as its
        // TEST HOST, so `xcodebuild test` LAUNCHES Robut for real — this
        // delegate fires, the loop starts, and every `make test` makes
        // live provider network calls. That is how a test suite quietly
        // turned into a request generator against Anthropic and kept a
        // rate limit alive that was supposed to be expiring.
        //
        // Tests construct their own AppModel with injected sources; they
        // never want the shared one polling the real network.
        guard !Self.isRunningTests else {
            Log.app.notice("test host launch — refresh loop NOT started")
            return
        }

        Log.app.notice("applicationDidFinishLaunching")
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }

    /// True when this process was launched by XCTest as a test host.
    ///
    /// Belt and braces: the environment variable is the documented
    /// signal, and the runtime class check catches a bundle injected
    /// without it. `ROBUT_DISABLE_NETWORK` is a manual override for
    /// running the app while deliberately keeping it off the network.
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["ROBUT_DISABLE_NETWORK"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
