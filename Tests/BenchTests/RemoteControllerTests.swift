// RemoteControllerTests.swift — Bench's Serve mapping when nobody turned the
// switch off: when Bench quits, and when it launches with the switch off. A
// fake runner stands in for the CLI and records what would have run; the
// settings are a throwaway suite. Nothing reaches Tailscale.
import Foundation
import Testing
@testable import Bench

/// Answers every command after a wait, as a CLI that hangs would.
private struct SlowRunner: TailscaleRunner {
    let seconds: Double

    func run(_ arguments: [String], timeout: TimeInterval, stopWhen: (@Sendable (String) -> Bool)?) async -> TailscaleRun {
        try? await Task.sleep(for: .seconds(seconds))
        return TailscaleRun(exitStatus: 0, output: "{}")
    }
}

@MainActor
struct RemoteControllerTests {
    private let off = ["serve", "--https=8443", "off"]

    private func ok(_ output: String) -> TailscaleRun {
        TailscaleRun(exitStatus: 0, output: output)
    }

    /// A throwaway settings suite: `served` as if a listener had run on an earlier launch.
    private func withDefaults(served: Bool, _ body: @MainActor (UserDefaults) async throws -> Void) async throws {
        let scratch = ScratchDefaults.make(prefix: "bench.tests.remote")
        defer { scratch.discard() }
        let defaults = scratch.defaults
        if served { defaults.set(47280, forKey: SettingsKey.remotePort) }
        try await body(defaults)
    }

    private func controller(_ runner: any TailscaleRunner, _ defaults: UserDefaults, demo: Bool = false) -> RemoteController {
        RemoteController(auth: RemoteAuth(store: MemoryDeviceStore()), bridge: TailscaleBridge(runner: runner),
                         defaults: defaults, isDemo: demo)
    }

    private func runner(serving json: String, offWorks: Bool = true) -> FakeTailscaleRunner {
        FakeTailscaleRunner([TailscaleCommands.serveStatus: [ok(json)],
                             off: [TailscaleRun(exitStatus: offWorks ? 0 : 1, output: "")]])
    }

    // MARK: Quitting

    @Test func quittingRemovesBenchsMapping() async throws {
        try await withDefaults(served: true) { defaults in
            let runner = runner(serving: TailscaleFixture.serveBench())
            controller(runner, defaults).removeMappingAtQuit(within: 10)
            #expect(runner.calls == [TailscaleCommands.serveStatus, off])
        }
    }

    @Test func quittingLeavesSomeoneElsesMappingAlone() async throws {
        try await withDefaults(served: true) { defaults in
            for json in [TailscaleFixture.serveOther8443, TailscaleFixture.serveBenchPlusMount, TailscaleFixture.serveFunnel,
                         TailscaleFixture.serveEmpty] {
                let runner = runner(serving: json)
                controller(runner, defaults).removeMappingAtQuit(within: 10)
                #expect(runner.changes.isEmpty, "\(json)")
            }
        }
    }

    @Test func quittingInADemoAsksTailscaleNothing() async throws {
        try await withDefaults(served: true) { defaults in
            let runner = runner(serving: TailscaleFixture.serveBench())
            controller(runner, defaults, demo: true).removeMappingAtQuit(within: 10)
            #expect(runner.calls.isEmpty)
            #expect(!ServeCleanup.shouldLook(demo: true, everServed: true))
        }
    }

    @Test func quittingAsksNothingOfSomeoneWhoNeverServed() async throws {
        try await withDefaults(served: false) { defaults in
            let runner = runner(serving: TailscaleFixture.serveBench())
            controller(runner, defaults).removeMappingAtQuit(within: 10)
            #expect(runner.calls.isEmpty)
            #expect(!ServeCleanup.shouldLook(demo: false, everServed: false))
            #expect(ServeCleanup.shouldLook(demo: false, everServed: true))
        }
    }

    @Test func quittingNeverWaitsLongerThanItsLimit() async throws {
        try await withDefaults(served: true) { defaults in
            let started = Date()
            controller(SlowRunner(seconds: 5), defaults).removeMappingAtQuit(within: 0.3)
            #expect(Date().timeIntervalSince(started) < 1.5)
        }
    }

    // MARK: Launching with the switch off

    @Test func launchingWithTheSwitchOffRemovesAMappingLeftBehind() async throws {
        try await withDefaults(served: true) { defaults in
            let runner = runner(serving: TailscaleFixture.serveBench())
            let remote = controller(runner, defaults)
            remote.reconcileAtLaunch()
            await remote.settle()
            #expect(runner.changes == [off])
            #expect(!remote.status.mappingLeft)
        }
    }

    @Test func launchingLeavesOtherMappingsAndNeverServedAlone() async throws {
        try await withDefaults(served: true) { defaults in
            let others = runner(serving: TailscaleFixture.serveOther8443)
            let remote = controller(others, defaults)
            remote.reconcileAtLaunch()
            await remote.settle()
            #expect(others.changes.isEmpty)
        }
        try await withDefaults(served: false) { defaults in
            let runner = runner(serving: TailscaleFixture.serveBench())
            let remote = controller(runner, defaults)
            remote.reconcileAtLaunch()
            await remote.settle()
            #expect(runner.calls.isEmpty)
        }
    }

    @Test func launchingWithTheSwitchOnLeavesItToTurningOn() async throws {
        try await withDefaults(served: true) { defaults in
            defaults.set(true, forKey: SettingsKey.remoteEnabled)
            let runner = runner(serving: TailscaleFixture.serveBench())
            let remote = controller(runner, defaults)
            remote.reconcileAtLaunch()
            await remote.settle()
            #expect(runner.calls.isEmpty)
        }
    }

    @Test func aMappingThatCantBeRemovedIsShownAndTriedAgain() async throws {
        try await withDefaults(served: true) { defaults in
            let runner = FakeTailscaleRunner([
                TailscaleCommands.serveStatus: [ok(TailscaleFixture.serveBench())],
                off: [TailscaleRun(exitStatus: 1, output: "error"), ok("")],
            ])
            let remote = controller(runner, defaults)
            remote.reconcileAtLaunch()
            await remote.settle()
            #expect(remote.status.mappingLeft)
            // Check Again, or Bench coming to the front: tried again, and gone.
            remote.refresh()
            await remote.settle()
            #expect(runner.changes == [off, off])
            #expect(!remote.status.mappingLeft)
        }
    }

    @Test func tailscaleNotRunningLeavesItToTryAgain() async throws {
        try await withDefaults(served: true) { defaults in
            let runner = FakeTailscaleRunner([TailscaleCommands.serveStatus: [TailscaleRun(exitStatus: 1, output: "failed to connect")]])
            let remote = controller(runner, defaults)
            remote.reconcileAtLaunch()
            await remote.settle()
            #expect(remote.status.mappingLeft)
            #expect(runner.changes.isEmpty)
        }
    }

    // MARK: The login

    @Test func anAddressKeptByAnEarlierBuildIsHashedAtLaunch() async throws {
        try await withDefaults(served: false) { defaults in
            defaults.set("pat@example.com", forKey: SettingsKey.remoteLogin)
            _ = controller(FakeTailscaleRunner([:]), defaults, demo: true)
            // Not in a demo, which touches no setting.
            #expect(defaults.string(forKey: SettingsKey.remoteLogin) == "pat@example.com")
            _ = controller(FakeTailscaleRunner([:]), defaults)
            #expect(defaults.string(forKey: SettingsKey.remoteLogin) == RemoteLogin.hash("pat@example.com"))
        }
    }
}
