// RemotePermissionsTests.swift — the phone's permission requests (Phase 4) on
// made-up frames. The projection is the very JavaScript the page runs, run
// here in JavaScriptCore; Swift's own checks and decisions run on what it
// returns. Every frame, host and line of code is invented; the fields Bench
// must never pass on hold "SECRET" so a leak shows.
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root
private let helperA = "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6"
private let helperB = "2d9e4a6b-3c4d-4e5f-8a1b-c2d3e4f5a6b7"
private let deeper = "3eaf5b7c-4d5e-4f60-9b2c-d3e4f5a6b7c8"

// MARK: Made-up frames

private func json(_ value: Any) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])) ?? Data(),
           as: UTF8.self)
}

/// One pending request, with the fields every request carries.
private func request(_ kind: String, _ fields: [String: Any] = [:], at: String = "2026-10-12T19:30:00Z",
                     mode: String = "live", id: String = "req-1", tool: String = "tool-1") -> [String: Any] {
    var made: [String: Any] = ["kind": kind, "requestId": id, "tool_id": tool, "frameId": root, "rootFrameId": root,
                               "projectId": "proj-made-up", "createdAt": at, "mode": mode]
    for (key, value) in fields { made[key] = value }
    return made
}

/// The root's shallow frame holding `requests`.
private func rootFrame(status: String = "processing", _ requests: [[String: Any]]) -> String {
    ReaderFixture.frame(status: status, context: "null", output: json(["pending_input_requests": requests, "thinking": "SECRET-THINKING"]))
}

/// A frame in `trace-shallow`'s tree.
private func node(_ id: String, parent: String = root, status: String = "awaiting_user_response",
                  requests: [[String: Any]] = [], children: [[String: Any]] = [], outputAsText: Bool = false) -> [String: Any] {
    let output: Any = ["pending_input_requests": requests, "response": "SECRET-RESPONSE"] as [String: Any]
    return ["id": id, "parent_frame_id": parent, "status": status, "delegate_name": "SECRET-DELEGATE",
            "agent_name": "made-up-helper", "context_data": ["_note": "SECRET-CONTEXT"],
            "output_data": outputAsText ? json(output) : output, "children": children]
}

private func trace(_ children: [[String: Any]] = [], id: String = root) -> String {
    json(["id": id, "parent_frame_id": NSNull(), "status": "processing", "children": children])
}

/// `benchProjectPermission` on a root frame and its trace, then Swift's checks.
private func head(_ frame: String, _ trace: String?, rootID: String = root) -> (json: String, request: PermissionRequest?) {
    let script = PageScript(PermissionScript.reading)
    let out = script.callJSON("benchProjectPermission", [frame, trace, json(rootID)]) ?? "<exception>"
    #expect(script.exception == nil)
    guard out != "null", let object = try? JSONSerialization.jsonObject(with: Data(out.utf8)) else { return (out, nil) }
    return (out, PermissionRequest(object: object))
}

/// One request alone on the root, as the root's own.
private func alone(_ made: [String: Any]) -> PermissionRequest? {
    head(rootFrame([made]), trace()).request
}

private func described(_ made: [String: Any], actionsOn: Bool = true) -> RemoteAPI.Permission? {
    alone(made).map { RemotePermission.describe($0, actionsOn: actionsOn) }
}

// MARK: Every kind

struct PermissionKindTests {
    private struct Case {
        let kind: String
        let fields: [String: Any]
        let title: String
        let allow: Bool
        let deny: Bool
        /// The code is passed on whole (a code cell, with its code readable).
        let code: Bool

        init(_ kind: String, _ fields: [String: Any] = [:], _ title: String, allow: Bool = false, deny: Bool, code: Bool? = nil) {
            self.kind = kind
            self.fields = fields
            self.title = title
            self.allow = allow
            self.deny = deny
            self.code = code ?? (allow && kind == "local_exec")
        }
    }

