// CompatInventoryTests.swift — the inventory of what Capsid relies on in
// Claude Science (CompatInventory) is held to the code in both directions:
// every selector in a page script, every path an allowlist lets through, every
// write the builders make, every key the status parser takes and every column
// a query reads is in the list, and every column in the list is one a query
// needs. Add a dependency in the code, or drop one, and a test here says so.
//
// The reads of the real source files below are of Capsid's own code, in this
// checkout. No daemon, no page and no real database is touched; the databases
// are made up and hold nothing.
import Foundation
import Testing
@testable import Bench

// MARK: Capsid's own source, as text

private enum Repo {
    /// This checkout: Tests/BenchTests/<this file> → the root.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func url(_ relative: String) -> URL {
        root.appendingPathComponent("Sources/Bench/\(relative)")
    }

    static func source(_ relative: String) -> String {
        (try? String(contentsOf: url(relative), encoding: .utf8)) ?? ""
    }

    /// Every Swift file under Sources/Bench, relative to it.
    static var allFiles: [String] {
        let base = root.appendingPathComponent("Sources/Bench")
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { ($0 as? URL).map { $0.path } }
            .filter { $0.hasSuffix(".swift") }
            .map { String($0.dropFirst(base.path.count + 1)) }
            .sorted()
    }

    /// The files whose text matches `pattern`.
    static func files(matching pattern: String) -> Set<String> {
        let expression = try! NSRegularExpression(pattern: pattern)
        return Set(allFiles.filter { file in
            let text = source(file)
            return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        })
    }
}

