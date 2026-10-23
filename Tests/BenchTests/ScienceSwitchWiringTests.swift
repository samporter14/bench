// ScienceSwitchWiringTests.swift — the parts of living beside Claude Science's
// own app that are wiring rather than rules: the inventory knows the new
// status keys and the page hook, `serve` is reached only through the plan, the
// read-only mode is the failure every "page ready" gate already respects, and
// the few files that had to change say so. Like CompatWiringTests these read
// Capsid's own source in this checkout; no daemon, no page and no app is touched.
import Foundation
import Testing
@testable import Bench

private enum Source {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func text(_ relative: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent("Sources/Bench/\(relative)"), encoding: .utf8)) ?? ""
    }

    static func count(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}

struct ScienceSwitchInventoryTests {
    private func item(_ kind: CompatKind, _ token: String) -> CompatDependency? {
        CompatInventory.dependencies(of: kind).first { $0.token == token }
    }

    @Test func theFourNewStatusKeysAreListedWithTheFeatureThatReliesOnThem() {
        let expected: [String: CompatFeature] = [
            "status.daemon.launch_context": .start,
            "status.daemon.boot": .start,
            "status.daemon.url_host": .signIn,
            "status.daemon.require_token": .signIn,
        ]
        for (token, feature) in expected {
            let found = item(.cli, token)
            #expect(found != nil, "\(token)")
            #expect(found?.feature == feature, "\(token)")
            #expect(found?.file == "Shared/Core/CLIStatus.swift", "\(token)")
            #expect(found?.check == .live, "\(token)")
        }
    }

    @Test func thePortIsListedAsUnknownWhenStatusNamesNone() {
        #expect(item(.cli, "status.port")?.detail.contains("unknown") == true)
        // And no 8765 is left in the parser to guess with.
        #expect(!Source.text("Shared/Core/CLIStatus.swift").contains("?? 8765"))
    }

    @Test func theToolsPlaceInsideTheAppAndTheNeverServeRuleAreWrittenDown() {
        #expect(item(.cli, "claude-science")?.detail.contains("Contents/Resources/bin") == true)
        let serve = item(.cli, "serve --no-browser --detached")
        #expect(serve?.detail.contains("never") == true)
        #expect(serve?.isWhenUsed == true)
    }

