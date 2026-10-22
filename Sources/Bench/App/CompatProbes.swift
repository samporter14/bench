// CompatProbes.swift — Diagnostics' live look at what Capsid reads from the
// Claude Science page and its API (DESIGN.md, Diagnostics). It runs only when
// the user opens Diagnostics, and it only looks:
//
//   - the page hooks that are on screen now, through the page's own scripts;
//   - the reads that `WebContainer.apiGET` is allowed to make, each answered
//     in the shape Capsid parses, checked by the very parsers the app uses.
//
// The probes have no way to write: the environment they are given holds four
// reads (`apiGET`, Keep's typed artifact read, and the two projected counts of
// step progress and the reviewer's findings) and two looks, and no POST.
// The phone's readers (messages, artifact lists, live text), Keep's lineage and
// every write are listed as checked only when used: the first return what was
// said or made, which Diagnostics never reads (the notes are among them), the
// lineage can start Claude Science's own code reconstruction, and the rest
// change things. Keep's other two reads (an artifact's versions, one version's
// facts) are pure, and run on the shown session's plan artifact; so do the two
// projected reads, which answer in counts and never hand a title or a finding
// to Swift.
//
// A probe says one of four things: it answered as expected, it answered in a
// shape Capsid doesn't read, the thing isn't on screen right now (a tab strip
// with no tab open, a session page with none shown), or it failed. "Not on
// screen now" is never a fault. Nothing a probe reports names a session, a
// project, a tab or a file: only counts and the words below.
import Foundation

// MARK: What a probe says

enum ProbeVerdict: Equatable, Sendable {
    /// It answered as expected; the text says what was found (may be empty).
    case ok(String)
    /// It answered, but not in the shape Capsid reads.
    case unexpectedShape(String)
    /// It only exists in some states, and this isn't one.
    case notOnScreenNow(String)
    /// It couldn't be tried: refused, signed out, slow, or gone.
    case failed(String)
}

struct ProbeResult: Equatable, Sendable {
    let name: String
    let verdict: ProbeVerdict

    /// The Diagnostics line, in its style: ✓ for fine, ✗ for a problem and
    /// • for what couldn't be told.
    var line: String {
        switch verdict {
        case .ok(let found): "✓ \(name)\(found.isEmpty ? "" : ": \(found)")"
        case .unexpectedShape(let why): "✗ \(name): not the shape Capsid reads (\(why))"
        case .notOnScreenNow(let why): "• \(name): not on screen now (\(why))"
        case .failed(let why): "✗ \(name): couldn't be checked (\(why))"
        }
    }
}

struct ProbeTimeout: Error {}

// MARK: The rules

/// What each answer means. Pure, and tested on made-up data.
enum CompatProbeRules {
    // MARK: Page

    /// How the tab strip looked (`PageTabsScript.probe`'s JSON).
    static func tabStrip(_ json: String) -> ProbeVerdict {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let strip = object["strip"] as? String,
              let tabs = count(object["tabs"]), let withButton = count(object["withButton"]),
              let withClose = count(object["withClose"]), let shown = count(object["shown"]) else {
            return .unexpectedShape("the page's answer wasn't understood")
        }
        switch strip {
        case "none":
            return .notOnScreenNow("no tab is open; open one and run this again")
        case "several":
            return .unexpectedShape("the page has more than one tab strip")
        case "no-toolbar":
            return .unexpectedShape("the strip has no toolbar of open panels")
        case "ok":
            if tabs == 0 { return .ok("strip and toolbar found, with no tab to look at") }
            if withButton < tabs { return .unexpectedShape("\(tabs - withButton) of \(tabs) tabs have no button that shows them") }
            if withClose < tabs { return .unexpectedShape("\(tabs - withClose) of \(tabs) tabs have no close button") }
            if shown != 1 { return .unexpectedShape("\(shown) of \(tabs) tabs are marked as shown, not one") }
            return .ok("\(tabs) tab\(tabs == 1 ? "" : "s"), each with a close button, one shown")
        default:
            return .unexpectedShape("the page's answer wasn't understood")
        }
    }