    private static func cases() -> [Case] {
        [
        // Allow once: code in a language Bench lists, in no shared environment.
        Case("local_exec", ["tool": "python", "code": "print(1)"], "Run Python code", allow: true, deny: true),
        Case("local_exec", ["tool": "r", "code": "print(1)", "shared_env": false], "Run R code", allow: true, deny: true),
        Case("local_exec", ["tool": "bash", "code": "ls"], "Run Bash code", allow: true, deny: true),
        Case("local_exec", ["tool": "powershell", "code": "Get-Date", "shared_env": NSNull()], "Run PowerShell code", allow: true, deny: true),
        Case("local_exec", ["tool": "python", "code": "print(1)", "shared_env": true], "Run Python code", deny: true, code: true),
        Case("local_exec", ["tool": "python", "code": "print(1)", "shared_env": "yes"], "Run Python code", deny: true, code: true),
        Case("local_exec", ["tool": "julia", "code": "println(1)"], "Run julia code", deny: true, code: true),
        Case("local_exec", ["tool": "python", "code": String(repeating: "x", count: 4001)], "Run Python code", deny: true),
        Case("local_exec", ["tool": "python", "code": "a\u{202E}b"], "Run Python code", deny: true),
        Case("local_exec", ["tool": "python", "code": "a\u{0}b"], "Run Python code", deny: true),
        Case("local_exec", ["tool": "python", "code": "   "], "Run Python code", deny: true),
        // An MCP tool that says it only reads, from a source Bench lists.
        Case("mcp_tool", ["server_id": "s1", "server_name": "Paper search", "tool_name": "search_papers",
                          "server_source": "directory", "read_only": true], "Use search_papers from Paper search", allow: true, deny: true),
        Case("mcp_tool", ["server_id": "s1", "server_name": "Paper search", "tool_name": "search_papers",
                          "server_source": "bundled", "read_only": true], "Use search_papers from Paper search", allow: true, deny: true),
        Case("mcp_tool", ["server_id": "s1", "server_name": "Paper search", "tool_name": "search_papers",
                          "server_source": "antmcp", "read_only": true], "Use search_papers from Paper search", allow: true, deny: true),
        Case("mcp_tool", ["server_id": "s1", "server_name": "Paper search", "tool_name": "search_papers",
                          "server_source": "directory", "read_only": false], "Use search_papers from Paper search", deny: true),
        Case("mcp_tool", ["server_id": "s1", "server_name": "Paper search", "tool_name": "search_papers",
                          "server_source": "directory", "read_only": "true"], "Use search_papers from Paper search", deny: true),
        Case("mcp_tool", ["server_id": "s1", "server_name": "Paper search", "tool_name": "search_papers",
                          "server_source": "directory"], "Use search_papers from Paper search", deny: true),
        Case("mcp_tool", ["server_id": "s1", "server_name": "Paper search", "tool_name": "search_papers",
                          "server_source": "custom", "read_only": true], "Use search_papers from Paper search", deny: true),
        // Deny, or Open on Mac.
        Case("network", ["target": "genomes.example.org"], "Wants to reach genomes.example.org", deny: true),
        Case("host", ["target": "/Users/made-up/data", "requested_mode": "ro"], "Wants to read /Users/made-up/data", deny: true),
        Case("host", ["target": "/Users/made-up/data", "requested_mode": "rw"], "Wants to read and change /Users/made-up/data", deny: true),
        Case("host", ["target": "/Users/made-up/data"], "Wants to use /Users/made-up/data", deny: true),
        Case("host_delete", ["paths": ["/Users/made-up/a.csv", "/Users/made-up/b.csv"], "covering_roots": ["/Users/made-up"]],
             "Wants to delete 2 files", deny: true),
        Case("host_delete", ["paths": ["/Users/made-up/a.csv"], "covering_roots": ["/Users/made-up"]],
             "Wants to delete /Users/made-up/a.csv", deny: true),
        Case("artifact_delete", ["items": [["id": "a"], ["id": "b"], ["id": "c"]], "total_bytes": 12], "Wants to delete 3 project files", deny: true),
        Case("artifact_delete", ["items": [["id": "a"]]], "Wants to delete a project file", deny: true),
        Case("remote_exec", ["provider": "made-up-cluster"], "Wants to run a command on made-up-cluster", deny: true),
        Case("remote_read", ["provider": "made-up-cluster", "remote_path": "/data/x.csv"],
             "Wants to read /data/x.csv on made-up-cluster", deny: true),
        Case("byoc_submit", ["provider": "made-up-cloud"], "Wants to start a paid job on made-up-cloud", deny: true),
        Case("byoc_kernel", ["provider": "made-up-cloud"], "Wants to start a paid session on made-up-cloud", deny: true),
        Case("infer_submit", ["provider": "made-up-cloud"], "Wants to run a paid model on made-up-cloud", deny: true),
        Case("customize_mutation", ["label": "Project instructions"], "Wants to change Project instructions", deny: true),
        Case("managed_endpoint_register", ["name": "made-up-endpoint"], "Wants to add the endpoint made-up-endpoint", deny: true),
        Case("credential_access", ["name": "made-up-key"], "Wants to use the saved credential made-up-key", deny: true),
        // Open on Mac only.
        Case("skill_license", ["skill_name": "made-up-skill"], "Wants a license accepted for made-up-skill", deny: false),
        Case("contact_email", [:], "Wants your email address", deny: false),
        Case("credential_request", ["label": "Lab login"], "Wants a password or key (Lab login)", deny: false),
        Case("ssh_password", ["host": "made-up-host"], "Wants an SSH password for made-up-host", deny: false),
        Case("usage_checkpoint", [:], "Reached a usage checkpoint", deny: false),
        Case("set_goal", [:], "Wants to set a goal", deny: false),
        Case("grant_scan", [:], "Wants access to more files", deny: false),
        Case("provider_discovery", [:], "Wants to choose a provider", deny: false),
        // A kind Bench doesn't know: nothing but Open on Mac.
        Case("teleport", ["target": "elsewhere"], "Wants your permission", deny: false),
        // The daemon's own shape for the kind doesn't hold: Open on Mac.
        Case("network", [:], "Wants your permission", deny: false),
        Case("mcp_tool", ["server_name": "Paper search", "tool_name": "x", "server_source": "directory", "read_only": true],
             "Wants your permission", deny: false),
        Case("host_delete", ["paths": ["/x"]], "Wants your permission", deny: false),
        Case("host_delete", ["paths": [] as [String], "covering_roots": ["/"]], "Wants your permission", deny: false),
        Case("local_exec", ["tool": "python"], "Wants your permission", deny: false),
        ]
    }

    @Test(arguments: 0..<48)
    func eachKindHasItsOwnRules(_ index: Int) throws {
        let cases = Self.cases()
        #expect(cases.count == 48)
        guard index < cases.count else { return }
        let item = cases[index]
        let permission = try #require(described(request(item.kind, item.fields)), "\(item.kind)")
        #expect(permission.title == item.title, "\(item.kind): \(permission.title)")
        #expect(permission.canAllow == item.allow, "\(item.kind) allow")
        #expect(permission.canDeny == item.deny, "\(item.kind) deny")
        #expect(permission.helper == false)
        #expect(permission.id == "req-1")
        #expect(permission.kind == item.kind)
        // `why` says why not, and only then.
        #expect((permission.why == nil) == item.allow, "\(item.kind) why: \(permission.why ?? "nil")")
        // Code only for a code cell whose code is readable, shown whole.
        #expect((permission.code != nil) == item.code, "\(item.kind) code")
    }

    @Test func everyKindTheSpecNamesIsInTheTableAndInTheScript() {
        // The script's list and Swift's enum are the same set: a request of each
        // kind, with only the common fields and the ones its shape needs, has
        // its shape hold exactly when Swift knows the kind.
        for kind in PermissionKind.allCases {
            let fields: [String: Any]
            switch kind {
            case .network: fields = ["target": "h"]
            case .host: fields = ["target": "/p"]
            case .hostDelete: fields = ["paths": ["/p"], "covering_roots": ["/"]]
            case .artifactDelete: fields = ["items": [1]]
            case .mcpTool: fields = ["server_id": "s", "server_name": "n", "tool_name": "t", "server_source": "directory"]
            case .localExec: fields = ["tool": "python", "code": "1"]
            default: fields = [:]
            }
            #expect(alone(request(kind.rawValue, fields))?.shape == true, "\(kind.rawValue)")
        }
        #expect(PermissionKind.allCases.count == 22)
        #expect(alone(request("teleport"))?.shape == false)
        #expect(alone(request("teleport"))?.known == nil)
    }

