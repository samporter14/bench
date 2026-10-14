// RemotePermissionsDemo.swift — `--demo remote`'s made-up permission requests
// and live text for Phase 4 (DESIGN.md, Phase 4). Every name, host, line of
// code and sentence here is invented. Nothing is read from Claude Science or
// written anywhere: an answer is remembered in memory until the demo quits,
// so the request leaves the screen as it would on a real session.
import Foundation

/// The made-up sessions that wait on a permission, and what the working
/// ones write as they go.
@MainActor
final class DemoLive {
    /// The sessions' ids end in these (`00000000-0000-4000-8000-0000000000<id>`).
    enum Suffix {
        static let exec = "d8"
        static let network = "d9"
        static let helper = "da"
        /// The helper (sub-agent) of the "Citation check" session.
        static let child = "db"
        /// "Literature sweep": text growing.
        static let writing = "d4"
        /// "Plate layout": running code.
        static let running = "d5"
    }

    static func id(_ suffix: String) -> String { "00000000-0000-4000-8000-0000000000\(suffix)" }

    static let passage = """
    Two reviews compare dyes for thermal shift assays. The first finds that the SYPRO-type dyes give the cleanest \
    melting curves for most soluble proteins, but they bind exposed hydrophobic patches and so can shift a \
    transition that is already close to the buffer's own. The second compares them against label-free readouts \
    and agrees on the main point: a dye is a choice to report, not a default.
    """

    /// Reads of the running-code stretch between two texts.
    static let gap = 5
    /// Characters more on each read.
    static let stride = 52

    private var counts: [String: Int] = [:]
    private(set) var answered: Set<String> = []

    // MARK: Permissions

    /// The made-up read of a session that waits on a permission.
    static func read(title: String, id: String, now: Date) -> SessionProjection? {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        switch title {
        case "Peak calling script":
            return SessionProjection(
                status: "processing", agentName: "demo", projectID: "demo",
                statusLine: "Waiting for your approval to run a cell",
                turns: [SessionProjection.Turn(role: .you, at: ago(3), text: "Total the counts for the three made-up samples and list the ten highest regions."),
                        SessionProjection.Turn(role: .claude, at: ago(2), text: "I'll total the counts per region first, then sort them.")],
                permission: PermissionRequest(
                    requestID: "demo-request-exec", toolID: "demo-tool-exec", mode: "live", kind: "local_exec", frame: id,
                    tool: "python",
                    code: """
                    import pandas as pd

                    counts = pd.read_csv("sample_counts.csv", index_col=0)
                    counts["total"] = counts.sum(axis=1)
                    print(counts.sort_values("total", ascending=False).head(10))
                    """))
        case "Reference genome download":
            return SessionProjection(
                status: "awaiting_user_response", agentName: "demo", projectID: "demo",
                statusLine: "Waiting to reach a website",
                turns: [SessionProjection.Turn(role: .you, at: ago(6), text: "Fetch the made-up reference sequence for the plasmid map."),
                        SessionProjection.Turn(role: .claude, at: ago(5), text: "The sequence is on a host I haven't used yet.")],
                permission: PermissionRequest(
                    requestID: "demo-request-net", toolID: "demo-tool-net", mode: "parked", kind: "network", frame: id,
                    target: "genomes.example.org"))
        case "Citation check":
            return SessionProjection(
                status: "processing", agentName: "demo", projectID: "demo",
                statusLine: "A helper is waiting for your approval",
                turns: [SessionProjection.Turn(role: .you, at: ago(4), text: "Check that the five cited papers say what the summary says they do."),
                        SessionProjection.Turn(role: .claude, at: ago(3), text: "I've handed the lookups to a helper.")],
                permission: PermissionRequest(
                    requestID: "demo-request-mcp", toolID: "demo-tool-mcp", mode: "parked", kind: "mcp_tool",
                    frame: Self.id(Suffix.child), chain: [Self.id(Suffix.child), id],
                    tool: "search_papers", server: "Paper search", source: "directory", readOnly: true))
        default:
            return nil
        }
    }

    /// What the demo's sessions show once an answer went: the request is gone.
    func settled(_ read: SessionProjection) -> SessionProjection {
        guard let request = read.permission, answered.contains(request.id) else { return read }
        return read.with(permission: nil)
    }

    /// The daemon's `accepted`, as the demo's write answers it.
    func answer(_ requestID: String) -> RemoteWriteResult {
        answered.insert(requestID)
        return RemoteWriteResult(status: 200, bodyStatus: "accepted", remaining: 0)
    }

    // MARK: Live text

    /// 52 more characters on each read of "Literature sweep", then five reads
    /// (a few seconds' worth) of a model call running code, then it starts
    /// over: what a real call's buffer does between messages. "Plate layout"
    /// only ever runs code.
    func read(_ id: String, activity: Bool, text: Bool) -> LiveRead? {
        if id == Self.id(Suffix.running) {
            return LiveRead(working: true, text: nil, activity: LiveScript.Activity.executing)
        }
        guard id == Self.id(Suffix.writing) else { return nil }
        let step = counts[id, default: 0]
        counts[id] = step + 1
        let characters = Array(Self.passage)
        let reads = (characters.count + Self.stride - 1) / Self.stride
        let phase = step % (reads + Self.gap)
        guard phase < reads else {
            return LiveRead(working: true, text: nil, activity: LiveScript.Activity.executing)
        }
        let shown = String(characters.prefix((phase + 1) * Self.stride))
        return LiveRead(working: true, text: text ? shown : nil, activity: LiveScript.Activity.working)
    }
}

extension SessionProjection {
    /// The same read with another `permission`.
    func with(permission: PermissionRequest?) -> SessionProjection {
        SessionProjection(status: status, agentName: agentName, projectID: projectID, statusLine: statusLine,
                          reply: reply, replyAt: replyAt, toYou: toYou, queued: queued, asks: asks,
                          planVersion: planFrame.versionID, planArtifact: planFrame.artifactID,
                          approval: planFrame.approval, turns: turns, permission: permission)
    }
}