    private static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let count = number.intValue
        return (0...PageTabsOutcome.cap).contains(count) && number.doubleValue == Double(count) ? count : nil
    }

    /// The sign-in button shows only while signed out.
    static func signIn(showing: Bool) -> ProbeVerdict {
        showing ? .ok("found, which means the page is signed out")
                : .notOnScreenNow("it shows only while signed out, so this can't be checked until then")
    }

    /// A session's address, `/projects/<project>/frames/<session>`.
    static func sessionAddress(shown: String?) -> ProbeVerdict {
        shown == nil ? .notOnScreenNow("no session is open in the window")
                     : .ok("the page names the session shown")
    }

    // MARK: API reads

    static func usage(_ data: Data) -> ProbeVerdict {
        do {
            let limits = try PlanUsageModel.parse(data).limits
            if limits.isEmpty { return .unexpectedShape(CompatMiss.usageWithoutLimits.phrase) }
            return .ok("\(limits.count) limit\(limits.count == 1 ? "" : "s") read")
        } catch PlanUsageModel.PlanUsageError.refused {
            return .unexpectedShape("the answer says ok: false")
        } catch {
            return .unexpectedShape(CompatMiss.usageNotDecoded.phrase)
        }
    }

    static func context(_ data: Data) -> ProbeVerdict {
        guard let series = try? TokenSeries.decode(data) else { return .unexpectedShape(CompatMiss.contextNotDecoded.phrase) }
        if let miss = series.shapeMiss { return .unexpectedShape(miss.phrase) }
        let turns = series.turns?.count ?? 0
        return .ok("a window size and \(turns) turn\(turns == 1 ? "" : "s")")
    }

    /// The shown session's shallow frame, and the frame itself for the plan
    /// probe after it.
    static func frame(_ data: Data) -> (verdict: ProbeVerdict, frame: PlanFrame?) {
        guard let frame = PlanFrame(json: data) else {
            return (.unexpectedShape(CompatMiss.planFrameNotUnderstood.phrase), nil)
        }
        if let miss = PlanCheck.frameMiss(frame) { return (.unexpectedShape(miss.phrase), frame) }
        return (.ok("a status, and the plan fields if it has a plan"), frame)
    }

    static func plan(_ data: Data) -> ProbeVerdict {
        let plan = PlanDocument(json: data)
        if let miss = PlanCheck.planMiss(plan) { return .unexpectedShape(miss.phrase) }
        let steps = plan?.steps.map { ", \($0) step\($0 == 1 ? "" : "s")" } ?? ""
        return .ok("a summary\(steps)")
    }

    // MARK: Keep's reads

    /// An artifact's versions (Keep): at least one, each with a number (the
    /// reader refuses a row without one) and a time.
    static func versions(_ outcome: ArtifactReadOutcome) -> ProbeVerdict {
        guard case .versions(let rows) = outcome else { return failure(outcome, miss: .keepVersionsNotUnderstood) }
        if rows.isEmpty { return .unexpectedShape("the list was empty") }
        let timeless = rows.filter { $0.at == nil }.count
        if timeless > 0 { return .unexpectedShape("\(timeless) of \(rows.count) versions have no time") }
        return .ok("\(rows.count) version\(rows.count == 1 ? "" : "s"), each with a number and a time")
    }

    /// One version's facts (Keep): the answer is for the version asked, has a
    /// number, and a checksum that is 64 hex digits (the reader nils anything
    /// else) or none.
    static func facts(_ outcome: ArtifactReadOutcome, version: String) -> ProbeVerdict {
        guard case .facts(let facts) = outcome else { return failure(outcome, miss: .keepFactsNotUnderstood) }
        guard facts.v == version else { return .unexpectedShape("the answer was for another version") }
        guard facts.n != nil else { return .unexpectedShape("the answer has no version number") }
        return facts.sha == nil ? .ok("a number, and no checksum (a file read from your Mac may have none)")
                                : .ok("a checksum and a number")
    }

    // MARK: Step progress and the reviewer

    /// The shown session's plan progress, as the page projected it: counts
    /// and words only, never a step's title.
    static func progress(_ read: PlanProgressRead) -> ProbeVerdict {
        func frames(_ facts: PlanProgressFacts) -> String {
            "\(facts.children) frame\(facts.children == 1 ? "" : "s") directly below the session"
        }
        switch read {
        case .progress(let value, let facts):
            if facts.unknown > 0 { return .unexpectedShape(CompatMiss.progressStatusNotUnderstood.phrase) }
            return .ok("step \(value.step) of \(value.total), \(facts.reported) step\(facts.reported == 1 ? "" : "s") reporting, \(frames(facts))")
        case .idle(let why, let facts):
            if facts.unknown > 0 { return .unexpectedShape(CompatMiss.progressStatusNotUnderstood.phrase) }
            switch why {
            case .notApproved: return .notOnScreenNow("the shown session has no approved plan")
            case .noPlan: return .notOnScreenNow("the shown session's plan has no phases or steps")
            case .planMissing: return .unexpectedShape(CompatMiss.progressTreeWithoutPlan.phrase)
            case .noStatuses: return .notOnScreenNow("no plan step has reported a status yet")
            case .complete: return .ok("every step is done, \(frames(facts))")
            }
        case .unreadable: return .unexpectedShape(CompatMiss.progressTreeNotUnderstood.phrase)
        case .lost: return .failed("signed out (401); Capsid signs back in by itself")
        case .missing: return .failed("answered 404: the route may have moved, or that session is gone")
        case .tooBig: return .failed("the answer exceeded the read limit")
        case .cancelled: return .failed("the read didn't complete")
        }
    }

    /// The shown session's reviewer counts. A session nobody reviewed answers
    /// an empty list, which is four zeros and no fault.
    static func reviewer(_ read: ReviewerRead) -> ProbeVerdict {
        switch read {
        case .counts(let counts):
            return .ok("\(counts.standing) standing, \(counts.fixed) fixed, \(counts.running) running, \(counts.reviews) finished")
        case .unreadable: return .unexpectedShape(CompatMiss.reviewerAnswerNotUnderstood.phrase)
        case .lost: return .failed("signed out (401); Capsid signs back in by itself")
        case .missing: return .failed("answered 404: the route may have moved, or that session is gone")
        case .tooBig: return .failed("the answer exceeded the read limit")
        case .cancelled: return .failed("the read didn't complete")
        }
    }

    /// Why a typed artifact read didn't come back as the shape it was asked for.
    static func failure(_ outcome: ArtifactReadOutcome, miss: CompatMiss) -> ProbeVerdict {
        switch outcome {
        case .lost: .failed("signed out (401); Capsid signs back in by itself")
        case .missing: .failed("answered 404: the route may have moved, or that session is gone")
        case .tooBig: .failed("the answer exceeded the read limit")
        case .cancelled: .failed("the read didn't complete")
        default: .unexpectedShape(miss.phrase)
        }
    }

    /// Why a read didn't come back, from the page's own words. Only the HTTP
    /// status is taken from the error: its text can hold an address.
    static func failure(_ error: any Error) -> ProbeVerdict {
        if error is ProbeTimeout { return .failed("no answer in time") }
        if let known = error as? WebAPIError {
            switch known {
            case .notReady: return .notOnScreenNow("the page isn't up yet")
            case .notAllowed: return .failed("Capsid's list of readable paths doesn't allow it")
            case .badResponse: return .unexpectedShape("the page didn't hand back text")
            case .timedOut: return .failed("no answer in time")
            case .responseTooLarge: return .failed("the answer exceeded the read limit")
            }
        }
        let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? ""
        if let status = httpStatus(in: message) {
            switch status {
            case 401: return .failed("signed out (401); Capsid signs back in by itself")
            case 404, 405, 410: return .failed("answered \(status): the route may have moved, or that session is gone")
            default: return .failed("answered \(status)")
            }
        }
        return .failed("the read didn't complete")
    }

    /// The three digits after "HTTP ", the page's own message for a refusal.
    static func httpStatus(in message: String) -> Int? {
        guard let range = message.range(of: "HTTP ") else { return nil }
        let digits = message[range.upperBound...].prefix(3)
        return digits.count == 3 ? Int(digits) : nil
    }
}