    @Test func theHandoverDialogIsAHookTheInventoryHoldsLiteralAndCheckedOnlyWhenUsed() {
        let hook = item(.pageHook, #"[data-testid="restarting-dialog"]"#)
        #expect(hook != nil)
        #expect(hook?.literal == true)
        #expect(hook?.isWhenUsed == true)
        #expect(hook?.feature == .handover)
        #expect(hook?.file == "Web/HandoverWatch.swift")
        #expect(CompatFeature.handover.title == "Staying with Claude Science when it opens in its own window")
        // It appears on the list of what is checked only when used.
        #expect(CompatReport.whenUsedLines().contains { $0.contains("restarting-dialog") })
    }

    @Test func theSignInPageIsAHookCheckedOnlyWhenUsed() {
        let hook = item(.pageHook, "/api/me?nonce=<code>")
        #expect(hook?.feature == .signIn)
        #expect(hook?.isWhenUsed == true)
        #expect(hook?.literal == false)
        // The address is built in one place, and nothing else builds it.
        #expect(Source.text("Web/DaemonPolicy.swift").contains(#"parts.path = "/api/me""#))
        #expect(!Source.text("Web/WebContainer.swift").contains(#""/api/me""#))
    }

    @Test func theWatchScriptIsTheOneThatHoldsTheDialogSelectorAndTheSignInScriptStillOnlyTheButton() {
        #expect(HandoverWatch.script.contains(#"[data-testid="restarting-dialog"]"#))
        // Every restart shows the dialog, so its words are compared in the page with the handover's one
        // phrase, and only a yes ever leaves it: the one postMessage carries `shown: true` and nothing read.
        #expect(HandoverWatch.script.contains("now opens in its own window"))
        #expect(HandoverWatch.script.components(separatedBy: "postMessage(").count == 2)
        #expect(HandoverWatch.script.contains("handler.postMessage({ shown: true })"))
        #expect(!SignInScript.press.contains("restarting-dialog") && !SignInScript.look.contains("restarting-dialog"))
    }
}

struct ScienceSwitchWiringTests {
    @Test func serveIsRunFromOneCallThatTheStartPlanGatesAndNothingElseCallsIt() {
        let controller = Source.text("Web/DaemonController.swift")
        #expect(Source.count(of: "launchDetached()", in: controller) == 2) // the definition and the one call
        let decided = controller.range(of: "StartPlan.decide(")
        let called = controller.range(of: "try await offMain { try launchDetached() }")
        #expect(decided != nil && called != nil)
        if let decided, let called { #expect(decided.lowerBound < called.lowerBound) }
        // The call sits in the `.serve` case and the other cases return or throw before it.
        #expect(controller.contains("case .waitForApp(let reason):"))
        #expect(controller.contains("throw DaemonError.appOwnsServer"))
        // The automatic tries ask `status` and never start anything.
        #expect(Source.text("Web/StartRetry.swift").contains("DaemonController.runningStatus()"))
        #expect(!Source.text("Web/StartRetry.swift").contains("ensureRunning"))
        // And no other file runs the tool with `serve`.
        for file in ["Web/WebContainer.swift", "Web/HandoverWatch.swift", "Web/DaemonPolicy.swift", "App/ScienceInstall.swift",
                     "Shared/Core/CLIStatus.swift", "App/Diagnose.swift"] {
            #expect(!Source.text(file).contains(#""serve""#), "\(file)")
        }
    }

    @Test func theStartAskedForIsGivenWhatTheHandoverSaw() {
        #expect(Source.text("Web/WebContainer.swift").contains("DaemonController.ensureRunning(handoverSeen: handover.seen)"))
    }

    @Test func onlyReadingIsTheFailureSoEveryPageReadyGateIsAlreadyOff() {
        let container = Source.text("Web/WebContainer.swift")
        #expect(container.contains("fail(CompanionSentence.readOnly, temporary: false, companion: .readOnly(reason))"))
        // A failure that stops the tries: nothing here starts them again.
        let enter = container.range(of: "private func enterReadOnly")
        #expect(enter != nil)
        if let enter {
            let body = String(container[enter.lowerBound...].prefix(600))
            #expect(!body.contains("retry.begin()"))
        }
        // The window is only ever "ready" after a daemon page finished, and never for the sign-in step.
        #expect(container.contains("guard !SignInPlan.isSignInStep(url) else { return }"))
        // Entering any other state drops the mode.
        #expect(container.contains("companion = .none"))
    }

    @Test func theRouterOpensClaudeScienceInsteadOnlyWhileReading() {
        let container = Source.text("Web/WebContainer.swift")
        #expect(container.contains("Router.shared.openInScience = { ScienceApp.open(.show) }"))
        #expect(container.contains("Router.shared.openInScience = nil"))
        #expect(Source.count(of: "openInScience", in: Source.text("App/Router.swift")) >= 4)
    }

    @Test func theButtonStartsTheAppInTheBackgroundWhileWaitingAndShowsItWhileReading() {
        let container = Source.text("Web/WebContainer.swift")
        let waiting = container.range(of: "ScienceApp.open(.startServer)")
        let showing = container.range(of: "ScienceApp.open(.show)\n        }\n    }")
        #expect(waiting != nil && showing != nil)
        #expect(ScienceApp.Reason.startServer.activates == false)
        #expect(ScienceApp.Reason.show.activates == true)
    }

    @Test func theInstallIsNeverReadOnTheMainThreadByTheStartOrTheSignIn() {
        let container = Source.text("Web/WebContainer.swift")
        #expect(!container.contains("ScienceInstall.current()"))
        #expect(container.contains("await DaemonController.installedOpens()"))
    }

    @Test func theOverlayOffersOpenClaudeScienceNextToTryAgainOnlyBesideTheApp() {
        let view = Source.text("Web/BrowserView.swift")
        #expect(view.contains("CompanionSentence.openButton"))
        #expect(view.contains("if companion == .none"))
        #expect(view.contains("openScience: web.openScience"))
    }

    @Test func theHandoverWatchIsInstalledOnTheMainViewAndKept() {
        let container = Source.text("Web/WebContainer.swift")
        #expect(container.contains("watch.install(on: configuration.userContentController)"))
        // The controller holds its handler weakly, so the container holds the watch.
        #expect(container.contains("handoverWatch = watch"))
        #expect(Source.text("Web/HandoverWatch.swift").contains("injectionTime: .atDocumentEnd, forMainFrameOnly: true"))
    }

    @Test func theDialogStopsTheTriesBeforeAnythingElse() {
        let container = Source.text("Web/WebContainer.swift")
        #expect(container.contains("stopRetries: { [unowned self] in retry.stop(resetting: true) }"))
        #expect(container.contains("post: { LabModel.shared.post($0) }"))
        // The watch for the new daemon asks `status` only: a StartRetry, never `ensureRunning`.
        #expect(container.contains("private lazy var newDaemonWatch: StartRetry = StartRetry("))
        #expect(container.contains("DaemonController.runningStatus()"))
    }

    @Test func theSignInStepIsShownNotSavedAndItsRefusalDoesNotCostTheRetry() {
        let delegate = Source.text("Web/NavigationDelegates.swift")
        let refused = delegate.range(of: "container?.signInRejected(at: url) == true")
        let allowed = delegate.range(of: "SignInPlan.isSignInStep(navigationResponse.response.url) { return .allow }")
        let download = delegate.range(of: "Downloads.policy(for: navigationResponse) ?? .allow")
        #expect(refused != nil && allowed != nil && download != nil)
        if let refused, let allowed, let download {
            #expect(refused.lowerBound < allowed.lowerBound && allowed.lowerBound < download.lowerBound)
        }
        let container = Source.text("Web/WebContainer.swift")
        let rejected = container.range(of: "func signInRejected(at url: URL) -> Bool {")
        let early = container.range(of: "if SignInPlan.isSignInStep(url) {")
        let once = container.range(of: "let now = ContinuousClock.now\n        if let last = lastSignInRetry")
        #expect(rejected != nil && early != nil && once != nil)
        if let early, let once { #expect(early.lowerBound < once.lowerBound) }
    }

    @Test func noCodeBesideTheAppEndsSigningInInsteadOfRetrying() {
        let container = Source.text("Web/WebContainer.swift")
        #expect(container.contains("switch SignInPlan.outcomeWithoutCode(appOwned: owned)"))
        #expect(container.contains("case .readOnly(let reason): enterReadOnly(reason)"))
        #expect(container.contains(#"case .retryLater: fail("Couldn't get a sign-in code from Claude Science.", temporary: true)"#))
    }

    @Test func aDaemonWithNoPortIsAFailureThatMayPassNeverAGuess() {
        let container = Source.text("Web/WebContainer.swift")
        #expect(container.contains("fail(DaemonError.noPort.sentence, temporary: true)"))
        #expect(!container.contains("8765"))
        #expect(!Source.text("Web/DaemonController.swift").contains("8765"))
    }

    @Test func diagnosticsShowsTheInstallTheToolsPlaceAndTheDaemonsKeys() {
        let diagnose = Source.text("App/Diagnose.swift")
        #expect(diagnose.contains("let install = ScienceInstall.current()"))
        #expect(diagnose.contains("install.lines()"))
        #expect(diagnose.contains("resolveCLI(install: install)"))
        #expect(diagnose.contains("daemonLines(status: status, install: install.opens)"))
        #expect(diagnose.contains("Diagnose.windowLines(companion: WebContainer.shared.companion)"))
        // The line the brief asks for.
        #expect(Source.text("App/ScienceInstall.swift").contains(#""• Claude Science opens in: \(opensPhrase)""#))
    }

    @Test func theInstallIsReadFreshAtEachUseBecauseTheSwitchHappensWhileCapsidRuns() {
        // Nothing caches the detection.
        let install = Source.text("App/ScienceInstall.swift")
        #expect(!install.contains("static let current"))
        #expect(install.contains("static func current() -> ScienceInstall"))
        // And it reads the plist, not a cached bundle.
        #expect(!install.contains("Bundle(path:"))
    }
}