/// What a page script looks for, read out of its text.
private enum ScriptLiterals {
    /// The string handed to `querySelector`, `querySelectorAll`, `closest`,
    /// `getAttribute` or `hasAttribute`.
    static func selectors(in script: String) -> Set<String> {
        matches(#"(?:querySelectorAll|querySelector|closest|getAttribute|hasAttribute)\(\s*(['"])(.*?)\1\s*\)"#, in: script, group: 2)
    }

    /// The text a script compares an element's text with: `.trim() === "…"`.
    static func texts(in script: String) -> Set<String> {
        matches(#"trim\(\)\s*===\s*"([^"]*)""#, in: script, group: 1)
    }

    static func matches(_ pattern: String, in text: String, group: Int) -> Set<String> {
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return Set(expression.matches(in: text, range: range).compactMap { found in
            Range(found.range(at: group), in: text).map { String(text[$0]) }
        })
    }
}

// MARK: The list itself

struct CompatInventoryShapeTests {
    @Test func everyKindHasDependenciesAndEveryOneIsDescribed() {
        for kind in CompatKind.allCases {
            #expect(!CompatInventory.dependencies(of: kind).isEmpty, "\(kind)")
        }
        for item in CompatInventory.all {
            #expect(!item.token.isEmpty && !item.detail.isEmpty, "\(item.token)")
            #expect(!item.feature.title.isEmpty)
            if case .whenUsed(let why) = item.check { #expect(!why.isEmpty, "\(item.token)") }
        }
    }

    @Test func eachTokenIsListedOnce() {
        let tokens = CompatInventory.all.map(\.token)
        #expect(Set(tokens).count == tokens.count, "\(tokens.filter { token in tokens.filter { $0 == token }.count > 1 })")
    }

    @Test func theFileEachNamesExists() {
        for item in CompatInventory.all {
            #expect(FileManager.default.fileExists(atPath: Repo.url(item.file).path), "\(item.token): \(item.file)")
        }
    }

    @Test func theFilesAreWhereTheCodeIs() {
        // The first file named for a dependency really holds a trace of it.
        let expectations: [String: String] = [
            "GET /api/usage": "/usage",
            "GET /api/frames/<session>/token-series": "token-series",
            "POST /api/frames/<session>/approve-plan": "approve-plan",
            "Sign in": "Sign in",
            "window.Notification": "Notification",
            "claude-science": "claude-science",
        ]
        for (token, trace) in expectations {
            guard let item = CompatInventory.all.first(where: { $0.token == token }) else {
                Issue.record("no \(token)")
                continue
            }
            #expect(Repo.source(item.file).contains(trace), "\(token) in \(item.file)")
        }
    }

    @Test func writesAreAlwaysCheckedOnlyWhenUsed() {
        for item in CompatInventory.writeEndpoints {
            #expect(item.isWhenUsed, "\(item.token)")
            #expect(item.kind == .writeEndpoint)
        }
    }

    @Test func theCheckedWithVersionIsTheOneTheDesignNames() {
        // DESIGN.md names the version the markup was read from, in the sentence
        // about the selectors; bumping one means bumping the other.
        let design = (try? String(contentsOf: Repo.root.appendingPathComponent("DESIGN.md"), encoding: .utf8)) ?? ""
        let named = "Claude Science \(CompatInventory.checkedWith)"
        #expect(design.contains(named), "DESIGN.md should say \"\(named)\" (Main window, Selectors relied on)")
        #expect(ScienceVersion.parse(CompatInventory.checkedWith) != nil)
    }
}

// MARK: The page

struct CompatPageHookTests {
    /// Every page script that looks at Claude Science's markup.
    private var scripts: [String] {
        [PageTabsScript.body, PageTabsScript.probe, TabContextMenu.script, ConversationMenu.script, ModelPickerMenu.script,
         SignInScript.press, SignInScript.look, HandoverWatch.script, SourceSeek.body]
    }

    private var literalTokens: Set<String> {
        Set(CompatInventory.pageHooks.filter(\.literal).map(\.token))
    }

    /// Every selector, attribute name and compared text in the scripts.
    private var used: Set<String> {
        scripts.reduce(into: Set<String>()) { all, script in
            all.formUnion(ScriptLiterals.selectors(in: script))
            all.formUnion(ScriptLiterals.texts(in: script))
        }
    }

    @Test func everySelectorTheScriptsUseIsInTheInventory() {
        let used = self.used
        #expect(!used.isEmpty)
        let missing = used.subtracting(literalTokens)
        #expect(missing.isEmpty, "not in the inventory: \(missing.sorted())")
    }

    @Test func everySelectorInTheInventoryIsOneTheScriptsUse() {
        let stale = literalTokens.subtracting(self.used)
        #expect(stale.isEmpty, "no script uses: \(stale.sorted())")
    }

    @Test func theExtractionSeesTheSelectorsItShould() {
        // The two checks above mean nothing if the extraction found nothing.
        let tabs = ScriptLiterals.selectors(in: PageTabsScript.body)
        #expect(tabs.contains(#"[data-testid="right-tab-strip"]"#))
        #expect(tabs.contains(#"[role="toolbar"][aria-label="Open panels"]"#))
        #expect(tabs.contains("button[data-tab-close]"))
        #expect(tabs.contains("aria-current"))
        #expect(ScriptLiterals.selectors(in: TabContextMenu.script) == [#"[data-testid="right-tab-strip"] [data-tab-id]"#, "data-tab-id"])
        #expect(ScriptLiterals.selectors(in: ConversationMenu.script) == [
            "img, a[href]", #"[data-testid="turn-tray-card"]"#, "img", #"[role="menu"]"#, #"[role="menu"][aria-label="Artifact actions"]"#,
            #"[role="menuitem"]"#, #"[data-cds="Icon"]"#,
            // A file with no picture, by its name: the card's label, the tile's body, its header and the button in it.
            #"[data-testid="middle-truncated-filename"]"#, #"[data-testid="artifact-preview-region"]"#, "header",
            #"[data-testid="artifact-actions"]"#,
            // The page's viewer for a picture (the one picture in the zoom-and-pan wrapper of a tile's body), and the name
            // of a tile of the right-hand panel, which its header does not show: the panel's shown tab.
            ".react-transform-component img", #"[data-pane="right"]"#,
            #"[data-testid="right-tab-strip"] [data-tab-id]"#, "[data-tab-btn]", "data-shown", "aria-current",
        ])
        // Show Where It Came From: the scroller, the numbered messages and their rows, the tray, and the card in it.
        #expect(ScriptLiterals.selectors(in: SourceSeek.body) == [
            #"[data-testid="conversation-scroll"]"#, "[data-msg-idx]", "data-msg-idx", "[data-rs-index]",
            #"[data-testid="turn-artifact-tray"]"#, #"[data-testid="turn-tray-card"]"#, "img",
            #"[data-testid="middle-truncated-filename"]"#,
        ])
        #expect(ScriptLiterals.selectors(in: ModelPickerMenu.script) == [
            #"[role="menu"][data-cds="ModelSelector"], [role="menu"][data-testid="model-selector-popup"]"#, #"[role="menu"]"#,
            #"[data-testid="model-selector"]"#, #"[data-testid="composer"]"#, #"[role="menuitemradio"], [role="menuitem"]"#,
            "[data-cds-sheet-scroll]", #"[role="separator"]"#, #"[role="textbox"]"#, "data-voice-ghost", "data-upload-status",
        ])
        #expect(ScriptLiterals.texts(in: SignInScript.press) == ["Sign in"])
        // And a made-up new hook is seen.
        #expect(ScriptLiterals.selectors(in: #"x.querySelector('[data-new]'); y.getAttribute("data-newer");"#) == ["[data-new]", "data-newer"])
    }

    @Test func noOtherFileReadsTheMarkupOfThePage() {
        // Capsid's own phone page (RemoteWebApp) is its own markup.
        let known: Set<String> = ["AskModel/ModelPickerMenu.swift", "Remote/RemoteWebApp.swift", "Shelf/ConversationMenu.swift",
                                  "Shelf/SourceSeek.swift", "Web/HandoverWatch.swift", "Web/PageTabs.swift", "Web/TabContextMenu.swift",
                                  "Web/WebContainer.swift"]
        let found = Repo.files(matching: #"querySelector|\.closest\(|getElementById|getElementsBy"#)
        #expect(found == known, "now: \(found.sorted())")
    }

    @Test func noOtherFileRunsAScriptInThePage() {
        let known: Set<String> = [
            "AskModel/ModelPickerMenu.swift", "Remote/ArtifactReader.swift", "Remote/HistoryReader.swift", "Remote/InsightReader.swift",
            "Remote/RemoteLive.swift", "Remote/RemotePhotoUpload.swift", "Remote/SessionReader.swift", "Remote/SessionWriter.swift",
            "Shelf/ConversationMenu.swift", "Shelf/ShowSource.swift", "Web/HandoverWatch.swift", "Web/NotificationBridge.swift", "Web/PageTabs.swift",
            "Web/TabContextMenu.swift", "Web/WebAPI.swift", "Web/WebContainer.swift",
        ]
        let found = Repo.files(matching: #"callAsyncJavaScript\(|evaluateJavaScript\(|WKUserScript\("#)
        #expect(found == known, "now: \(found.sorted())")
    }

    @Test func theHooksWithNoLiveLookAreMarkedSo() {
        // Only the tab strip, its parts and the address have a live look.
        let live = Set(CompatInventory.pageHooks.filter { !$0.isWhenUsed }.map(\.feature))
        #expect(live == [.closeTabs, .signIn, .sessionAddress])
    }
}

// MARK: Reads and writes

struct CompatEndpointTests {
    private static let session = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
    // Made-up 36-character ids: Keep's reads take no others.
    private static let version = "1c8d3a5f-2b3c-4d4e-9f00-b1c2d3e4f5a6"
    private static let artifact = "6d1f0c2e-7a3b-4c8d-9e10-2b3c4d5e6f70"
    private static let project = "proj_a"

    /// An inventory token's path with sample ids in it.
    private func path(of token: String) -> String {
        token.drop { $0 != "/" }
            .replacingOccurrences(of: "<session>", with: Self.session)
            .replacingOccurrences(of: "<version>", with: Self.version)
            .replacingOccurrences(of: "<artifact>", with: Self.artifact)
            .replacingOccurrences(of: "<project>", with: Self.project)
    }

    // MARK: Reads

    /// The path Capsid really builds for each read, by inventory token, and
    /// whether the real gate for it lets that path through.
    private var reads: [(token: String, built: String, allowed: Bool)] {
        let s = Self.session, v = Self.version, a = Self.artifact
        return [
            ("GET /api/usage", "/api/usage", WebContainer.isReadablePath("/usage") && WebContainer.isReadablePath("/usage?fresh=1")),
            ("GET /api/frames/<session>/token-series", "/api" + ContextModel.seriesPath(for: s),
             WebContainer.isReadablePath(ContextModel.seriesPath(for: s))),
            ("GET /api/frames/<session>?shallow=true", "/api" + (PlanCheck.framePath(s) ?? ""),
             WebContainer.isReadablePath(PlanCheck.framePath(s) ?? "")),
            ("GET /api/artifacts/versions/<version>", "/api" + (PlanCheck.versionPath(v) ?? ""),
             WebContainer.isReadablePath(PlanCheck.versionPath(v) ?? "")
                && ArtifactRead.text(version: v).path == "/api/artifacts/versions/\(v)"),
            ("GET /api/artifacts/versions/<version>?thumbnail=<width>", ArtifactRead.thumb(version: v, width: 120).path ?? "",
             ArtifactRead.isAllowedPath(ArtifactRead.thumb(version: v, width: 800).path ?? "")),
            ("GET /api/frames/<session>/artifacts", ArtifactRead.list(frame: s).path ?? "",
             ArtifactRead.isAllowedPath(ArtifactRead.list(frame: s).path ?? "")),
            ("GET /api/frames/<session>/messages?from=<n>&limit=<n>", "/api/frames/\(s)/messages?from=-12&limit=12",
             HistoryReaderScript.isAllowedPath("/api/frames/\(s)/messages?from=-12&limit=12")
                && HistoryReaderScript.isAllowedPath("/api/frames/\(s)/messages?from=40&limit=50")),
            ("GET /api/frames/<session>/trace-shallow?include_messages=false", PermissionPaths.trace(s) ?? "",
             PermissionPaths.isAllowed(PermissionPaths.trace(s) ?? "")),
            ("GET /api/frames/<session>/streaming", PermissionPaths.streaming(s) ?? "",
             PermissionPaths.isAllowed(PermissionPaths.streaming(s) ?? "")),
            // Keep's three reads, built by the typed reader and gated by its allowlist.
            ("GET /api/artifacts/<artifact>/versions", ArtifactRead.versions(artifact: a).path ?? "",
             ArtifactRead.isAllowedPath(ArtifactRead.versions(artifact: a).path ?? "")),
            ("GET /api/artifacts/versions/<version>?include_metadata=true", ArtifactRead.facts(version: v).path ?? "",
             ArtifactRead.isAllowedPath(ArtifactRead.facts(version: v).path ?? "")),
            ("GET /api/artifacts/versions/<version>/lineage?slim=1", ArtifactRead.lineage(version: v).path ?? "",
             ArtifactRead.isAllowedPath(ArtifactRead.lineage(version: v).path ?? "")),
            // The reviewer's findings, built and gated by the insight reader, which projects them to counts in the page.
            ("GET /api/frames/<session>/verification?resolved_limit=0&actionable_limit=500", InsightReaderScript.verificationPath(s) ?? "",
             InsightReaderScript.isAllowedPath(InsightReaderScript.verificationPath(s) ?? "")),
        ]
    }

    /// The reads that go through the typed artifact reader, which projects
    /// them in the page. `apiGET` is not how they are read, and for the
    /// versions list (it carries `file_path`) it must not be.
    private let typedReads: Set<String> = [
        "GET /api/artifacts/<artifact>/versions", "GET /api/artifacts/versions/<version>?include_metadata=true",
        "GET /api/artifacts/versions/<version>/lineage?slim=1",
    ]

    /// The reads the insight reader projects to counts in the page. `apiGET`
    /// must not read them: its body would hand the findings' text to Swift.
    private let projectedReads: Set<String> = ["GET /api/frames/<session>/verification?resolved_limit=0&actionable_limit=500"]

    /// Reads that are not a path of their own.
    private let notPaths: Set<String> = [
        "GET /api/csrf", "401 on any /api read",
        // A field of the shallow read above, which is a path already listed.
        "output_data.error on GET /api/frames/<session>?shallow=true",
        // Fields of the messages read above, kept by Keep's showing op.
        "_artifact_refs and _ts on GET /api/frames/<session>/messages",
        // A message the history reader projects as a note.
        "send_user_message in GET /api/frames/<session>/messages",
        // Fields of the session tree the phone's permission queue reads; the insight reader projects the plan statuses in the page.
        "plan statuses on GET /api/frames/<session>/trace-shallow?include_messages=false",
    ]

    @Test func everyReadInTheInventoryIsAPathCapsidBuildsAndItsGateAllows() {
        for (token, built, allowed) in reads {
            // The messages token holds placeholders for its query; compare up to it.
            func normal(_ text: String) -> String { token.contains("messages") ? String(text.prefix { $0 != "?" }) : text }
            let expected = path(of: token).replacingOccurrences(of: "<width>", with: "120")
            #expect(normal(built) == normal(expected), "\(token): built \(built)")
            #expect(allowed, "\(token)")
            #expect(CompatInventory.readEndpoints.contains { $0.token == token }, "\(token) is not in the inventory")
        }
    }

    @Test func theInventorysReadsAreExactlyThese() {
        let inventory = Set(CompatInventory.readEndpoints.map(\.token))
        #expect(inventory == Set(reads.map(\.token)).union(notPaths), "\(inventory.symmetricDifference(Set(reads.map(\.token)).union(notPaths)))")
    }

    @Test func theCSRFReadIsMadeByTheWriters() {
        for script in [SessionWriterScript.body, PhotoUploadScript.body] {
            #expect(script.contains(#""/api/csrf""#))
        }
        #expect(Repo.source("Web/WebAPI.swift").contains(#""/api/csrf""#))
    }

    @Test func theReadsTheProbesMakeAreAllOnesApiGETAllows() {
        for item in CompatInventory.readEndpoints where !notPaths.contains(item.token) {
            let sample = path(of: item.token).replacingOccurrences(of: "<width>", with: "120").replacingOccurrences(of: "<n>", with: "5")
            if typedReads.contains(item.token) {
                // Probed (or not) through the typed reader, whose own allowlist holds the shape.
                #expect(ArtifactRead.isAllowedPath(sample), "\(item.token)")
                #expect(item.file == "Remote/ArtifactReader.swift", "\(item.token)")
                continue
            }
            if projectedReads.contains(item.token) {
                // Probed through the insight reader, whose own allowlist holds the shape, and never through apiGET.
                #expect(InsightReaderScript.isAllowedPath(sample), "\(item.token)")
                #expect(item.file == "Remote/InsightReader.swift", "\(item.token)")
                #expect(item.check == .live, "\(item.token)")
                #expect(!WebContainer.isReadablePath(String(sample.dropFirst("/api".count))), "\(item.token) is reachable by apiGET")
                continue
            }
            let readable = WebContainer.isReadablePath(String(sample.dropFirst("/api".count)))
            if item.check == .live {
                #expect(readable, "\(item.token) is probed but apiGET would refuse it")
            } else if !item.token.contains("thumbnail") {
                // The messages, the artifact list, trace-shallow and streaming
                // are out of apiGET's reach, so no probe could read them. (A
                // thumbnail is under the versions prefix, but needs a file.)
                #expect(!readable, "\(item.token) is reachable by apiGET but not probed")
            }
        }
    }

    @Test func everyPrefixApiGETAllowsIsInTheInventory() {
        for prefix in WebContainer.readablePrefixes {
            #expect(CompatInventory.readEndpoints.contains { $0.token.contains("/api" + prefix) }, "\(prefix)")
        }
    }

    @Test func keepsReadsAreInTheInventoryWithTheirChecks() {
        #expect(CompatFeature.keep.title == "Keep a figure with its answer, data and script")
        func item(_ token: String) -> CompatDependency? { CompatInventory.readEndpoints.first { $0.token == token } }
        let versions = item("GET /api/artifacts/<artifact>/versions")
        let facts = item("GET /api/artifacts/versions/<version>?include_metadata=true")
        let lineage = item("GET /api/artifacts/versions/<version>/lineage?slim=1")
        let refs = item("_artifact_refs and _ts on GET /api/frames/<session>/messages")
        // The two pure reads are looked at; the lineage can start a reconstruction and the messages are what was said.
        #expect(versions?.check == .live && facts?.check == .live)
        #expect(lineage?.check == .whenUsed("reading it can start Claude Science's own code reconstruction, so it is not read from here"))
        #expect(refs?.check == .whenUsed("it is what was said, so it is never read from here"))
        #expect([versions, facts, lineage, refs].allSatisfy { $0?.feature == .keep && $0?.kind == .readEndpoint })
        #expect(refs?.file == "Remote/HistoryReader.swift")
        // The reads the probes make are the live ones.
        #expect(CompatProbes.Name.all.contains("GET /api/artifacts/<artifact>/versions"))
        #expect(CompatProbes.Name.all.contains("GET /api/artifacts/versions/<version>?include_metadata=true"))
        #expect(!CompatProbes.Name.all.contains("GET /api/artifacts/versions/<version>/lineage?slim=1"))
        // The page never lists a field the inventory doesn't, for what Keep reads of a version.
        #expect(facts?.detail.contains("reproduction_code") == true && facts?.detail.contains("python_version") == true)
        #expect(lineage?.detail.contains("workspace_path") == true && lineage?.detail.contains("consensus") == true)
        #expect(versions?.detail.contains("parent_version_id") == true && versions?.detail.contains("file_path") == true)
    }

    @Test func stepProgressTheReviewerAndNotesAreInTheInventoryWithTheirChecks() {
        func item(_ token: String) -> CompatDependency? { CompatInventory.readEndpoints.first { $0.token == token } }
        let progress = item("plan statuses on GET /api/frames/<session>/trace-shallow?include_messages=false")
        let reviewer = item("GET /api/frames/<session>/verification?resolved_limit=0&actionable_limit=500")
        let note = item("send_user_message in GET /api/frames/<session>/messages")
        // Both projected counts are pure reads and are looked at; a note is what was said.
        #expect(progress?.check == .live && reviewer?.check == .live)
        #expect(note?.check == .whenUsed("it is what was said, so it is never read from here"))
        #expect(progress?.feature == .planProgress && reviewer?.feature == .reviewer && note?.feature == .notes)
        #expect([progress, reviewer].allSatisfy { $0?.file == "Remote/InsightReader.swift" && $0?.kind == .readEndpoint })
        #expect(note?.file == "Remote/HistoryReader.swift")
        #expect(CompatProbes.Name.all.contains(CompatProbes.Name.progress) && CompatProbes.Name.all.contains(CompatProbes.Name.reviewer))
        #expect(CompatProbes.Name.progress == progress?.token && CompatProbes.Name.reviewer == reviewer?.token)
        // The page's fields the projection reads are all named in the inventory's words.
        for field in ["_plan_approved", "_plan_version_id", "_plan_json", "_step_statuses", "_plan_claims", "pending|in_progress|completed|blocked|skipped"] {
            #expect(progress?.detail.contains(field) == true, "\(field)")
        }
        for field in ["verdict", "status", "rebuttal", "reflag_count", "running", "completed_review_count", "resolved_by_verdict"] {
            #expect(reviewer?.detail.contains(field) == true, "\(field)")
        }
        #expect(progress?.detail.contains("never a step's description") == true)
        #expect(reviewer?.detail.contains("never a claim, its evidence or a rebuttal") == true)
        // The sources the page's counting rule rests on are named only once each.
        #expect(CompatFeature.planProgress.title == "Step n of m under a running session")
        #expect(CompatFeature.reviewer.title == "The reviewer's findings on a finished card")
    }

    @Test func theInsightReadersTwoPathsAreTheOnlyOnesItsScriptAllowsAndApiGETReadsNeither() {
        let s = Self.session
        let trace = InsightReaderScript.tracePath(s)
        #expect(trace == "/api/frames/\(s)/trace-shallow?include_messages=false")
        #expect(trace == PermissionPaths.trace(s))
        #expect(InsightReaderScript.verificationPath(s) == "/api/frames/\(s)/verification?resolved_limit=0&actionable_limit=500")
        for path in [trace, InsightReaderScript.verificationPath(s)].compactMap({ $0 }) {
            #expect(InsightReaderScript.isAllowedPath(path))
            #expect(!WebContainer.isReadablePath(String(path.dropFirst("/api".count))), "\(path)")
        }
    }

    // MARK: Writes

    private func build(_ write: RemoteWrite) -> String? {
        let script = PageScript(SessionWriterScript.builder)
        guard let data = try? JSONSerialization.data(withJSONObject: write.arguments),
              let out = script.callJSON("benchBuildWrite", [String(decoding: data, as: UTF8.self)]),
              let object = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] else { return nil }
        return object["path"] as? String
    }

    @Test func everyWriteInTheInventoryIsAPathTheBuildersMake() {
        let s = Self.session, p = Self.project
        let intent = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
        let photo = PhotoFile(data: Data(count: 10), name: "phone-photo-20261012-193000.jpg", width: 4, height: 3)
        let upload: String? = {
            let script = PageScript(PhotoUploadScript.builder)
            let json = String(decoding: (try? JSONSerialization.data(withJSONObject: PhotoUploadScript.arguments(project: p, photo: photo))) ?? Data(), as: UTF8.self)
            return (script.callJSON("benchBuildUpload", [json]))
                .flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }?["path"] as? String
        }()
        let built: [String: [String?]] = [
            "POST /api/frames/<session>/approve-plan": [build(.approvePlan(frame: s)), "/api" + (PlanCheck.approvePath(s) ?? "")],
            "POST /api/frames/<session>/resolve-input": [
                build(.answer(frame: s, toolID: "tool-1", answers: ["Q": "A"])),
                build(.cancel(frame: s, toolID: "tool-1")),
                build(.permission(frame: s, requestID: "req-1", toolID: "tool-1", allow: true)),
            ],
            "POST /api/request": [
                build(.message(frame: s, agent: "OPERON", projectID: p, text: "Made-up", intentID: intent)),
                build(.planFeedback(frame: s, agent: "OPERON", projectID: p, text: "Made-up", intentID: intent)),
            ],
            "POST /api/projects/<project>/request": [build(.newSession(project: p, text: "Made-up", planMode: false, intentID: intent))],
            "POST /api/projects/<project>/attachments": [upload],
        ]
        for (token, paths) in built {
            #expect(CompatInventory.writeEndpoints.contains { $0.token == token }, "\(token) is not in the inventory")
            for made in paths { #expect(made == path(of: token), "\(token): built \(made ?? "nothing")") }
        }
        // And nothing in the inventory that the builders don't make.
        let routes = CompatInventory.writeEndpoints.map(\.token).filter { $0.hasPrefix("POST ") }
        #expect(Set(routes) == Set(built.keys), "\(Set(routes).symmetricDifference(Set(built.keys)))")
    }

    @Test func theOneWriteApiPOSTMakesIsApprove() {
        #expect(WebContainer.isWritablePath(path(of: "POST /api/frames/<session>/approve-plan").replacingOccurrences(of: "/api", with: "")))
        #expect(!WebContainer.isWritablePath("/frames/\(Self.session)/resolve-input"))
        #expect(!WebContainer.isWritablePath("/request"))
    }

    @Test func theCSRFProtocolIsWhatTheWritersSend() {
        for script in [SessionWriterScript.body, PhotoUploadScript.body] {
            #expect(script.contains("operon_csrf") && script.contains("x-operon-csrf"))
        }
        let api = Repo.source("Web/WebAPI.swift")
        #expect(api.contains("operon_csrf=") && api.contains("x-operon-csrf") && api.contains("csrf_stale"))
    }

    // MARK: No new resource slips in

    @Test func everyDaemonResourceTheReadersAndWritersNameIsInTheInventory() {
        let files = ["Remote/ArtifactReader.swift", "Remote/HistoryReader.swift", "Remote/RemoteLive.swift", "Remote/RemotePhotoUpload.swift",
                     "Remote/SessionReader.swift", "Remote/SessionWriter.swift", "Remote/RemotePermissions.swift",
                     "Remote/InsightReader.swift", "Lab/LabInsights.swift",
                     "Lab/PlanApproval.swift", "Lab/FailureReason.swift", "Web/WebAPI.swift"]
        var segments = Set<String>()
        for file in files {
            segments.formUnion(ScriptLiterals.matches(#""/api/([a-z][a-z-]*)"#, in: Repo.source(file), group: 1))
        }
        let known = Set(CompatInventory.readEndpoints.map(\.token) + CompatInventory.writeEndpoints.map(\.token)).reduce(into: Set<String>()) { set, token in
            if let found = ScriptLiterals.matches(#"/api/([a-z][a-z-]*)"#, in: token, group: 1).first { set.insert(found) }
        }
        #expect(!segments.isEmpty)
        let missing = segments.subtracting(known)
        #expect(missing.isEmpty, "/api/\(missing.sorted()) is read or written but not in the inventory")
    }
}

// MARK: The command line

struct CompatCommandLineTests {
    private func status(_ extra: String = "") -> Data {
        Data("""
        {"running": true, "version": "9.8.7", "port": 4321, "pid": 777,
         "daemon": {"active_frames": 3, "active_conversations": 2, "data_dir": "/tmp/made-up-data"}\(extra)}
        """.utf8)
    }

    @Test func eachStatusFieldInTheInventoryIsTheOneTheParserReads() throws {
        let parsed = try parseCLIStatus(status(), exitStatus: 0)
        #expect(parsed.version == "9.8.7")
        #expect(parsed.port == 4321)
        #expect(parsed.pid == 777)
        #expect(parsed.dataDir == "/tmp/made-up-data")
        #expect(parsed.activeFrames == 3)
        #expect(parsed.activeConversations == 2)
        let tokens = Set(CompatInventory.commandLine.map(\.token))
        for field in ["running", "version", "port", "pid", "daemon.data_dir", "daemon.active_frames", "daemon.active_conversations",
                      "daemon.launch_context", "daemon.boot", "daemon.url_host", "daemon.require_token"] {
            #expect(tokens.contains("status.\(field)"), "\(field)")
        }
    }

    @Test func everyKeyTheParserTakesIsInTheInventory() {
        let source = Repo.source("Shared/Core/CLIStatus.swift")
        let top = ScriptLiterals.matches(#"json\["([a-z_A-Z]+)"\]"#, in: source, group: 1).subtracting(["daemon"])
        let daemon = ScriptLiterals.matches(#"daemon\["([a-z_A-Z]+)"\]"#, in: source, group: 1)
        #expect(!top.isEmpty && !daemon.isEmpty)
        let tokens = Set(CompatInventory.commandLine.map(\.token))
        // The parser also takes a camelCase spelling of each count; the
        // inventory names the snake_case one.
        func snake(_ key: String) -> String {
            key.reduce(into: "") { $0 += $1.isUppercase ? "_" + $1.lowercased() : String($1) }
        }
        for key in top { #expect(tokens.contains("status.\(snake(key))"), "status.\(key)") }
        for key in daemon { #expect(tokens.contains("status.daemon.\(snake(key))"), "status.daemon.\(key)") }
    }

    @Test func theCommandsRunAreTheOnesInTheInventory() {
        let status = Repo.source("Shared/Core/CLIStatus.swift")
        let args = ScriptLiterals.matches(#"runProcess\(\w+, \[((?:"[^"]*",?\s*)+)\]"#, in: status, group: 1)
            .filter { !$0.contains("claude-science") }
            .map { $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: ", ", with: " ") }
        #expect(Set(args) == ["status", "url"])
        let serve = ScriptLiterals.matches(#"task\.arguments = \[((?:"[^"]*",?\s*)+)\]"#, in: Repo.source("Web/DaemonController.swift"), group: 1)
            .map { $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: ", ", with: " ") }
        #expect(serve == ["serve --no-browser --detached"])
        let tokens = Set(CompatInventory.commandLine.map(\.token))
        #expect(tokens.isSuperset(of: ["url", "serve --no-browser --detached", "claude-science"]))
        #expect(CompatInventory.commandLine.contains { $0.token.hasPrefix("status.") })
    }

    @Test func theToolIsLookedForWhereTheInventorySays() {
        let source = Repo.source("Shared/Core/CLIStatus.swift")
        for place in [".local/bin", ".claude-science/bin", "/opt/homebrew/bin", "/usr/local/bin"] {
            #expect(source.contains(place))
        }
    }

    @Test func theCommandsOnlyEverRunReadOnlyOrStartingOnes() {
        // Nothing in the inventory stops, restarts or reconfigures the daemon.
        for item in CompatInventory.commandLine {
            #expect(!item.token.contains("stop") && !item.token.contains("restart") && !item.token.contains("--port") && !item.token.contains("--data-dir"))
        }
    }

    @Test func aStatusWithoutRunningIsAFailureAndFalseIsNotRunning() {
        #expect(throws: ScienceError.self) { try parseCLIStatus(Data(#"{"version":"9.8.7"}"#.utf8), exitStatus: 0) }
        #expect(throws: ScienceError.daemonNotRunning) { try parseCLIStatus(Data(#"{"running":false}"#.utf8), exitStatus: 0) }
    }
}

// MARK: The database

/// A made-up database holding exactly the tables and columns the inventory
/// lists (less one, if asked): the least the queries should need.
private struct InventoryDatabase {
    let dir: URL
    let url: URL

    init(omitting omitted: String? = nil, withOptional: Bool = true) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-compat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("made-up.db")
        var sql = ""
        for (table, required, optional) in CompatInventory.schemaTables {
            let columns = (required + (withOptional ? optional : [])).filter { "\(table).\($0)" != omitted }
            sql += "CREATE TABLE \(table)(\(columns.joined(separator: ", ")));\n"
        }
        let make = Process()
        make.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        make.arguments = [url.path]
        let input = Pipe()
        make.standardInput = input
        make.standardOutput = FileHandle.nullDevice
        try make.run()
        input.fileHandleForWriting.write(Data(sql.utf8))
        try input.fileHandleForWriting.close()
        make.waitUntilExit()
        #expect(make.terminationStatus == 0)
    }

    func remove() { try? FileManager.default.removeItem(at: dir) }

    /// Runs every query the app makes of the daemon's database. Throws at the
    /// first that can't be prepared.
    func runEveryQuery() throws {
        let frame = "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5"
        let cursor = BrowseCursor(updatedMs: 1, id: frame)
        _ = try fetchRecentFrames(db: url)
        for (byTime, byStatus) in [(true, true), (false, false)] {
            _ = try runReadOnlyQuery(db: url, sql: sessionsPollSQL(byTime: byTime, byStatus: byStatus), arguments: [.integer(5)])
        }
        _ = try fetchDailySessionCounts(db: url, days: 30)
        _ = try fetchDailyMessageCounts(db: url, days: 30)
        _ = try fetchDailyTokenCounts(db: url, days: 30)
        _ = try fetchProjectNames(db: url)
        _ = try fetchProjects(db: url)
        _ = try fetchProjectSessions(db: url, project: "proj_a", after: cursor, search: "x")
        _ = try fetchProjectSessions(db: url, project: "proj_a", after: nil, search: nil)
        _ = try fetchRecentSessions(db: url, after: cursor)
        _ = try fetchRecentSessions(db: url, after: nil)
        _ = try fetchSession(db: url, id: frame)
        _ = try fetchSessionsNamed(db: url, words: ["x", "y"], limit: 5)
        _ = try fetchSessionByIntent(db: url, project: "proj_a", intent: "0b7c2f4e-1a2b-4c3d-8e9f-a0b1c2d3e4f5")
        // Find any figure: a name, a kind word, a day word, and the window's chip and pill.
        let find = FindQuery.parse("x figures today", kind: .table, project: "proj_a")!
        _ = try fetchFiles(db: url, query: find)
        _ = try fetchFileCount(db: url)
    }
}

struct CompatSchemaTests {
    @Test func theInventorysColumnsAreEnoughForEveryQuery() throws {
        for withOptional in [true, false] {
            let database = try InventoryDatabase(withOptional: withOptional)
            defer { database.remove() }
            try database.runEveryQuery()
        }
    }

    @Test func everyColumnInTheInventoryIsOneSomeQueryNeeds() throws {
        for (table, required, _) in CompatInventory.schemaTables {
            for column in required {
                let database = try InventoryDatabase(omitting: "\(table).\(column)")
                defer { database.remove() }
                #expect(throws: (any Error).self, "\(table).\(column) is listed but no query needs it") {
                    try database.runEveryQuery()
                }
            }
        }
    }

    @Test func theDiagnosticsStepChecksTheInventorysColumns() throws {
        let whole = try InventoryDatabase()
        defer { whole.remove() }
        #expect(Diagnose.schemaLines(db: whole.url) == [
            "✓ Table frames: all 18 columns",
            "✓ Table projects: all 2 columns",
            "✓ Table frame_blobs: all 3 columns",
            "✓ Table frame_messages: all 2 columns",
            "✓ Table artifacts: all 8 columns",
            "✓ Table artifact_versions: all 6 columns",
        ])
        // The optional column missing is a note, not a problem.
        let without = try InventoryDatabase(withOptional: false)
        defer { without.remove() }
        let lines = Diagnose.schemaLines(db: without.url)
        #expect(lines.count == 6 && lines.dropFirst().first == "✓ Table projects: all 2 columns (archived_at is optional and isn't there)")
    }

    @Test func aMissingColumnIsNamedAndSoIsAMissingTable() throws {
        // Columns the old step never looked for.
        let noKind = try InventoryDatabase(omitting: "frames.conversation_type")
        defer { noKind.remove() }
        #expect(Diagnose.schemaLines(db: noKind.url).first == "✗ Table frames: missing conversation_type")
        let noBody = try InventoryDatabase(omitting: "frame_blobs.body")
        defer { noBody.remove() }
        #expect(Diagnose.schemaLines(db: noBody.url).dropFirst(2).first == "✗ Table frame_blobs: missing body")

        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("bench-compat-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: empty) }
        FileManager.default.createFile(atPath: empty.path, contents: nil)
        // A database with no tables at all: every table is missing.
        #expect(Diagnose.schemaLines(db: empty) == [
            "✗ Table frames: missing", "✗ Table projects: missing", "✗ Table frame_blobs: missing", "✗ Table frame_messages: missing",
            "✗ Table artifacts: missing", "✗ Table artifact_versions: missing",
        ])
    }

    @Test func theOptionalColumnIsNotRequiredAndUsedWhenThere() throws {
        let optional = CompatInventory.schemaTables.flatMap { entry in entry.optional.map { "\(entry.table).\($0)" } }
        #expect(optional == ["projects.archived_at"])
    }

    @Test func theTablesAreTheOnesTheDiagnosticsStepChecks() {
        let tables = CompatInventory.schemaTables
        #expect(tables.map(\.table) == ["frames", "projects", "frame_blobs", "frame_messages", "artifacts", "artifact_versions"])
        #expect(tables.first { $0.table == "frames" }?.required.count == 18)
        // What the step used to check is still checked.
        let frames = Set(tables.first { $0.table == "frames" }?.required ?? [])
        #expect(frames.isSuperset(of: ["id", "project_id", "name", "status", "created_at", "updated_at", "completed_at",
                                        "last_user_message_at", "root_frame_id", "parent_frame_id", "input_tokens",
                                        "output_tokens", "is_hidden", "output_data"]))
        // And what the queries read that it did not: the session filter, the
        // browse lists and the intent lookup.
        #expect(frames.isSuperset(of: ["conversation_type", "agent_name", "task_summary", "input_data"]))
    }

    @Test func theWordsStoredInsideTheDatabaseAreInTheInventoryAndWhenUsed() {
        let stored = CompatInventory.database.filter { $0.check != .live }
        #expect(stored.contains { $0.token.hasPrefix("output_data.pending_input_requests") })
        #expect(stored.contains { $0.token.hasPrefix("msg_json.") })
        #expect(stored.allSatisfy { $0.isWhenUsed })
    }
}