// MARK: Running them

/// What the probes may touch. A read of Claude Science's API through the
/// page, a look at the tab strip and a look for the Sign in button: no write
/// of any kind is in here to call.
@MainActor
struct CompatProbeEnvironment {
    var isReady: @MainActor @Sendable () -> Bool
    var shownSession: @MainActor @Sendable () -> String?
    /// `WebContainer.apiGET`: a path under `/api`, the body.
    var get: @MainActor @Sendable (String) async throws -> Data
    /// `PageTabsScript.probe`'s JSON.
    var tabStrip: @MainActor @Sendable () async throws -> String
    var signInShowing: @MainActor @Sendable () async throws -> Bool
    /// `WebContainer.readArtifact`: one of Keep's reads, projected in the page
    /// and checked again. The probes ask only for an artifact's versions and a
    /// version's facts, never the lineage, which can start a reconstruction.
    var artifactRead: @MainActor @Sendable (ArtifactRead) async throws -> ArtifactReadOutcome
    /// `WebContainer.readPlanProgress`: the shown session's tree, projected
    /// in the page to a step number, a total and at most one title.
    var planProgress: @MainActor @Sendable (String) async throws -> PlanProgressRead
    /// `WebContainer.readReviewerCounts`: its findings, projected in the page
    /// to four counts.
    var reviewerCounts: @MainActor @Sendable (String) async throws -> ReviewerRead
    /// How long any one probe may take before it is called failed.
    var timeout: Duration = .seconds(6)

