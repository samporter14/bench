// PlanApproval.swift — approving a plan from its needs-input card (DESIGN.md,
// Approving a plan from its card). Bench's only write to Claude Science.
//
// The checks are pure (`PlanCheck`, on the small structs below) and tested on
// made-up JSON. `PlanApprover` is the thin part that reads and posts through
// the page. What it reads of a plan (its summary, how many steps, their
// titles, the confidence word) lives in memory only, for the card, and is
// never logged or saved.
import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "local.sam.bench", category: "plan")

// MARK: What is read

/// Reads single values out of parsed JSON, leniently: a value of the wrong
/// type is no value. Nothing here keeps what it was given.
private enum JSONPick {
    static func parse(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any]
    }

    /// An object, or a string holding one (the database keeps these columns
    /// as text, so an API could hand them over that way too).
    static func object(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        if let text = value as? String { return parse(Data(text.utf8)) }
        return nil
    }

    static func isAbsent(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    /// A JSON string, and nothing else (a number is not one).
    static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNumber) else { return nil }
        return value as? String
    }

    /// A JSON `true` or `false`, and nothing else (a 1 or a 0 is not one).
    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// Context first, then output, the way Claude Science's own plan preview
    /// picks: the output's value only when the context has none at all. A
    /// context value of the wrong type is not passed over for the output's.
    static func string(context: Any?, output: Any?) -> String? {
        isAbsent(context) ? string(output) : string(context)
    }
}

/// The few fields of a session's root frame that say whether its plan waits
/// (`GET /api/frames/<id>?shallow=true`). Nothing else of the frame is kept.
struct PlanFrame: Equatable, Sendable {
    enum Approval: Equatable, Sendable {
        /// Absent, null or `false` wherever it is given.
        case no
        /// `true` somewhere.
        case yes
        /// Given as something that is neither: not safe to call either way.
        case unclear
    }

    /// The frame's own status: `awaiting_plan_approval` while its plan waits.
    let status: String
    /// `context_data._plan_version_id`, else `output_data.plan_version_id`.
    let versionID: String?
    /// `context_data._plan_artifact_id`, else `output_data.plan_artifact_id`.
    let artifactID: String?
    /// `context_data._plan_approved` and `output_data.plan_approved`.
    let approval: Approval

    init(status: String, versionID: String?, artifactID: String?, approval: Approval) {
        self.status = status
        self.versionID = versionID
        self.artifactID = artifactID
        self.approval = approval
    }

    /// Nil unless the body is a JSON object with a string `status`.
    init?(json data: Data) {
        guard let root = JSONPick.parse(data), let status = JSONPick.string(root["status"]) else { return nil }
        let context = JSONPick.object(root["context_data"])
        let output = JSONPick.object(root["output_data"])
        self.status = status
        versionID = JSONPick.string(context: context?["_plan_version_id"], output: output?["plan_version_id"])
        artifactID = JSONPick.string(context: context?["_plan_artifact_id"], output: output?["plan_artifact_id"])
        let flags = [context?["_plan_approved"], output?["plan_approved"]].map { value -> Approval in
            if JSONPick.isAbsent(value) { return .no }
            guard let flag = JSONPick.bool(value) else { return .unclear }
            return flag ? .yes : .no
        }
        approval = flags.contains(.yes) ? .yes : flags.contains(.unclear) ? .unclear : .no
    }
}

/// What the card shows of a plan (`GET /api/artifacts/versions/<id>`): its
/// `task_summary`, how many steps it has, the titles of those steps and its
/// confidence word. A step's description is never read.
struct PlanDocument: Equatable, Sendable {
    /// The longest step title kept, in characters. The card cuts a title at
    /// its line's end long before this; the limit only keeps an odd plan from
    /// holding a page of text in memory.
    static let titleLimit = 200

    /// `task_summary`, when it is a string with something in it.
    let summary: String?
    /// Every `phases[].delegations[].steps[]`, or an older plan's top-level
    /// `steps[]`.
    let steps: Int?
    /// The `title` of each of those steps that has a string with something in
    /// it, in plan order, each on one line. A step without one is left out of
    /// this list but still counts in `steps`, so this can be shorter.
    let stepTitles: [String]
    /// `feasibility.confidence`, when it is a short string ("high").
    let confidence: String?

    init(summary: String?, steps: Int?, stepTitles: [String] = [], confidence: String?) {
        self.summary = summary
        self.steps = steps
        self.stepTitles = stepTitles
        self.confidence = confidence
    }