// MARK: The call sites

/// The places that note a change, and the places that use the inventory, are
/// still there. They run against a live web view, which no test loads, so this
/// reads the source for the call that links each to the pure part tested above.
struct CompatWiringTests {
    private func contains(_ file: String, _ text: String) -> Bool {
        Repo.source(file).contains(text)
    }

    @Test func theReadersNoteWhatTheyFind() {
        #expect(contains("Usage/PlanUsageModel.swift", "try Self.parseNoting(data)"))
        #expect(contains("Context/ContextModel.swift", "try TokenSeries.decodeNoting(data)"))
        #expect(contains("Web/PageTabs.swift", "PageTabsOutcome.read(value)"))
        #expect(contains("Lab/PlanApproval.swift", "dependencies.breadcrumbs.record(.planFrameNotUnderstood)"))
        #expect(contains("Lab/FailureReason.swift", "if let miss = FailureCheck.miss(frame) { dependencies.breadcrumbs.record(miss) }"))
    }

    @Test func theSignInFallbackNotesNothing() {
        // A 401 with no Sign in card falls back to a fresh code by design
        // (DESIGN.md, Daemon and sign-in): an ordinary event, not a change.
        #expect(!contains("Web/WebContainer.swift", "CompatBreadcrumbs"))
        #expect(!CompatMiss.allCases.contains { $0.feature == .signIn })
    }