    static func live() -> CompatProbeEnvironment {
        CompatProbeEnvironment(
            isReady: { WebContainer.shared.status == .ready },
            shownSession: { WebContainer.shared.currentFrameID },
            get: { try await WebContainer.shared.apiGET($0) },
            tabStrip: { try await WebContainer.shared.readTabStrip() },
            signInShowing: { try await WebContainer.shared.signInButtonIsShowing() },
            artifactRead: { try await WebContainer.shared.readArtifact($0) },
            planProgress: { try await WebContainer.shared.readPlanProgress($0) },
            reviewerCounts: { try await WebContainer.shared.readReviewerCounts($0) })
    }
}

enum CompatProbes {
    /// The probes' names. The reads are named as the inventory names them.
    enum Name {
        static let tabStrip = "Tab strip"
        static let signIn = "Sign in button"
        static let address = "Session address"
        static let usage = "GET /api/usage"
        static let context = "GET /api/frames/<session>/token-series"
        static let frame = "GET /api/frames/<session>?shallow=true"
        static let plan = "GET /api/artifacts/versions/<version>"
        static let versions = "GET /api/artifacts/<artifact>/versions"
        static let facts = "GET /api/artifacts/versions/<version>?include_metadata=true"
        static let progress = "plan statuses on GET /api/frames/<session>/trace-shallow?include_messages=false"
        static let reviewer = "GET /api/frames/<session>/verification?resolved_limit=0&actionable_limit=500"

        static let all = [tabStrip, signIn, address, usage, context, frame, plan, versions, facts, progress, reviewer]
    }

    /// Every probe, in order. Never throws: what goes wrong is a verdict.
    @MainActor
    static func run(_ env: CompatProbeEnvironment) async -> [ProbeResult] {
        guard env.isReady() else {
            return Name.all.map { ProbeResult(name: $0, verdict: .notOnScreenNow("the page isn't up yet")) }
        }
        var results: [ProbeResult] = []
        func add(_ name: String, _ verdict: ProbeVerdict) { results.append(ProbeResult(name: name, verdict: verdict)) }

        // The page's own hooks.
        switch await timed(env.timeout, env.tabStrip) {
        case .success(let json): add(Name.tabStrip, CompatProbeRules.tabStrip(json))
        case .failure(let error): add(Name.tabStrip, CompatProbeRules.failure(error))
        }
        switch await timed(env.timeout, env.signInShowing) {
        case .success(let showing): add(Name.signIn, CompatProbeRules.signIn(showing: showing))
        case .failure(let error): add(Name.signIn, CompatProbeRules.failure(error))
        }
        let session = env.shownSession()
        add(Name.address, CompatProbeRules.sessionAddress(shown: session))

        // The reads.
        switch await timed(env.timeout, { try await env.get("/usage") }) {
        case .success(let data): add(Name.usage, CompatProbeRules.usage(data))
        case .failure(let error): add(Name.usage, CompatProbeRules.failure(error))
        }

        guard let session else {
            let none = ProbeVerdict.notOnScreenNow("no session is open in the window")
            for name in [Name.context, Name.frame, Name.plan, Name.versions, Name.facts, Name.progress, Name.reviewer] {
                add(name, none)
            }
            return results
        }
        switch await timed(env.timeout, { try await env.get(ContextModel.seriesPath(for: session)) }) {
        case .success(let data): add(Name.context, CompatProbeRules.context(data))
        case .failure(let error): add(Name.context, CompatProbeRules.failure(error))
        }

        // The frame and, if it names a plan, the plan. Both need a full id.
        guard let framePath = PlanCheck.framePath(session) else {
            add(Name.frame, .unexpectedShape("the session's id isn't the 36-character id Capsid reads"))
            let unreadable = ProbeVerdict.notOnScreenNow("the session has no readable id")
            for name in [Name.plan, Name.versions, Name.facts, Name.progress, Name.reviewer] { add(name, unreadable) }
            return results
        }
        var shownFrame: PlanFrame?
        switch await timed(env.timeout, { try await env.get(framePath) }) {
        case .success(let data):
            let read = CompatProbeRules.frame(data)
            shownFrame = read.frame
            add(Name.frame, read.verdict)
        case .failure(let error):
            add(Name.frame, CompatProbeRules.failure(error))
        }
        if let version = shownFrame?.versionID, let planPath = PlanCheck.versionPath(version) {
            switch await timed(env.timeout, { try await env.get(planPath) }) {
            case .success(let data): add(Name.plan, CompatProbeRules.plan(data))
            case .failure(let error): add(Name.plan, CompatProbeRules.failure(error))
            }
            // Keep's two pure reads, on the plan's artifact.
            let keep = await keepReads(env, version: version, artifact: shownFrame?.artifactID)
            add(Name.versions, keep.versions)
            add(Name.facts, keep.facts)
        } else {
            let none = ProbeVerdict.notOnScreenNow("the shown session has no plan")
            for name in [Name.plan, Name.versions, Name.facts] { add(name, none) }
        }

        // Step progress and the reviewer's findings: projected in the page to
        // counts, so these are pure reads too, whether or not there is a plan.
        switch await timed(env.timeout, { try await env.planProgress(session) }) {
        case .success(let read): add(Name.progress, CompatProbeRules.progress(read))
        case .failure(let error): add(Name.progress, CompatProbeRules.failure(error))
        }
        switch await timed(env.timeout, { try await env.reviewerCounts(session) }) {
        case .success(let read): add(Name.reviewer, CompatProbeRules.reviewer(read))
        case .failure(let error): add(Name.reviewer, CompatProbeRules.failure(error))
        }
        return results
    }

