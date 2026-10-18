// LaunchAtLoginTests.swift — Robut comes back after a reboot, once, politely.
//
// The policy (rex/robut#2): a release build registers itself as a login
// item on its first real launch — once — and never overrides the user's
// choice afterwards. Everything here runs against a fake service and a
// throwaway defaults suite; nothing touches the real login-item store.

import Foundation
import ServiceManagement
import Testing

@testable import Robut

/// Records calls and models the status transitions macOS would make.
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registerCalls = 0
    var unregisterCalls = 0
    var failRegister = false

    struct Refused: Error {}

    func register() throws {
        registerCalls += 1
        if failRegister { throw Refused() }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        status = .notRegistered
    }
}

@Suite("Launch at login")
@MainActor
struct LaunchAtLoginTests {

    private let installed = "/Applications/Robut.app"

    private func defaults() throws -> UserDefaults {
        let suite = "robut.tests.launch-at-login.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.removePersistentDomain(forName: suite)
        return store
    }

    @Test("A release build's first launch registers — exactly once")
    func firstLaunchRegistersOnce() throws {
        let service = FakeLoginItemService()
        let launch = LaunchAtLogin(
            service: service, defaults: try defaults(), isReleaseBuild: true, bundlePath: installed
        )
        launch.bootstrap()
        launch.bootstrap()
        #expect(service.registerCalls == 1)
        #expect(launch.isEnabled)
    }

    @Test("Turning it off is never undone by a later launch")
    func userChoiceSticks() throws {
        let service = FakeLoginItemService()
        let store = try defaults()
        let first = LaunchAtLogin(
            service: service, defaults: store, isReleaseBuild: true, bundlePath: installed
        )
        first.bootstrap()
        first.set(enabled: false)
        #expect(service.unregisterCalls == 1)

        // Next launch — same preferences, item still off.
        let next = LaunchAtLogin(
            service: service, defaults: store, isReleaseBuild: true, bundlePath: installed
        )
        next.bootstrap()
        #expect(service.registerCalls == 1)
        #expect(!next.isEnabled)
    }

    @Test("Debug builds never self-register, but the toggle still works")
    func debugNeverSelfRegisters() throws {
        let service = FakeLoginItemService()
        let launch = LaunchAtLogin(
            service: service, defaults: try defaults(), isReleaseBuild: false,
            bundlePath: "/tmp/DerivedData/Build/Products/Debug/Robut.app"
        )
        launch.bootstrap()
        #expect(service.registerCalls == 0)

        launch.set(enabled: true)
        #expect(service.registerCalls == 1)
        #expect(launch.isEnabled)
    }

    @Test("A translocated launch waits for the copy in Applications")
    func translocationDefers() throws {
        let service = FakeLoginItemService()
        let store = try defaults()
        let translocated = LaunchAtLogin(
            service: service, defaults: store, isReleaseBuild: true,
            bundlePath: "/private/var/folders/xy/AppTranslocation/ABC-123/d/Robut.app"
        )
        translocated.bootstrap()
        #expect(service.registerCalls == 0)

        // Moved to /Applications and relaunched: now it registers.
        let moved = LaunchAtLogin(
            service: service, defaults: store, isReleaseBuild: true, bundlePath: installed
        )
        moved.bootstrap()
        #expect(service.registerCalls == 1)
    }

    @Test("A refused registration is reported, not thrown")
    func failureIsReported() throws {
        let service = FakeLoginItemService()
        service.failRegister = true
        let launch = LaunchAtLogin(
            service: service, defaults: try defaults(), isReleaseBuild: true, bundlePath: installed
        )
        launch.bootstrap()
        #expect(launch.lastError != nil)
        #expect(!launch.isEnabled)
    }

    @Test("Pending approval counts as on, and says it needs approval")
    func approvalPending() throws {
        let service = FakeLoginItemService()
        service.status = .requiresApproval
        let launch = LaunchAtLogin(
            service: service, defaults: try defaults(), isReleaseBuild: true, bundlePath: installed
        )
        launch.bootstrap()
        #expect(service.registerCalls == 0)
        #expect(launch.isEnabled)
        #expect(launch.needsApproval)
    }
}