    @Test func denyIsOnlyForKindsWhoseNoIsAPlainNo() {
        let open: Set<PermissionKind> = [.skillLicense, .contactEmail, .credentialRequest, .sshPassword, .usageCheckpoint,
                                         .setGoal, .grantScan, .providerDiscovery]
        for kind in PermissionKind.allCases { #expect(kind.canBeDenied == !open.contains(kind), "\(kind.rawValue)") }
    }

    @Test func actionsOffOffersNothingAndSaysWhy() throws {
        let permission = try #require(described(request("local_exec", ["tool": "python", "code": "print(1)"]), actionsOn: false))
        #expect(!permission.canAllow && !permission.canDeny)
        #expect(permission.why == "Actions are off in Bench's Settings")
        // The words stay: the phone still says what is waiting.
        #expect(permission.title == "Run Python code")
    }

    @Test func theWhyForALastingAllowIsTheSpecsSentence() throws {
        let permission = try #require(described(request("network", ["target": "genomes.example.org"])))
        #expect(permission.why == "Allowing this from your phone would give lasting access. Open it on your Mac.")
    }

    @Test func aRequestWithoutBothIDsOrAKnownModeCanNeitherBeAllowedNorDenied() throws {
        for fields: [String: Any] in [["requestId": NSNull()], ["tool_id": NSNull()], ["mode": "somehow"], ["createdAt": "yesterday"]] {
            let made = request("network", fields.merging(["target": "genomes.example.org"]) { $1 })
            let permission = try #require(described(made), "\(fields)")
            #expect(!permission.canAllow && !permission.canDeny, "\(fields)")
        }
    }

    @Test func theCodeIsShownWholeAndNeverCut() throws {
        let code = "import pandas as pd\n\n\tcounts = pd.read_csv('c.csv')\r\nprint(counts)  \n"
        let permission = try #require(described(request("local_exec", ["tool": "python", "code": code])))
        #expect(permission.code == code)
        let exactly = String(repeating: "界", count: 4000)
        #expect(try #require(described(request("local_exec", ["tool": "python", "code": exactly]))).code == exactly)
        #expect(try #require(described(request("local_exec", ["tool": "python", "code": exactly + "界"]))).canAllow == false)
    }

    @Test func aCodeCellsOtherFieldsAreNotPassedOn() throws {
        let made = request("local_exec", ["tool": "python", "code": "print(1)", "environment": "SECRET-ENV", "working_dir": "/SECRET/dir",
                                           "auto_mode_reason": "SECRET-REASON", "scopes": ["SECRET-SCOPE"]])
        let (text, parsed) = head(rootFrame([made]), trace())
        #expect(!text.contains("SECRET"))
        #expect(parsed != nil)
    }
}

// MARK: What never leaves the page

struct PermissionSecretsTests {
    /// Every field a request of this kind may carry that Bench must not read.
    private static let sensitive = ["reason", "warning", "input", "command", "preview", "summary", "credentials", "environment",
                                    "working_dir", "auto_mode_reason", "notice_text", "ack_statement", "prompt", "alias", "text",
                                    "detail", "intent", "display", "endpoint", "url", "credential_name", "grant", "change",
                                    "unfinished", "predicate", "condition", "replaces", "budget", "claim", "boundary", "hold_action",
                                    "existing_mode", "resource_key", "scripts", "gpu", "cpu", "method"]

    @Test(arguments: PermissionKind.allCases.map(\.rawValue))
    func noKindPassesOnAFieldItWasNotMeantToShow(_ kind: String) {
        var fields: [String: Any] = [:]
        for key in Self.sensitive { fields[key] = "SECRET-\(key)" }
        // The fields each kind's shape needs, and the ones it shows: made-up and plain.
        fields["code"] = "SECRET-code"
        fields["tool"] = "SECRET-tool"
        switch kind {
        case "network": fields["target"] = "genomes.example.org"
        case "host": fields["target"] = "/Users/made-up/data"
        case "host_delete": fields["paths"] = ["/Users/made-up/a.csv", "/Users/SECRET-second"]; fields["covering_roots"] = ["/SECRET-root"]
        case "artifact_delete": fields["items"] = [["id": "a", "name": "SECRET-item"]]
        case "mcp_tool":
            fields["server_id"] = "s"; fields["server_name"] = "Paper search"; fields["tool_name"] = "search_papers"
            fields["server_source"] = "directory"; fields["read_only"] = true; fields["input"] = ["query": "SECRET-QUERY"]
        case "local_exec": fields["tool"] = "python"; fields["code"] = "print(1)"
        default: break
        }
        let made = request(kind, fields)
        let behind = request("network", ["target": "SECRET-BEHIND.example"], at: "2026-10-12T19:40:00Z", id: "req-2", tool: "tool-2")
        let (text, parsed) = head(rootFrame([made, behind]), trace([node(helperA, requests: [
            request("host", ["target": "/SECRET/helper"], at: "2026-10-12T19:50:00Z", id: "req-3", tool: "tool-3")])]))
        #expect(!text.contains("SECRET"), "\(kind): \(text)")
        #expect(parsed != nil, "\(kind)")
    }

    @Test func theFramesOtherFieldsStayInThePage() {
        let (text, parsed) = head(rootFrame([request("network", ["target": "genomes.example.org"])]),
                                  trace([node(helperA, status: "completed")]))
        #expect(!text.contains("SECRET"))
        #expect(parsed?.target == "genomes.example.org")
    }