    /// Nil unless the body is a JSON object.
    init?(json data: Data) {
        guard let root = JSONPick.parse(data) else { return nil }
        let summary = JSONPick.string(root["task_summary"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary?.isEmpty == false ? summary : nil
        let entries = Self.stepEntries(in: root)
        steps = entries?.count
        stepTitles = (entries ?? []).compactMap(Self.stepTitle)
        let feasibility = root["feasibility"] as? [String: Any]
        confidence = Self.confidenceWord(JSONPick.string(feasibility?["confidence"]))
    }

    /// The plan's steps in order, whatever each one holds: the phases'
    /// delegations' steps when there are any, else an older plan's top-level
    /// steps. The count and the titles both come from this one list, so they
    /// are always about the same shape. Nil when the plan has neither.
    private static func stepEntries(in root: [String: Any]) -> [Any]? {
        var phased: [Any]?
        if let phases = root["phases"] as? [Any] {
            phased = phases.flatMap { phase -> [Any] in
                let delegations = (phase as? [String: Any])?["delegations"] as? [Any] ?? []
                return delegations.flatMap { ($0 as? [String: Any])?["steps"] as? [Any] ?? [] }
            }
        }
        if let phased, !phased.isEmpty { return phased }
        if let flat = root["steps"] as? [Any] { return flat }
        return phased
    }

    /// A step's `title` as one line, when it is a string with something in
    /// it. A step that isn't an object has none.
    private static func stepTitle(_ step: Any) -> String? {
        guard let text = JSONPick.string((step as? [String: Any])?["title"]) else { return nil }
        // Any run of white space, line breaks included, becomes one space.
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.isEmpty ? nil : String(line.prefix(titleLimit))
    }

    /// "high", from "High" or "high confidence"; nothing from a sentence.
    private static func confidenceWord(_ text: String?) -> String? {
        guard var word = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        if word.hasSuffix("confidence") {
            word = String(word.dropLast("confidence".count)).trimmingCharacters(in: .whitespaces)
        }
        guard !word.isEmpty, word.count <= 20, !word.contains(where: \.isNewline) else { return nil }
        return word
    }
}

/// The step titles a card lists: the first few, and how many are left out.
/// Pure, so the cap is tested. The panel measures its content and grows with
/// it, so a long plan must not be able to grow it off a laptop screen.
struct PlanStepList: Equatable, Sendable {
    /// The most titles a card lists.
    static let limit = 8

    let shown: [String]
    /// How many titles come after the ones shown.
    let more: Int

    init(_ titles: [String], limit: Int = PlanStepList.limit) {
        shown = Array(titles.prefix(max(0, limit)))
        more = titles.count - shown.count
    }

    /// "and 2 more…", when any are left out.
    var moreLine: String? {
        more > 0 ? "and \(more) more…" : nil
    }
}

/// A plan the card may offer to approve: what it shows, and which version it
/// is, to check against just before approving.
struct PlanPreview: Equatable, Sendable {
    /// The tooltip of the steps line, which names the confidence word
    /// "feasibility": the column is too narrow for the longer wording.
    static let feasibilityHelp = "Claude's own estimate of how feasible the plan is"

    let summary: String
    let steps: Int?
    let confidence: String?
    /// The titles of the steps that have one, in plan order; empty when none
    /// do. Held in memory only, for the card's list of steps.
    let stepTitles: [String]
    let versionID: String
    let artifactID: String?

    init(summary: String, steps: Int?, confidence: String?, stepTitles: [String] = [],
         versionID: String, artifactID: String?) {
        self.summary = summary
        self.steps = steps
        self.confidence = confidence
        self.stepTitles = stepTitles
        self.versionID = versionID
        self.artifactID = artifactID
    }

    /// "5 steps · feasibility: high", or as much of it as is known.
    var detail: String? {
        var parts: [String] = []
        if let steps, steps > 0 { parts.append(steps == 1 ? "1 step" : "\(steps) steps") }
        if let confidence { parts.append("feasibility: \(confidence)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What the card lists under "Show steps"; nil for a plan with no step
    /// titles, which has no such control.
    var stepList: PlanStepList? {
        stepTitles.isEmpty ? nil : PlanStepList(stepTitles)
    }
}

/// How an approval from the card ended.
enum PlanOutcome: Equatable, Sendable {
    /// Approved (or already approved): the card says so, then goes.
    case approved
    /// Claude is still working on the frame; nothing was approved.
    case busy
    /// The plan isn't the one shown any more, or no plan waits.
    case changed
    /// Anything unexpected. The card keeps Open.
    case failed

    /// What the card says instead of the steps line; nil when approved.
    var message: String? {
        switch self {
        case .approved: nil
        case .busy: "Claude is still busy with it"
        case .changed: "The plan changed: open it to check"
        case .failed: "Couldn't approve here"
        }
    }
}

// MARK: The checks

/// Every decision about approving, pure.
enum PlanCheck {
    static let awaitingStatus = "awaiting_plan_approval"

    /// A full frame id: 36 lowercase hex digits and dashes. The daemon matches
    /// a shorter id by prefix, so only full ones are ever sent.
    static func isFrameID(_ id: String) -> Bool {
        id.utf8.count == 36 && id.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) || $0 == 0x2D }
    }

    /// A version id that is safe in a path: letters, digits, `-` and `_`.
    static func isVersionID(_ id: String) -> Bool {
        (1...128).contains(id.utf8.count) && id.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2D || $0 == 0x5F
        }
    }

    /// The root frame's shallow read.
    static func framePath(_ frameID: String) -> String? {
        isFrameID(frameID) ? "/frames/\(frameID)?shallow=true" : nil
    }

    /// The plan file of one version.
    static func versionPath(_ versionID: String) -> String? {
        isVersionID(versionID) ? "/artifacts/versions/\(versionID)" : nil
    }

    /// The one write Bench makes.
    static func approvePath(_ frameID: String) -> String? {
        isFrameID(frameID) ? "/frames/\(frameID)/approve-plan" : nil
    }

    /// `^/frames/[0-9a-f-]{36}/approve-plan$`, and nothing else: the check
    /// `WebContainer.apiPOST` itself makes, where the write is sent.
    static func isApprovePath(_ path: String) -> Bool {
        WebContainer.isWritablePath(path)
    }

    /// The plan version to read, when the root frame itself waits for its
    /// plan: its own status is `awaiting_plan_approval` (a sub-agent waiting
    /// leaves the root `processing`), it isn't approved, and the version id
    /// is a string fit for a path.
    static func versionToRead(_ frame: PlanFrame?) -> String? {
        guard let frame, frame.status == awaitingStatus, frame.approval == .no,
              let versionID = frame.versionID, isVersionID(versionID) else { return nil }
        return versionID
    }

    /// What the card shows, when Approve may be offered: all of the frame's
    /// checks hold, and the plan file has a string `task_summary`.
    static func preview(frame: PlanFrame?, plan: PlanDocument?) -> PlanPreview? {
        guard let versionID = versionToRead(frame), let frame, let plan, let summary = plan.summary else { return nil }
        return PlanPreview(summary: summary, steps: plan.steps, confidence: plan.confidence,
                           stepTitles: plan.stepTitles, versionID: versionID, artifactID: frame.artifactID)
    }

    /// Read again just before approving: still waiting, still not approved,
    /// and the same version (and artifact, when both are known) as shown.
    static func isSamePlan(_ frame: PlanFrame?, as shown: PlanPreview) -> Bool {
        guard let versionID = versionToRead(frame), versionID == shown.versionID, let frame else { return false }
        if let artifactID = frame.artifactID, let shownArtifact = shown.artifactID, artifactID != shownArtifact {
            return false
        }
        return true
    }

    /// What the daemon's answer to the approve POST means.
    static func outcome(_ result: APIWriteResult) -> PlanOutcome {
        switch result.status {
        case 200:
            // `{"root_frame_id", "frame_id", "status": "accepted"}`.
            return result.isJSON && result.accepted ? .approved : .failed
        case 400:
            // Claude Science's own UI counts this one as success.
            if result.code == "plan_already_approved" { return .approved }
            if result.code == "plan_frame_processing" { return .busy }
            if result.noPlanAwaiting { return .changed }
            return .failed
        default:
            // 401 (signed out), 403 (CSRF, after the one retry), 404 or 405
            // (the route is gone), anything else.
            return .failed
        }
    }
}

// MARK: The card's state

/// What a plan's card shows, by session.
enum PlanCardState: Equatable, Sendable {
    /// Reading the frame and the plan: "Loading the plan…", no Approve yet.
    case loading
    /// Approve may be offered.
    case ready(PlanPreview)
    /// A check failed or a read did: the card is as before, Open and Later.
    case unavailable
    /// Pressed: checking the plan again, then posting. No second press.
    case approving(PlanPreview)
    /// "Approved ✓", for a moment, then the card goes.
    case approved(PlanPreview)
    /// It didn't approve: a short sentence, and Open.
    case problem(String, PlanPreview)
}

/// Reads the plan for the needs-input card on top, and approves it when asked.
/// One read per card: the state is dropped when the card goes, or stops being
/// about a plan, and read afresh if it comes back.
@MainActor
final class PlanApprover: ObservableObject {
    static let shared = PlanApprover(model: .shared, dependencies: .live())

    /// Everything that reaches outside, so tests can stand in for it.
    struct Dependencies {
        /// "Show plans on the card, with Approve" and "Show a card" are on,
        /// and no demo runs.
        var isEnabled: @MainActor () -> Bool
        /// The page is up, so its API can be called.
        var isReady: @MainActor () -> Bool
        /// `WebContainer.apiGET`.
        var get: @MainActor (String) async throws -> Data
        /// `WebContainer.apiPOST`.
        var post: @MainActor (String) async throws -> APIWriteResult
        /// How long "Approved ✓" stays before the card goes.
        var approvedPause: Duration

        static func live() -> Dependencies {
            Dependencies(
                isEnabled: {
                    let defaults = UserDefaults.standard
                    return Demo.mode == nil && defaults.bool(forKey: SettingsKey.showPlansOnCard)
                        && defaults.bool(forKey: SettingsKey.showCards)
                },
                isReady: { WebContainer.shared.status == .ready },
                get: { path in
                    guard Demo.mode == nil else { throw WebAPIError.notAllowed }
                    return try await WebContainer.shared.apiGET(path)
                },
                post: { path in
                    guard Demo.mode == nil else { throw WebAPIError.notAllowed }
                    return try await WebContainer.shared.apiPOST(path)
                },
                approvedPause: .milliseconds(1500))
        }
    }

    /// By session id: only sessions whose plan card is in the queue.
    @Published private(set) var states: [String: PlanCardState] = [:]
    /// By session id: the cards whose list of steps is open. Closed unless
    /// opened, and dropped with the card's plan, so a card that comes back
    /// starts closed.
    @Published private(set) var stepsOpen: Set<String> = []

    private let model: LabModel
    private let dependencies: Dependencies
    private var tasks: [String: Task<Void, Never>] = [:]
    /// `--demo plan`'s made-up session: approving it posts nothing.
    private var demoSessions: Set<String> = []
    private var subscriptions = Set<AnyCancellable>()

    init(model: LabModel, dependencies: Dependencies) {
        self.model = model
        self.dependencies = dependencies
    }

    func state(for sessionID: String) -> PlanCardState? {
        states[sessionID]
    }

    func isShowingSteps(_ sessionID: String) -> Bool {
        stepsOpen.contains(sessionID)
    }

    /// Opens or closes one card's list of steps. Nothing for a card with no
    /// plan state, so a card that has gone can't leave an open flag behind.
    func toggleSteps(_ sessionID: String) {
        guard states[sessionID] != nil else { return }
        if !stepsOpen.insert(sessionID).inserted { stepsOpen.remove(sessionID) }
    }

    /// Follows the cards, the settings and the page. Never in a demo.
    func start() {
        guard subscriptions.isEmpty, Demo.mode == nil else { return }
        let center = NotificationCenter.default
        Publishers.Merge3(
            model.$cards.map { _ in () },
            center.publisher(for: UserDefaults.didChangeNotification).map { _ in () },
            WebContainer.shared.$status.map { _ in () })
            // @Published publishes before the value changes: look after it has.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sync() }
            .store(in: &subscriptions)
    }

    /// Drops what no longer has a plan card to go with, and starts reading
    /// the plan of the card on top if it has none yet. Internal for tests.
    func sync() {
        let enabled = dependencies.isEnabled()
        var planCards: Set<String> = []
        for case .needsInput(let session) in model.cards where session.waitingReason == .plan {
            planCards.insert(session.id)
        }
        for id in Array(states.keys) {
            let keep: Bool
            if !planCards.contains(id) {
                keep = false
            } else if demoSessions.contains(id) {
                keep = true
            } else if !enabled {
                keep = false
            } else {
                switch states[id] {
                // A new request for the session lets the card go from under
                // an approval: it asks something else now.
                case .approving?, .approved?: keep = model.holdsPlanCard(id)
                default: keep = true
                }
            }
            if !keep { discard(id) }
        }
        guard enabled, case .needsInput(let session)? = model.cards.first, session.waitingReason == .plan,
              states[session.id] == nil, dependencies.isReady() else { return }
        load(session.id)
    }

    /// Approve, once: only from `ready`, which it leaves at once, so a second
    /// press finds nothing to do and nothing is posted twice.
    func approve(_ sessionID: String) {
        guard case .ready(let preview) = states[sessionID] else { return }
        let id = sessionID
        states[id] = .approving(preview)
        if demoSessions.contains(id) {
            // Made up: the Approved state, with nothing sent anywhere.
            tasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self, self.states[id] == .approving(preview) else { return }
                self.states[id] = .approved(preview)
            }
            return
        }
        // The card stays up through the approval, even once the session runs.
        model.holdPlanCard(id)
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.send(id, preview)
            self.finish(id, preview, outcome)
        }
    }