    /// An artifact's versions and one version's facts, for the plan the shown
    /// session has. The facts are read first: they name the artifact when the
    /// frame didn't. Neither read writes, and neither is the lineage.
    @MainActor
    private static func keepReads(_ env: CompatProbeEnvironment, version: String, artifact: String?)
        async -> (versions: ProbeVerdict, facts: ProbeVerdict) {
        var artifactID = artifact.flatMap { PlanCheck.isUUIDLike($0) ? $0 : nil }
        let facts: ProbeVerdict
        if PlanCheck.isUUIDLike(version) {
            switch await timed(env.timeout, { try await env.artifactRead(.facts(version: version)) }) {
            case .success(let outcome):
                facts = CompatProbeRules.facts(outcome, version: version)
                if artifactID == nil, case .facts(let known) = outcome { artifactID = known.a }
            case .failure(let error):
                facts = CompatProbeRules.failure(error)
            }
        } else {
            facts = .notOnScreenNow("the shown session's plan has no 36-character version id")
        }
        let versions: ProbeVerdict
        if let artifactID {
            switch await timed(env.timeout, { try await env.artifactRead(.versions(artifact: artifactID)) }) {
            case .success(let outcome): versions = CompatProbeRules.versions(outcome)
            case .failure(let error): versions = CompatProbeRules.failure(error)
            }
        } else {
            versions = .notOnScreenNow("the shown session's plan has no 36-character artifact id")
        }
        return (versions, facts)
    }

    /// `work`, or a timeout. The probe that is slow is left running and
    /// forgotten: a fetch inside the page can't be cancelled from here.
    @MainActor
    static func timed<T: Sendable>(_ limit: Duration, _ work: @escaping @MainActor @Sendable () async throws -> T) async -> Result<T, any Error> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result<T, any Error>, Never>) in
            let gate = OneShot(continuation)
            Task { @MainActor in
                do { gate.finish(.success(try await work())) } catch { gate.finish(.failure(error)) }
            }
            Task {
                try? await Task.sleep(for: limit)
                gate.finish(.failure(ProbeTimeout()))
            }
        }
    }

    /// Resumes a continuation once, whichever of the two tasks gets there first.
    private final class OneShot<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Result<T, any Error>, Never>?

        init(_ continuation: CheckedContinuation<Result<T, any Error>, Never>) {
            self.continuation = continuation
        }

        func finish(_ result: Result<T, any Error>) {
            lock.lock()
            let taken = continuation
            continuation = nil
            lock.unlock()
            taken?.resume(returning: result)
        }
    }
}

// MARK: The report

/// The Diagnostics lines this feature adds. Pure apart from what it is given.
enum CompatReport {
    static let probesHeading = "Claude Science's page and API (only looked at; nothing is written):"
    static let whenUsedHeading = "Checked only when used:"
    static let notFromTheCommandLine = "• Page and API checks: run Help → Capsid Diagnostics… in the app (they need its open window)"

    static func probeLines(_ results: [ProbeResult]) -> [String] {
        [probesHeading] + results.map(\.line)
    }

    /// The writes, the reads that return what was said or made, and the page
    /// hooks seen only in some states: each with the feature that depends on
    /// it, and why it can't be tried from here.
    static func whenUsedLines(_ items: [CompatDependency] = CompatInventory.whenUsed) -> [String] {
        [whenUsedHeading] + items.map(whenUsedLine)
    }

    static func whenUsedLine(_ item: CompatDependency) -> String {
        guard case .whenUsed(let why) = item.check else { return "• \(item.token): \(item.feature.title)" }
        return "• \(item.token): \(item.feature.title) (\(why))"
    }
}