    @Test func aHelpersFieldsStayInThePage() {
        let (text, parsed) = head(rootFrame([]), trace([node(helperA, requests: [request("network", ["target": "genomes.example.org"])])]))
        #expect(!text.contains("SECRET"))
        #expect(parsed?.helper == true)
    }

    @Test func aLineLosesItsControlCharactersAndIsCut() throws {
        let long = String(repeating: "a", count: 300)
        let permission = try #require(alone(request("network", ["target": "  genomes\n\u{202E}.example\u{0}.org  "])))
        #expect(permission.target == "genomes .example.org")
        let cut = try #require(alone(request("network", ["target": long])))
        #expect(cut.target?.unicodeScalars.count == 200)
        #expect(cut.target?.hasSuffix("…") == true)
    }
}

// MARK: The head of the queue

struct PermissionHeadTests {
    private let early = "2026-10-12T19:00:00Z", mid = "2026-10-12T19:10:00Z", late = "2026-10-12T19:20:00Z"

    @Test func theEarliestRequestInTheWholeSessionIsTheHead() {
        let frame = rootFrame([request("network", ["target": "later.example.org"], at: mid, id: "req-b", tool: "tool-b")])
        let tree = trace([node(helperA, requests: [request("host", ["target": "/early"], at: early, id: "req-a", tool: "tool-a")]),
                          node(helperB, requests: [request("host", ["target": "/late"], at: late, id: "req-c", tool: "tool-c")])])
        let read = head(frame, tree).request
        #expect(read?.requestID == "req-a")
        #expect(read?.frame == helperA)
        #expect(read?.helper == true)
        // The root's own, when it is the earliest.
        let rootFirst = head(rootFrame([request("network", ["target": "first.example.org"], at: early, id: "req-b", tool: "tool-b")]),
                             trace([node(helperA, requests: [request("host", ["target": "/x"], at: mid, id: "req-a", tool: "tool-a")])])).request
        #expect(rootFirst?.requestID == "req-b")
        #expect(rootFirst?.frame == root)
        #expect(rootFirst?.helper == false)
    }

    @Test func theRootsOwnQueueIsInOrderOfTime() {
        let frame = rootFrame([request("host", ["target": "/second"], at: mid, id: "req-2", tool: "tool-2"),
                               request("host", ["target": "/first"], at: early, id: "req-1", tool: "tool-1")])
        #expect(head(frame, trace()).request?.target == "/first")
    }

    @Test func aTieGoesToTheSmallerRequestIDThenTheSmallerFrameID() {
        let same = request("host", ["target": "/x"], at: early, id: "req-b", tool: "tool-b")
        let smaller = request("host", ["target": "/y"], at: early, id: "req-a", tool: "tool-a")
        #expect(head(rootFrame([same, smaller]), trace()).request?.requestID == "req-a")
        let one = request("host", ["target": "/x"], at: early, id: "req-a", tool: "tool-a")
        let tree = trace([node(helperB, requests: [one]), node(helperA, requests: [one])])
        #expect(head(rootFrame([]), tree).request?.frame == helperA)
    }

    @Test func aTimeInMillisecondsOrSecondsOrTextOrderTheSame() {
        let ms = request("host", ["target": "/ms"], at: early, id: "req-1", tool: "tool-1")
        var viaSeconds = request("host", ["target": "/seconds"], id: "req-2", tool: "tool-2")
        viaSeconds["createdAt"] = 1_791_831_000 // 2026-10-12T18:50:00Z
        var viaMillis = request("host", ["target": "/millis"], id: "req-3", tool: "tool-3")
        viaMillis["createdAt"] = 1_791_834_000_000
        #expect(head(rootFrame([ms, viaMillis, viaSeconds]), trace()).request?.target == "/seconds")
    }

    @Test func aRequestWithNoTimeGoesFirstSoNothingBehindItIsOffered() throws {
        var untimed = request("network", ["target": "genomes.example.org"], id: "req-0", tool: "tool-0")
        untimed["createdAt"] = "yesterday"
        let timed = request("local_exec", ["tool": "python", "code": "print(1)"], at: early, id: "req-1", tool: "tool-1")
        let read = try #require(head(rootFrame([timed, untimed]), trace()).request)
        #expect(read.requestID == "req-0")
        #expect(!RemotePermission.decide(read, actionsOn: true).canAllow)
        #expect(!RemotePermission.decide(read, actionsOn: true).canDeny)
    }

    @Test func aQuestionAheadOfARequestIsTheRootsAndNothingIsOffered() {
        let ask: [String: Any] = ["kind": "ask", "tool_id": "toolu_1", "createdAt": early, "questions": [["question": "Q?"]]]
        let permission = request("network", ["target": "genomes.example.org"], at: mid)
        #expect(head(rootFrame([permission, ask]), trace()).json == "null")
        // A helper's question ahead of the root's request: also nothing.
        let tree = trace([node(helperA, requests: [ask])])
        #expect(head(rootFrame([permission]), tree).json == "null")
    }

    @Test func aQuestionBehindARequestLeavesTheRequestAsTheHead() {
        let ask: [String: Any] = ["kind": "ask", "tool_id": "toolu_1", "createdAt": late, "questions": [["question": "Q?"]]]
        let permission = request("network", ["target": "genomes.example.org"], at: early)
        #expect(head(rootFrame([ask, permission]), trace()).request?.target == "genomes.example.org")
    }

    @Test func onlyFramesThatHoldRequestsAreRead() {
        // A finished helper with a stale request is not a holder; a processing one is.
        let stale = request("network", ["target": "stale.example.org"], at: early, id: "req-s", tool: "tool-s")
        let live = request("network", ["target": "live.example.org"], at: mid, id: "req-l", tool: "tool-l")
        let tree = trace([node(helperA, status: "completed", requests: [stale]), node(helperB, status: "processing", requests: [live])])
        #expect(head(rootFrame([]), tree).request?.target == "live.example.org")
        // The root itself, completed: nothing is waiting.
        #expect(head(rootFrame(status: "completed", [live]), trace()).json == "null")
    }