    @Test func theSignInRecoveryAndTheLookShareOneFinder() {
        #expect(SignInScript.press.contains("benchFindSignIn()") && SignInScript.look.contains("benchFindSignIn()"))
        #expect(SignInScript.press.contains(SignInScript.finder) && SignInScript.look.contains(SignInScript.finder))
        #expect(contains("Web/WebContainer.swift", "SignInScript.press"))
    }

    @Test func theTabLookAndTheCommandsShareOneReader() {
        #expect(PageTabsScript.probe.contains(PageTabsScript.reader))
        #expect(PageTabsScript.body.contains(PageTabsScript.reader))
    }

    @Test func diagnosticsUsesTheInventoryTheVersionAndTheProbes() {
        let diagnose = Repo.source("App/Diagnose.swift")
        #expect(diagnose.contains("CompatInventory.schemaTables"))
        #expect(diagnose.contains("ScienceVersion.lines(running: status.version)"))
        // Both ways the status can fail still show the version Capsid was checked with.
        #expect(diagnose.components(separatedBy: "ScienceVersion.checkedOnlyLine()").count == 3)
        #expect(diagnose.contains("CompatProbes.run("))
        #expect(diagnose.contains("CompatReport.whenUsedLines()"))
        #expect(diagnose.contains("breadcrumbs.line()"))
        // And the window runs the page part after the first.
        #expect(diagnose.contains("await Diagnose.pageReport()"))
    }
}
