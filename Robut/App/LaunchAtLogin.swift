// LaunchAtLogin.swift — Robut comes back after a reboot.
//
// It didn't, once. The Mac rebooted at 06:14 on 2026-09-06; Robut was not
// a login item, so it stayed dead — silently, no crash, no log — for six
// weeks, and the history the pace engine learns from went with it
// (rex/robut#2). A usage monitor that doesn't survive a reboot isn't one.
//
// Policy, deliberately conservative:
//   • The first launch of a RELEASE build registers Robut as a login
//     item — once. From then on the choice is the user's: switching it
//     off (in the pane or in System Settings) is never undone.
//   • Not while App-Translocated (run straight out of Downloads): the
//     registered path would be a randomized mount that vanishes. Wait for
//     the launch from /Applications, and only then count it as done.
//   • Debug builds never self-register, so a DerivedData dev copy and an
//     installed copy can't both launch at login. The toggle still works.
//   • Called only after AppDelegate's XCTest guard — `make test` launches
//     the app as its test host and must never touch the login-item store.

import Foundation
import Observation
import ServiceManagement

/// The slice of `SMAppService` Robut uses — a seam so tests never touch
/// the real login-item database.
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

@MainActor
@Observable
final class LaunchAtLogin {

    /// Set once the first-launch registration has been attempted (or the
    /// user has made a choice). Its presence is what keeps a user's "off"
    /// from ever being flipped back on.
    static let bootstrappedKey = "launchAtLogin.bootstrapped"

    /// The app's instance. Static for the same lifetime reason as
    /// `AppModel.shared`; tests build their own.
    static let shared = LaunchAtLogin()

    private(set) var status: SMAppService.Status
    /// The last register/unregister failure, for the pane. nil when fine.
    private(set) var lastError: String?

    private let service: any LoginItemService
    private let defaults: UserDefaults
    private let isReleaseBuild: Bool
    private let bundlePath: String

    init(
        service: any LoginItemService = SMAppService.mainApp,
        defaults: UserDefaults = .standard,
        isReleaseBuild: Bool = LaunchAtLogin.compiledForRelease,
        bundlePath: String = Bundle.main.bundlePath
    ) {
        self.service = service
        self.defaults = defaults
        self.isReleaseBuild = isReleaseBuild
        self.bundlePath = bundlePath
        self.status = service.status
    }

    nonisolated static var compiledForRelease: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    /// On, or on pending the user's approval in System Settings.
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    /// macOS wants the user to approve the login item in System Settings.
    var needsApproval: Bool { status == .requiresApproval }

    var isTranslocated: Bool { bundlePath.contains("/AppTranslocation/") }

    /// First-launch registration. Safe to call on every launch: it acts
    /// at most once, and never against a choice the user has made.
    func bootstrap() {
        refresh()
        guard isReleaseBuild, !isTranslocated else { return }
        guard !defaults.bool(forKey: Self.bootstrappedKey) else { return }
        defaults.set(true, forKey: Self.bootstrappedKey)
        if !isEnabled { apply(register: true) }
    }

    /// The pane's toggle. Any explicit choice also counts as bootstrapped.
    func set(enabled: Bool) {
        defaults.set(true, forKey: Self.bootstrappedKey)
        apply(register: enabled)
    }

    /// Re-read the status — the user can change it in System Settings
    /// while Robut runs.
    func refresh() {
        status = service.status
    }

    /// Where macOS asks the user to approve a login item.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func apply(register: Bool) {
        let action = register ? "register" : "unregister"
        do {
            if register { try service.register() } else { try service.unregister() }
            lastError = nil
        } catch {
            lastError = register
                ? "Couldn't add Robut to Login Items"
                : "Couldn't remove Robut from Login Items"
            let detail = String(describing: error)
            Log.app.notice("launch at login \(action, privacy: .public) failed: \(detail, privacy: .public)")
        }
        refresh()
    }
}