    @Test func nothingWaitingIsNull() {
        #expect(head(rootFrame([]), trace()).json == "null")
        #expect(head(ReaderFixture.frame(status: "processing", context: "null", output: "null"), trace()).json == "null")
        #expect(head(rootFrame([]), trace([node(helperA)])).json == "null")
    }

    @Test func aHelpersOutputThatIsTextIsReadToo() {
        let tree = trace([node(helperA, requests: [request("network", ["target": "genomes.example.org"])], outputAsText: true)])
        #expect(head(rootFrame([]), tree).request?.frame == helperA)
    }
}

// MARK: Helpers: the chain to the root

struct PermissionChainTests {
    @Test func aGrandchildsChainReachesTheRoot() throws {
        let asking = request("local_exec", ["tool": "python", "code": "print(1)"])
        let tree = trace([node(helperA, children: [node(deeper, parent: helperA, requests: [asking])])])
        let read = try #require(head(rootFrame([]), tree).request)
        #expect(read.frame == deeper)
        #expect(read.chain == [deeper, helperA, root])
        #expect(read.helper)
        #expect(RemotePermission.describe(read, actionsOn: true).helper)
    }

    @Test func theRootsOwnChainIsJustTheRoot() throws {
        let read = try #require(alone(request("network", ["target": "genomes.example.org"])))
        #expect(read.chain == [root])
        #expect(!read.helper)
    }

    @Test(arguments: [
        // A child that says another parent than the one it hangs under.
        #"{"id": "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6", "parent_frame_id": "2d9e4a6b-3c4d-4e5f-8a1b-c2d3e4f5a6b7", "status": "awaiting_user_response", "output_data": null, "children": []}"#,
        // No parent at all.
        #"{"id": "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6", "status": "awaiting_user_response", "output_data": null, "children": []}"#,
        // An id that is not one.
        #"{"id": "helper", "parent_frame_id": "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", "status": "awaiting_user_response", "output_data": null, "children": []}"#,
        // A status the daemon doesn't have.
        #"{"id": "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6", "parent_frame_id": "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", "status": "thinking", "output_data": null, "children": []}"#,
        // Output that isn't an object, on a frame that holds requests.
        #"{"id": "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6", "parent_frame_id": "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", "status": "awaiting_user_response", "output_data": [1], "children": []}"#,
        #"{"id": "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6", "parent_frame_id": "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", "status": "awaiting_user_response", "output_data": {"pending_input_requests": {"kind": "network"}}, "children": []}"#,
        // Children that aren't a list.
        #"{"id": "1c8d3f5a-2b3c-4d4e-9fa0-b1c2d3e4f5a6", "parent_frame_id": "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", "status": "awaiting_user_response", "output_data": null, "children": {}}"#,
        "42",
    ])
    func aTreeThatDoesNotMatchOffersNothing(_ child: String) {
        let tree = #"{"id": "\#(root)", "children": [\#(child)]}"#
        // The root's own request is there; a tree that can't be trusted hides it too:
        // an earlier request under a frame Bench can't read might be the head.
        #expect(head(rootFrame([request("network", ["target": "genomes.example.org"])]), tree).json == "null")
    }

    @Test(arguments: [
        #"{"id": "9f8e7d6c-5b4a-4321-8fed-cba987654321", "children": []}"#,
        #"{"children": []}"#,
        #"{"id": "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5", "children": "none"}"#,
        "[]",
        "null",
    ])
    func aTraceThatIsNotThisSessionsOffersNothing(_ tree: String) {
        #expect(head(rootFrame([request("network", ["target": "genomes.example.org"])]), tree).json == "null")
    }

    /// A chain of helpers `depth` deep, the deepest one asking.
    private func chain(depth: Int) -> String {
        let ids = (0..<depth).map { String(format: "4fb06c8d-5e6f-4a71-8c3d-e4f5a6b7c8%02d", $0) }
        var inner: [String: Any]?
        for index in stride(from: depth - 1, through: 0, by: -1) {
            let asking = index == depth - 1
            inner = node(ids[index], parent: index == 0 ? root : ids[index - 1], status: asking ? "awaiting_user_response" : "processing",
                         requests: asking ? [request("network", ["target": "genomes.example.org"])] : [],
                         children: inner.map { [$0] } ?? [])
        }
        return trace(inner.map { [$0] } ?? [])
    }

    @Test func aDeepChainIsReadUpToSixteenHelpers() {
        #expect(head(rootFrame([]), chain(depth: 8)).request?.chain.count == 9)
        #expect(head(rootFrame([]), chain(depth: 15)).request?.chain.count == 16)
        #expect(head(rootFrame([]), chain(depth: 16)).request?.chain.count == 17)
        #expect(head(rootFrame([]), chain(depth: 17)).json == "null")
        #expect(head(rootFrame([]), chain(depth: 30)).json == "null")
    }

    @Test func aRootThatIsNotAFrameIDIsRefused() {
        #expect(head(rootFrame([request("network", ["target": "h"])]), trace(), rootID: "0b7c2f4e").json == "null")
    }
}

// MARK: Swift's own checks

struct PermissionRequestChecksTests {
    private static func valid() -> [String: Any] {
        ["requestId": "req-1", "toolId": "tool-1", "mode": "live", "kind": "network", "frame": root, "chain": [root],
         "shape": true, "target": "genomes.example.org", "access": NSNull(), "count": NSNull(), "tool": NSNull(),
         "server": NSNull(), "source": NSNull(), "provider": NSNull(), "name": NSNull(), "readOnly": false,
         "sharedEnv": false, "code": NSNull(), "codeProblem": NSNull()]
    }

    @Test func aValidProjectionIsTaken() throws {
        let read = try #require(PermissionRequest(object: Self.valid()))
        #expect(read.kind == "network")
        #expect(read.target == "genomes.example.org")
        #expect(read.known == .network)
    }

