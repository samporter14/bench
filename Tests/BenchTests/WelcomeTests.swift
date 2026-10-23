// WelcomeTests.swift — when the first-run welcome shows (once, and not to
// someone who used Bench before it), and the steps between its pages. Each
// test with defaults uses its own throwaway suite, never the real settings.
import Foundation
import Testing
@testable import Bench

struct WelcomeTests {
    /// A suite of its own, with the defaults Bench registers at launch, as
    /// `SettingsKey.register()` does for the real ones.
    private func suite(registering: Bool = true, _ body: (UserDefaults, String) throws -> Void) throws {
        let scratch = ScratchDefaults.make(prefix: "WelcomeTests")
        defer { scratch.discard() }
        let defaults = scratch.defaults
        if registering {
            defaults.register(defaults: [
                SettingsKey.showPanel: true,
                SettingsKey.appearance: BenchAppearance.system.rawValue,
                SettingsKey.checkForUpdates: true,
            ])
        }
        try body(defaults, scratch.name)
    }

    // MARK: Someone who used Bench before

    @Test func nothingStoredIsNewcomer() {
        #expect(!WelcomeGate.isExistingUser(storedKeys: []))
        #expect(WelcomeGate.shouldShow(hasSeen: false, storedKeys: []))
    }

    @Test(arguments: ["sceneGroups", "settingsTab", "appearance", "showLabPanel"])
    func anyOneOfTheEarlierSettingsMakesAnExistingUser(key: String) {
        #expect(WelcomeGate.isExistingUser(storedKeys: [key]))
        #expect(WelcomeGate.isExistingUser(storedKeys: [key, "pageZoom", "NSWindow Frame BenchMain"]))
        #expect(!WelcomeGate.shouldShow(hasSeen: false, storedKeys: [key]))
    }

    @Test func theKeysAreTheOnesTheAppWrites() {
        #expect(SettingsKey.settingsTab == "settingsTab")
        #expect(SettingsKey.appearance == "appearance")
        #expect(SettingsKey.showPanel == "showLabPanel")
        #expect(WelcomeGate.earlierSettings == ["sceneGroups", "settingsTab", "appearance", "showLabPanel"])
    }

    @Test func otherSettingsDoNotMakeAnExistingUser() {
        // What a first launch can leave behind, and the welcome's own keys.
        let stored: Set = [SettingsKey.hasSeenWelcome, SettingsKey.checkForUpdates, SettingsKey.pageZoom,
                           SettingsKey.showCards, "NSWindow Frame BenchMain"]
        #expect(!WelcomeGate.isExistingUser(storedKeys: stored))
        #expect(WelcomeGate.shouldShow(hasSeen: false, storedKeys: stored))
    }

    @Test func someoneWhoHasSeenItIsNotShownItAgain() {
        #expect(!WelcomeGate.shouldShow(hasSeen: true, storedKeys: []))
        #expect(!WelcomeGate.shouldShow(hasSeen: true, storedKeys: ["appearance"]))
    }

    // MARK: At launch, against real defaults

    @Test func registeredDefaultsDoNotMakeAnInstallLookUsed() throws {
        try suite { defaults, name in
            // `object(forKey:)` sees the registered values, so it can't tell.
            #expect(defaults.object(forKey: SettingsKey.showPanel) != nil)
            #expect(defaults.object(forKey: SettingsKey.appearance) != nil)
            #expect(WelcomeGate.storedKeys(in: defaults, domain: name).isEmpty)
            #expect(WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
        }
    }

    @Test func shownOnceThenNotAgain() throws {
        try suite { defaults, name in
            #expect(WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
            // Still shown until it is closed: nothing is recorded by asking.
            #expect(WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
            // Closing it, however it is closed, records it.
            WelcomeGate.markSeen(in: defaults)
            #expect(defaults.bool(forKey: SettingsKey.hasSeenWelcome))
            #expect(!WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
            #expect(!WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
        }
    }

    @Test func switchingUpdatesOnInTheWelcomeDoesNotMakeAnExistingUser() throws {
        try suite { defaults, name in
            defaults.set(true, forKey: SettingsKey.checkForUpdates)
            #expect(WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
        }
    }

    @Test(arguments: ["sceneGroups", "settingsTab", "appearance", "showLabPanel"])
    func anExistingUserIsMarkedAsHavingSeenIt(key: String) throws {
        try suite { defaults, name in
            #expect(!defaults.bool(forKey: SettingsKey.hasSeenWelcome))
            defaults.set(key == "sceneGroups" ? ["lab"] : "value", forKey: key)
            #expect(!WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
            #expect(defaults.bool(forKey: SettingsKey.hasSeenWelcome))
            #expect(!WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
        }
    }

    @Test func aSettingStoredAsOffStillCountsAsUsed() throws {
        try suite { defaults, name in
            defaults.set(false, forKey: SettingsKey.showPanel)
            #expect(!WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
        }
    }

    @Test func aNewcomerWhoChangesASettingWhileItIsOpenIsStillRecordedWhenItCloses() throws {
        try suite { defaults, name in
            #expect(WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
            defaults.set("dark", forKey: SettingsKey.appearance)
            WelcomeGate.markSeen(in: defaults)
            #expect(!WelcomeGate.shouldShowAtLaunch(defaults: defaults, domain: name))
        }
    }

    // MARK: The pages

    @Test func thereAreFourPagesAndItStartsOnTheFirst() {
        #expect(WelcomePage.allCases.count == 4)
        let flow = WelcomeFlow()
        #expect(flow.page == .welcome)
        #expect(flow.isFirst)
        #expect(!flow.isLast)
    }

    @Test func nextWalksToTheLastPageAndStopsThere() {
        var flow = WelcomeFlow()
        var seen = [flow.page]
        for _ in 0..<3 {
            flow.next()
            seen.append(flow.page)
        }
        #expect(seen == [.welcome, .panel, .gettingAround, .updates])
        #expect(flow.isLast)
        #expect(!flow.isFirst)
        flow.next()
        #expect(flow.page == .updates)
        #expect(flow.isLast)
    }

    @Test func backWalksToTheFirstPageAndStopsThere() {
        var flow = WelcomeFlow(startingAt: 4)
        flow.back()
        #expect(flow.page == .gettingAround)
        flow.back()
        flow.back()
        #expect(flow.page == .welcome)
        #expect(flow.isFirst)
        flow.back()
        #expect(flow.page == .welcome)
    }

    @Test func backUndoesNext() {
        var flow = WelcomeFlow(startingAt: 2)
        flow.next()
        flow.back()
        #expect(flow == WelcomeFlow(startingAt: 2))
    }

    @Test func aStartingPageCountsFromOneAndIsKeptInRange() {
        #expect(WelcomeFlow(startingAt: nil).page == .welcome)
        #expect(WelcomeFlow(startingAt: 1).page == .welcome)
        #expect(WelcomeFlow(startingAt: 2).page == .panel)
        #expect(WelcomeFlow(startingAt: 3).page == .gettingAround)
        #expect(WelcomeFlow(startingAt: 4).page == .updates)
        #expect(WelcomeFlow(startingAt: 0).page == .welcome)
        #expect(WelcomeFlow(startingAt: -7).page == .welcome)
        #expect(WelcomeFlow(startingAt: 5).page == .updates)
        #expect(WelcomeFlow(startingAt: 99).page == .updates)
    }
}