    /// `--demo plan`: a made-up plan, ready, for a made-up session.
    func showDemo(sessionID: String, preview: PlanPreview) {
        demoSessions.insert(sessionID)
        states[sessionID] = .ready(preview)
    }

    /// Waits until the reads and approvals under way, and any they start,
    /// are done. For tests.
    func settled() async {
        var done: Set<Task<Void, Never>> = []
        while let task = tasks.values.first(where: { !done.contains($0) }) {
            await task.value
            done.insert(task)
        }
    }

    // MARK: Reading

    private func load(_ id: String) {
        states[id] = .loading
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            let preview = await self.readPlan(id)
            guard !Task.isCancelled, self.states[id] == .loading else { return }
            self.states[id] = preview.map(PlanCardState.ready) ?? .unavailable
        }
    }

    /// The root frame, then its plan. Nil at the first thing that isn't as
    /// expected: a read that fails, a shape that doesn't match, a sub-agent
    /// waiting rather than the root.
    private func readPlan(_ id: String) async -> PlanPreview? {
        guard let framePath = PlanCheck.framePath(id),
              let frameData = try? await dependencies.get(framePath),
              let frame = PlanFrame(json: frameData),
              let versionID = PlanCheck.versionToRead(frame),
              let versionPath = PlanCheck.versionPath(versionID),
              !Task.isCancelled,
              let planData = try? await dependencies.get(versionPath) else { return nil }
        return PlanCheck.preview(frame: frame, plan: PlanDocument(json: planData))
    }

    // MARK: Approving

    /// Reads the root frame again, and posts only if it still waits for the
    /// very plan the card shows.
    private func send(_ id: String, _ shown: PlanPreview) async -> PlanOutcome {
        guard let framePath = PlanCheck.framePath(id), let approvePath = PlanCheck.approvePath(id),
              let data = try? await dependencies.get(framePath) else { return .failed }
        guard PlanCheck.isSamePlan(PlanFrame(json: data), as: shown) else { return .changed }
        // The card went, or a new request took its place, during the check:
        // nothing is sent.
        guard !Task.isCancelled, states[id] == .approving(shown) else { return .failed }
        guard let result = try? await dependencies.post(approvePath) else { return .failed }
        return PlanCheck.outcome(result)
    }

    private func finish(_ id: String, _ shown: PlanPreview, _ outcome: PlanOutcome) {
        // Nothing to show on a card that has gone meanwhile.
        guard states[id] == .approving(shown) else { return }
        log.notice("Approve from the card: \(String(describing: outcome), privacy: .public)")
        guard let message = outcome.message else {
            states[id] = .approved(shown)
            let pause = dependencies.approvedPause
            tasks[id] = Task { [weak self] in
                try? await Task.sleep(for: pause)
                guard !Task.isCancelled, let self, self.states[id] == .approved(shown) else { return }
                // As Open would, without opening the session.
                self.model.releasePlanCard(id, approved: true)
                self.states[id] = nil
                self.stepsOpen.remove(id)
                self.tasks[id] = nil
            }
            return
        }
        states[id] = .problem(message, shown)
        model.releasePlanCard(id, approved: false)
    }

    private func discard(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        let state = states.removeValue(forKey: id)
        stepsOpen.remove(id)
        demoSessions.remove(id)
        switch state {
        case .approving?, .approved?: model.releasePlanCard(id, approved: false)
        default: break
        }
    }
}