    private static func outOfShape() -> [(String, Any)] {
        [
            ("requestId", ""), ("requestId", "has space"), ("requestId", String(repeating: "a", count: 201)), ("requestId", 5),
            ("toolId", "tool\n1"), ("mode", "later"), ("mode", 3),
            ("kind", "Network"), ("kind", "9lives"), ("kind", ""), ("kind", String(repeating: "a", count: 41)), ("kind", NSNull()),
            ("frame", "0b7c2f4e"), ("frame", NSNull()),
            ("chain", [Any]()), ("chain", [root, root]), ("chain", ["0b7c2f4e"]), ("chain", [helperA]), ("chain", "x"),
            ("chain", Array(repeating: helperA, count: 18)),
            ("shape", 1), ("shape", NSNull()),
            ("target", String(repeating: "a", count: 401)), ("target", ""), ("target", 4),
            ("access", "rwx"), ("count", -1), ("count", 100_001), ("count", 1.5), ("count", true),
            ("tool", String(repeating: "a", count: 201)), ("source", String(repeating: "a", count: 41)),
            ("provider", String(repeating: "a", count: 101)), ("name", String(repeating: "a", count: 201)),
            ("readOnly", "true"), ("readOnly", NSNull()), ("sharedEnv", 0),
            ("code", String(repeating: "a", count: 4001)), ("code", "  "),
            ("codeProblem", "huge"), ("codeProblem", 1),
        ]
    }

    @Test(arguments: 0..<41)
    func anythingOutOfShapeIsLeftOut(_ index: Int) throws {
        let cases = Self.outOfShape()
        #expect(cases.count == 41)
        let (key, value) = try #require(index < cases.count ? cases[index] : nil)
        var object = Self.valid()
        object[key] = value
        #expect(PermissionRequest(object: object) == nil, "\(key)")
    }

    @Test func theSessionStillReadsWithoutAPermissionThatDoesNotMatch() {
        var bad = SessionReaderTestsSupport.session
        bad["permission"] = ["kind": 5]
        let read = SessionProjection(object: bad)
        #expect(read != nil)
        #expect(read?.permission == nil)
        var good = SessionReaderTestsSupport.session
        good["permission"] = Self.valid()
        #expect(SessionProjection(object: good)?.permission?.kind == "network")
    }
}

private enum SessionReaderTestsSupport {
    static var session: [String: Any] { [
        "status": "processing", "agentName": "a", "projectId": NSNull(), "statusLine": NSNull(), "reply": NSNull(),
        "replyAt": NSNull(), "toYou": [Any](), "queued": 0, "asks": [Any](),
        "plan": ["version": NSNull(), "artifact": NSNull(), "approval": "no"], "turns": NSNull(),
    ] }
}

// MARK: The write

struct PermissionWriteTests {
    private func build(_ write: RemoteWrite) -> [String: Any]? {
        let script = PageScript(SessionWriterScript.builder)
        guard let data = try? JSONSerialization.data(withJSONObject: write.arguments),
              let out = script.callJSON("benchBuildWrite", [String(decoding: data, as: UTF8.self)]) else { return nil }
        #expect(script.exception == nil)
        return (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
    }

    private func text(_ value: Any?) -> String {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    @Test func anAllowIsTheExactBodyToTheHolder() {
        let write = build(.permission(frame: helperA, requestID: "req-1", toolID: "tool-1", allow: true))
        #expect(write?["path"] as? String == "/api/frames/\(helperA)/resolve-input")
        #expect(text(write?["body"]) == #"{"responses":[{"action":"allow","approved":true,"requestId":"req-1","tool_id":"tool-1"}]}"#)
    }

    @Test func aDenyIsTheExactBodyToTheHolder() {
        let write = build(.permission(frame: root, requestID: "req-1", toolID: "tool-1", allow: false))
        #expect(write?["path"] as? String == "/api/frames/\(root)/resolve-input")
        #expect(text(write?["body"]) == #"{"responses":[{"action":"deny","approved":false,"requestId":"req-1","tool_id":"tool-1"}]}"#)
    }

    @Test func theKeysAreInTheDaemonsOrderAndNoScopeIsEverThere() throws {
        // The body as sent, not as sorted: requestId, tool_id, approved, action.
        let script = PageScript(SessionWriterScript.builder)
        for allow in [true, false] {
            let data = try JSONSerialization.data(withJSONObject: RemoteWrite.permission(frame: root, requestID: "r", toolID: "t", allow: allow).arguments)
            let sent = script.evaluate("JSON.stringify(benchBuildWrite(JSON.parse('\(String(decoding: data, as: UTF8.self))')).body)") ?? ""
            #expect(sent == #"{"responses":[{"requestId":"r","tool_id":"t","approved":\#(allow),"action":"\#(allow ? "allow" : "deny")"}]}"#)
            #expect(!sent.contains("scope") && !sent.contains("mode") && !sent.contains("text") && !sent.contains("redirect"))
        }
    }

    private static func refused() -> [RemoteWrite] {
        [
            .permission(frame: "0b7c2f4e", requestID: "r", toolID: "t", allow: true),
            .permission(frame: root.uppercased(), requestID: "r", toolID: "t", allow: true),
            .permission(frame: "../../usage/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", requestID: "r", toolID: "t", allow: true),
            .permission(frame: root, requestID: "", toolID: "t", allow: true),
            .permission(frame: root, requestID: "r", toolID: "", allow: true),
            .permission(frame: root, requestID: "has space", toolID: "t", allow: true),
            .permission(frame: root, requestID: "r", toolID: "t\nx", allow: false),
            .permission(frame: root, requestID: String(repeating: "r", count: 201), toolID: "t", allow: true),
            .permission(frame: root, requestID: "r", toolID: String(repeating: "t", count: 201), allow: false),
        ]
    }

    @Test(arguments: 0..<9)
    func anythingElseBuildsNothing(_ index: Int) {
        let cases = Self.refused()
        #expect(cases.count == 9)
        guard index < cases.count else { return }
        #expect(build(cases[index]) == nil)
    }

    @Test func aDecisionThatIsNeitherIsRefused() throws {
        var arguments = RemoteWrite.permission(frame: root, requestID: "r", toolID: "t", allow: true).arguments
        for decision: Any in ["always", "ALLOW", true, NSNull(), 1] {
            arguments["decision"] = decision
            let script = PageScript(SessionWriterScript.builder)
            let data = try JSONSerialization.data(withJSONObject: arguments)
            #expect(script.callJSON("benchBuildWrite", [String(decoding: data, as: UTF8.self)]) == "null", "\(decision)")
        }
    }

    @Test func noScopeCanBeSmuggledInThroughTheArguments() throws {
        var arguments = RemoteWrite.permission(frame: root, requestID: "r", toolID: "t", allow: true).arguments
        arguments["scope"] = "always"
        arguments["mode"] = "answer"
        arguments["answers"] = ["Q?": "A"]
        arguments["path"] = "/api/frames/\(root)/approve-plan"
        let script = PageScript(SessionWriterScript.builder)
        let data = try JSONSerialization.data(withJSONObject: arguments)
        let out = script.callJSON("benchBuildWrite", [String(decoding: data, as: UTF8.self)]) ?? ""
        #expect(!out.contains("scope"))
        #expect(!out.contains("answers"))
        #expect(out.contains("/resolve-input"))
    }

    // MARK: Through the page

    private func run(_ write: RemoteWrite, answers: [String: [PageScript.Answer]],
                     cookie: String = "theme=dark; operon_csrf=secret%20one") -> (result: RemoteWriteResult?, requests: [PageScript.Request]) {
        let script = PageScript()
        let arguments = write.arguments.keys.sorted().map { key -> (String, String) in
            let value = write.arguments[key]!
            let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data("null".utf8)
            return (key, String(decoding: data, as: UTF8.self))
        }
        let (raw, requests) = script.runPage(SessionWriterScript.body, arguments: arguments, answers: answers, cookie: cookie)
        #expect(script.exception == nil)
        return (raw.flatMap { try? SessionWriterScript.result(of: Data($0.utf8)) }, requests)
    }

    private var path: String { "/api/frames/\(helperA)/resolve-input" }
    private var write: RemoteWrite { .permission(frame: helperA, requestID: "req-1", toolID: "tool-1", allow: true) }

    @Test func thePageSendsOneResolveInputWithTheSecretAndNoScope() {
        let reply = #"{"root_frame_id":"\#(root)","frame_id":"\#(helperA)","status":"accepted","remaining_tool_ids":[]}"#
        let (result, requests) = run(write, answers: [path: [.init(status: 200, body: reply)]])
        #expect(result == RemoteWriteResult(status: 200, bodyStatus: "accepted", remaining: 0, rootFrameID: root))
        #expect(requests.count == 1)
        #expect(requests.first?.method == "POST")
        #expect(requests.first?.path == path)
        #expect(requests.first?.csrf == "secret one")
        #expect(requests.first?.body == #"{"responses":[{"requestId":"req-1","tool_id":"tool-1","approved":true,"action":"allow"}]}"#)
    }

    @Test func aStaleSecretIsRefreshedAndTriedOnce() {
        let stale = PageScript.Answer(status: 403, body: #"{"code":"csrf_stale"}"#)
        let (result, requests) = run(write, answers: [path: [stale, .init(status: 200, body: #"{"status":"accepted"}"#)],
                                                      "/api/csrf": [.init(status: 204, body: "")]])
        #expect(result?.bodyStatus == "accepted")
        #expect(requests.map(\.path) == [path, "/api/csrf", path])
    }

    @Test func partialIsAStatusBenchKnows() {
        let (result, _) = run(write, answers: [path: [.init(status: 200, body: #"{"status":"partial","remaining_tool_ids":["x"]}"#)]])
        #expect(result?.bodyStatus == "partial")
        #expect(result?.remaining == 1)
    }

    @Test(arguments: [
        #"{"error": "live_approval_stale: the request was already answered"}"#,
        #"{"error": "No pending request matching requestId req-1"}"#,
        #"{"error": "Frame not awaiting user response"}"#,
        #"{"error": "no pending input requests"}"#,
        #"{"error": "Frame state changed while resolving input"}"#,
    ])
    func theDaemonsWordsForAlreadyHandledAreFlags(_ body: String) {
        let (result, _) = run(write, answers: [path: [.init(status: 400, body: body)]])
        #expect(result?.staleInput == true)
    }
}

// MARK: Decisions

struct PermissionDecideTests {
    private func read(_ request: PermissionRequest?, status: String = "processing") -> SessionProjection {
        SessionProjection(status: status, agentName: "made-up-agent", projectID: "proj-1", turns: [], permission: request)
    }

    private let exec = PermissionRequest(requestID: "req-1", toolID: "tool-1", kind: "local_exec", frame: root, tool: "python", code: "print(1)")
    private let net = PermissionRequest(requestID: "req-2", toolID: "tool-2", mode: "parked", kind: "network", frame: root, target: "genomes.example.org")
    private let helper = PermissionRequest(requestID: "req-3", toolID: "tool-3", mode: "parked", kind: "mcp_tool", frame: helperA, chain: [helperA, root],
                                           tool: "search_papers", server: "Paper search", source: "directory", readOnly: true)

    private func decide(_ body: String, _ fresh: SessionProjection?) -> RemoteDecide.Step {
        PermissionDecide.decide(RemoteActionRequest.parse(.permission, body: Data(body.utf8))!, session: root, fresh: fresh)
    }

    private func changed(_ step: RemoteDecide.Step) -> Bool {
        if case .answer(let result) = step { result.result == .changed } else { false }
    }

    @Test func allowingTheHeadWritesToTheRoot() {
        #expect(decide(#"{"id":"req-1","decision":"allow"}"#, read(exec))
                == .write(.permission(frame: root, requestID: "req-1", toolID: "tool-1", allow: true)))
        #expect(decide(#"{"id":"req-1","decision":"deny"}"#, read(exec))
                == .write(.permission(frame: root, requestID: "req-1", toolID: "tool-1", allow: false)))
    }

    @Test func aHelpersRequestGoesToTheHelpersFrame() {
        #expect(decide(#"{"id":"req-3","decision":"allow"}"#, read(helper))
                == .write(.permission(frame: helperA, requestID: "req-3", toolID: "tool-3", allow: true)))
    }

    @Test func aRequestThatIsNoLongerTheHeadIsChanged() {
        #expect(changed(decide(#"{"id":"req-1","decision":"allow"}"#, read(net))))
        #expect(changed(decide(#"{"id":"req-1","decision":"allow"}"#, read(nil))))
        #expect(changed(decide(#"{"id":"req-1","decision":"deny"}"#, read(nil, status: "completed"))))
    }

    @Test func aKindThatChangedIsChanged() {
        #expect(decide(#"{"id":"req-1","decision":"allow","kind":"local_exec"}"#, read(exec))
                == .write(.permission(frame: root, requestID: "req-1", toolID: "tool-1", allow: true)))
        #expect(changed(decide(#"{"id":"req-1","decision":"allow","kind":"mcp_tool"}"#, read(exec))))
    }

    @Test func aHolderThatDoesNotReachThisSessionsRootIsChanged() {
        let elsewhere = PermissionRequest(requestID: "req-3", toolID: "tool-3", mode: "parked", kind: "mcp_tool", frame: helperA,
                                          chain: [helperA, helperB], tool: "t", server: "s", source: "directory", readOnly: true)
        #expect(changed(decide(#"{"id":"req-3","decision":"allow"}"#, read(elsewhere))))
        // The chain of another session's root: the same.
        let other = PermissionRequest(requestID: "req-1", toolID: "tool-1", kind: "local_exec", frame: helperB, chain: [helperB],
                                      tool: "python", code: "print(1)")
        #expect(changed(decide(#"{"id":"req-1","decision":"allow"}"#, read(other))))
    }

    @Test func anAllowThatIsNotAllowedIsRefusedWithItsReasonAndWritesNothing() {
        let step = decide(#"{"id":"req-2","decision":"allow"}"#, read(net))
        #expect(step == .answer(RemoteActionResult(result: .unavailable,
                                                   sentence: "Allowing this from your phone would give lasting access. Open it on your Mac.")))
        let shared = PermissionRequest(requestID: "req-1", toolID: "tool-1", kind: "local_exec", frame: root, tool: "python",
                                       sharedEnv: true, code: "print(1)")
        #expect(decide(#"{"id":"req-1","decision":"allow"}"#, read(shared)) == .answer(RemoteActionResult(
            result: .unavailable, sentence: "This code would run in a shared environment. Open it on your Mac.")))
        // But it may be denied.
        #expect(decide(#"{"id":"req-1","decision":"deny"}"#, read(shared))
                == .write(.permission(frame: root, requestID: "req-1", toolID: "tool-1", allow: false)))
    }

    @Test func aKindThatOnlyOpensOnTheMacCanBeNeither() {
        let license = PermissionRequest(requestID: "req-4", toolID: "tool-4", mode: "parked", kind: "skill_license", frame: root, name: "made-up-skill")
        for decision in ["allow", "deny"] {
            let step = decide(#"{"id":"req-4","decision":"\#(decision)"}"#, read(license))
            guard case .answer(let result) = step else {
                Issue.record("wrote \(step)")
                continue
            }
            #expect(result.result == .unavailable)
        }
    }

    @Test func anUnreadableSessionIsUnavailable() {
        #expect(decide(#"{"id":"req-1","decision":"allow"}"#, nil) == .answer(.unavailable))
    }

    // MARK: The body

    @Test func goodBodies() {
        #expect(RemoteActionRequest.parse(.permission, body: Data(#"{"id":"req-1","decision":"allow"}"#.utf8)) == .permission(id: "req-1", allow: true, kind: nil))
        #expect(RemoteActionRequest.parse(.permission, body: Data(#"{"id":"req-1","decision":"deny","kind":"network"}"#.utf8))
                == .permission(id: "req-1", allow: false, kind: "network"))
    }

    @Test(arguments: [
        "{}", #"{"id":"req-1"}"#, #"{"decision":"allow"}"#, #"{"id":"req-1","decision":"always"}"#,
        #"{"id":"req-1","decision":true}"#, #"{"id":"","decision":"allow"}"#, #"{"id":"a b","decision":"allow"}"#,
        #"{"id":5,"decision":"allow"}"#, #"{"id":"req-1","decision":"allow","kind":5}"#,
        #"{"id":"req-1","decision":"allow","kind":"Not A Word"}"#, #"["req-1"]"#, "not json",
    ])
    func badBodies(_ body: String) {
        #expect(RemoteActionRequest.parse(.permission, body: Data(body.utf8)) == nil)
    }

    // MARK: The reply

    @Test(arguments: ["accepted", "buffered", "partial"])
    func theDaemonsDoneWordsAreDone(_ word: String) {
        #expect(PermissionDecide.answered(RemoteWriteResult(status: 200, bodyStatus: word), allow: true).result == .allowed)
        #expect(PermissionDecide.answered(RemoteWriteResult(status: 200, bodyStatus: word), allow: false).result == .denied)
    }

    @Test func everyOtherReplyIsChangedOrUnavailable() {
        #expect(PermissionDecide.answered(RemoteWriteResult(status: 200, bodyStatus: "already_resolved"), allow: true).result == .changed)
        #expect(PermissionDecide.answered(RemoteWriteResult(status: 400, staleInput: true), allow: false).result == .changed)
        #expect(PermissionDecide.answered(RemoteWriteResult(status: 400), allow: true) == .unavailable)
        #expect(PermissionDecide.answered(RemoteWriteResult(status: 500, bodyStatus: "accepted"), allow: true) == .unavailable)
        #expect(PermissionDecide.answered(RemoteWriteResult(status: 200, isJSON: false, bodyStatus: "accepted"), allow: true) == .unavailable)
        #expect(PermissionDecide.answered(RemoteWriteResult(status: 200), allow: true) == .unavailable)
        #expect(PermissionDecide.answered(RemoteWriteResult(status: 403, code: "csrf_stale"), allow: true) == .unavailable)
        #expect(PermissionDecide.answered(nil, allow: true) == .unavailable)
    }
}
