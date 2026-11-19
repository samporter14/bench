// Science0173Tests.swift — what Capsid 1.1.7 reads of Claude Science 0.1.73's
// new requests (docs/science-0.1.73-kinds.md): the `share_save` kind, the
// saved-key check's `key_check_held` flag, and auto mode's held code. The
// projection is the page's own JavaScript, run in JavaScriptCore; every frame,
// path and line of code is invented, and the fields Capsid must never pass on
// hold "SECRET".
import Foundation
import Testing
@testable import Bench

private let root = ReaderFixture.root

private func json(_ value: Any) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])) ?? Data(),
           as: UTF8.self)
}

private func request(_ kind: String, _ fields: [String: Any] = [:], tool: Any = "tool-1") -> [String: Any] {
    var made: [String: Any] = ["kind": kind, "requestId": "req-1", "tool_id": tool, "frameId": root, "rootFrameId": root,
                               "projectId": "proj-made-up", "createdAt": "2026-11-19T16:30:00Z", "mode": "live"]
    for (key, value) in fields { made[key] = value }
    return made
}

/// The page's projection of one request alone on the root, as text and as Swift reads it.
private func projected(_ made: [String: Any]) -> (text: String, request: PermissionRequest?) {
    let frame = ReaderFixture.frame(status: "processing", context: "null",
                                    output: json(["pending_input_requests": [made]]))
    let trace = json(["id": root, "parent_frame_id": NSNull(), "status": "processing", "children": [Any]()])
    let script = PageScript(PermissionScript.reading)
    let out = script.callJSON("benchProjectPermission", [frame, trace, json(root)]) ?? "<exception>"
    #expect(script.exception == nil)
    guard out != "null", let object = try? JSONSerialization.jsonObject(with: Data(out.utf8)) else { return (out, nil) }
    return (out, PermissionRequest(object: object))
}

private func described(_ made: [String: Any]) -> RemoteAPI.Permission? {
    projected(made).request.map { RemotePermission.describe($0, actionsOn: true) }
}

// MARK: Waiting reasons

struct Science0173WaitingReasonTests {
    @Test func theNewSignalsHaveTheirOwnReasons() {
        #expect(WaitingReason(signal: "share_save") == .saveFile)
        #expect(WaitingReason(signal: "key_check_held") == .keyCheck)
        #expect(WaitingReason(signal: "credential_access") == .credentials)
        #expect(WaitingReason(signal: "local_exec") == .code)
        // Kinds Capsid still has no words of its own for stay "Waiting for you".
        #expect(WaitingReason(signal: "usage_checkpoint") == .other)
        #expect(WaitingReason(signal: nil) == .other)
    }

    @Test func theSavedKeyCheckSaysItIsSkippedAfterTenMinutes() {
        #expect(WaitingReason.keyCheck.sentence == "Wants your OK to use a saved key. Skipped after 10 minutes")
        #expect(WaitingReason.keyCheck.shortLabel == "Safety check")
        #expect(WaitingReason.saveFile.sentence == "Wants to save a file into your folder")
        #expect(WaitingReason.credentials.sentence == "Wants to use a saved key")
        #expect(WaitingReason.code.sentence == "Wants to run code")
    }

    @Test func everyNewReasonIsAPermissionWithThePadlock() {
        for reason in [WaitingReason.code, .credentials, .keyCheck, .saveFile] {
            #expect(reason.glyph == .permission, "\(reason)")
            #expect(reason.systemImage == "lock.fill", "\(reason)")
            #expect(CompanionNeedRow.kind(of: reason) == .request, "\(reason)")
        }
        // No sentence has an em dash, in Capsid's plain voice.
        for reason in WaitingReason.allCases { #expect(!reason.sentence.contains("—"), "\(reason)") }
    }

    @Test func aPushWithNamesOffSaysWhatKindOfThingWaits() {
        #expect(PushRules.needsYouBody(.keyCheck) == "A session needs you: an OK to use a saved key, skipped after 10 minutes")
        #expect(PushRules.needsYouBody(.saveFile) == "A session needs you: permission to save a file into a folder")
        #expect(PushRules.needsYouBody(.credentials) == "A session needs you: permission to use a saved key")
        #expect(PushRules.needsYouBody(.code) == "A session needs you: permission to run code")
    }

    /// The poll reads the flag, not the kind, when the saved-key check holds
    /// the first request; never the check's reason or cell.
    @Test func theSessionsPollReadsTheSavedKeyCheckByItsFlag() throws {
        let db = try MadeUpDatabase()
        defer { db.remove() }
        let ids = (1...5).map { "00000000-0000-4000-8000-0000000000b\($0)" }
        for (n, id) in ids.enumerated() {
            try db.frame(id, status: "awaiting_user_response", updated: 1_791_800_000_000 + Int64(n))
        }
        try db.run("""
            UPDATE frames SET output_data = '{"pending_input_requests":[{"kind":"local_exec","key_check_held":true,"key_check_reason":"SECRET","key_check_cell":{"code":"SECRET"}}]}'
                WHERE id = '\(ids[0])';
            UPDATE frames SET output_data = '{"pending_input_requests":[{"kind":"credential_access","key_check_held":true}]}'
                WHERE id = '\(ids[1])';
            UPDATE frames SET output_data = '{"pending_input_requests":[{"kind":"share_save","path":"/x"}]}'
                WHERE id = '\(ids[2])';
            UPDATE frames SET output_data = '{"pending_input_requests":[{"kind":"credential_access","key_check_held":"true"}]}'
                WHERE id = '\(ids[3])';
            UPDATE frames SET output_data = '{"pending_input_requests":[{"kind":"network"},{"kind":"local_exec","key_check_held":true}]}'
                WHERE id = '\(ids[4])';
            """)
        let rows = try fetchRecentFrames(db: db.url)
        let signal = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.waitingSignal) })
        #expect(signal[ids[0]] == "key_check_held")
        #expect(signal[ids[1]] == "key_check_held")
        #expect(signal[ids[2]] == "share_save")
        #expect(signal[ids[3]] == "credential_access", "only a JSON true is the flag")
        #expect(signal[ids[4]] == "network", "only the first request is read")
        #expect(!rows.contains { ($0.waitingSignal ?? "").contains("SECRET") })
    }
}

// MARK: The phone and the Mac's card

struct Science0173PermissionTests {
    @Test func aSaveIntoAFolderIsShownAndOnlyOpenedOnTheMac() throws {
        let cases: [([String: Any], String, String)] = [
            (["path": "/Users/made-up/out/table.csv"], "Wants to save /Users/made-up/out/table.csv", "Into a folder you let Claude write to."),
            (["path": "/Users/made-up/out/table.csv", "replaces": ["bytes": 3, "sha256": "SECRET-sha"]],
             "Wants to replace /Users/made-up/out/table.csv", "A file in a folder you let Claude write to."),
            (["path": "/Users/made-up/out/new", "what": "folder"], "Wants to make the folder /Users/made-up/out/new",
             "In a folder you let Claude write to."),
            (["path": "/Users/made-up/repo/a.py", "later": ["path": "/Users/made-up/repo", "what": "repo"]],
             "Wants to save source files in this repo", "For the rest of the session. Starting with /Users/made-up/repo/a.py."),
            (["path": "/Users/made-up/src/a.py", "later": ["path": "/Users/made-up/src", "what": "folder"]],
             "Wants to save source files in this folder", "For the rest of the session. Starting with /Users/made-up/src/a.py."),
        ]
        for (fields, title, detail) in cases {
            // As the daemon raises it: no `tool_id`.
            let permission = try #require(described(request("share_save", fields, tool: NSNull())), "\(fields)")
            #expect(permission.title == title)
            #expect(permission.detail == detail)
            #expect(!permission.canAllow && !permission.canDeny, "\(title)")
            #expect(permission.why != nil)
            #expect(permission.code == nil)
        }
        // With a `tool_id` it is still never answered from here.
        let withTool = try #require(described(request("share_save", ["path": "/Users/made-up/out/t.csv"])))
        #expect(!withTool.canAllow && !withTool.canDeny)
        #expect(withTool.why == "Look at the file on your Mac before it's saved there.")
        #expect(PermissionKind.shareSave.canBeDenied == false)
    }

    @Test func aSaveWithoutAPathCantBeShown() throws {
        let permission = try #require(described(request("share_save", [:])))
        #expect(permission.title == "Wants your permission")
        #expect(!permission.canAllow && !permission.canDeny)
    }

    @Test func aSavesFileTextReasonsAndHashesNeverLeaveThePage() {
        let made = request("share_save", [
            "path": "/Users/made-up/out/t.csv", "share": "/SECRET-share", "source": "/SECRET-source", "bytes": 12,
            "sha256": "SECRET-sha", "text": "SECRET-text", "previous_text": "SECRET-previous", "text_note": "SECRET-note",
            "reasons": [["reason": "SECRET-reason", "path": "/SECRET-reason-path"]], "created_folders": ["/SECRET-made"],
            "unshown": ["kind": "SECRET-kind", "opening": "SECRET-opening"],
            "replaces": ["bytes": 3, "sha256": "SECRET-old-sha", "rights": true],
            "later": ["path": "/SECRET-later", "what": "repo"],
        ])
        let (text, parsed) = projected(made)
        #expect(!text.contains("SECRET"), "\(text)")
        #expect(parsed?.save == .repo)
        #expect(parsed?.target == "/Users/made-up/out/t.csv")
    }

    @Test func codeTheSavedKeyCheckHoldsIsNeverAllowedFromThePhoneButCanBeDenied() throws {
        let made = request("local_exec", ["tool": "python", "code": "print(1)", "key_check_held": true,
                                          "key_check_reason": "SECRET-why", "key_check_cell": ["code": "SECRET-cell"], "scopes": [String]()])
        let (text, parsed) = projected(made)
        #expect(!text.contains("SECRET"))
        #expect(parsed?.held == .key)
        let permission = try #require(described(made))
        #expect(!permission.canAllow)
        #expect(permission.canDeny)
        #expect(permission.why == "This would use a saved key. Look at it on your Mac to allow it.")
        #expect(permission.title == "Run Python code that uses a saved key")
        #expect(permission.detail == "Skipped after 10 minutes with no answer.")
        // The Mac's card holds to the same table.
        let onMac = RemotePermission.decideOnMac(try #require(parsed))
        #expect(!onMac.canAllow && onMac.canDeny)
        #expect(onMac.why == "This would use a saved key. Open it in Capsid to allow it.")
    }

    @Test func aCredentialTheSavedKeyCheckHoldsCanOnlyBeDenied() throws {
        let made = request("credential_access", ["name": "OPENALEX_API_KEY", "key_check_held": true,
                                                 "key_check_reason": "SECRET-why", "key_check_cell": ["code": "SECRET-cell"]])
        let (text, _) = projected(made)
        #expect(!text.contains("SECRET"))
        let permission = try #require(described(made))
        #expect(!permission.canAllow && permission.canDeny)
        #expect(permission.title == "Wants to use the saved credential OPENALEX_API_KEY")
        #expect(permission.detail.hasSuffix("Skipped after 10 minutes with no answer."))
        #expect(permission.why == "This would use a saved key. Look at it on your Mac to allow it.")
    }

    @Test func onlyAJSONTrueIsTheSavedKeyFlag() throws {
        for flag: Any in ["true", 1, NSNull(), false] {
            let made = request("local_exec", ["tool": "python", "code": "print(1)", "key_check_held": flag])
            let permission = try #require(described(made), "\(flag)")
            #expect(permission.canAllow, "\(flag)")
        }
    }

    @Test func codeAutoModeHeldIsNeverAllowedFromThePhone() throws {
        for fields: [String: Any] in [["auto_mode_reason": "SECRET-classifier"], ["auto_mode_paused": true],
                                      ["auto_mode_reason": "SECRET-x", "auto_mode_check_failed": true]] {
            let made = request("local_exec", fields.merging(["tool": "python", "code": "print(1)"]) { $1 })
            let (text, parsed) = projected(made)
            #expect(!text.contains("SECRET"))
            #expect(parsed?.held == .auto)
            let permission = try #require(described(made))
            #expect(!permission.canAllow && permission.canDeny, "\(fields)")
            #expect(permission.why == "Auto mode's check held this code. See why on your Mac.")
            #expect(permission.detail == "Auto mode's check held it for your review.")
        }
        // auto_mode_paused false is no hold.
        let plain = try #require(described(request("local_exec", ["tool": "python", "code": "print(1)", "auto_mode_paused": false])))
        #expect(plain.canAllow)
    }

    @Test func aHeldAllowIsRefusedWhenAnswered() throws {
        let made = request("local_exec", ["tool": "python", "code": "print(1)", "key_check_held": true])
        let head = try #require(projected(made).request)
        let fresh = SessionProjection(status: "processing", agentName: "made-up-agent", projectID: "proj-1", turns: [], permission: head)
        let allow = PermissionDecide.decide(.permission(id: "req-1", allow: true, kind: "local_exec"), session: root, fresh: fresh)
        guard case .answer(let result) = allow else { Issue.record("an allow was written: \(allow)"); return }
        #expect(result.result == .unavailable)
        let deny = PermissionDecide.decide(.permission(id: "req-1", allow: false, kind: "local_exec"), session: root, fresh: fresh)
        guard case .write = deny else { Issue.record("a deny was not written: \(deny)"); return }
    }

    @Test func swiftRefusesAHeldOrSaveWordItDoesntKnow() {
        let base: [String: Any] = ["requestId": "req-1", "toolId": "tool-1", "mode": "live", "kind": "local_exec", "frame": root,
                                   "chain": [root], "toolIdShared": false, "shape": true, "readOnly": false, "sharedEnv": false]
        #expect(PermissionRequest(object: base) != nil, "absent is none")
        #expect(PermissionRequest(object: base.merging(["held": "key"]) { $1 })?.held == .key)
        #expect(PermissionRequest(object: base.merging(["held": "maybe"]) { $1 }) == nil)
        #expect(PermissionRequest(object: base.merging(["held": true]) { $1 }) == nil)
        #expect(PermissionRequest(object: base.merging(["save": "zip"]) { $1 }) == nil)
        #expect(PermissionRequest(object: base.merging(["save": "replace"]) { $1 })?.save == .replace)
    }
}

// MARK: Save All's names

struct ShelfFolderNameTests {
    @Test func namesProgramsPickUpGetAnUnderscoreAndKeepTheirDots() {
        #expect(ShelfFileName.forFolder(".Rprofile") == ("_.Rprofile", true))
        #expect(ShelfFileName.forFolder(".envrc") == ("_.envrc", true))
        #expect(ShelfFileName.forFolder("CLAUDE.md") == ("_CLAUDE.md", true))
        #expect(ShelfFileName.forFolder("claude.MD") == ("_claude.MD", true), "without regard to case")
        #expect(ShelfFileName.forFolder("nextflow.config") == ("_nextflow.config", true))
        #expect(ShelfFileName.forFolder("docker-compose.prod.yaml") == ("_docker-compose.prod.yaml", true))
        #expect(ShelfFileName.forFolder("my.bazelrc") == ("_my.bazelrc.txt", true), "still a *.bazelrc with _ in front")
        #expect(ShelfFileName.forFolder("renamed_files.txt") == ("_renamed_files.txt", true))
        #expect(ShelfFileName.forFolder("CLAUDE.md.") == ("_CLAUDE.md.", true), "trailing dots don't hide it")
        #expect(ShelfFileName.forFolder("CLA\u{200B}UDE.md").renamed, "nor a zero-width space")
    }

    @Test func aNameThatStillMatchesAfterTheUnderscoreGetsTxt() {
        // "-theme.auto.conf" still matches "*-theme.auto.conf" with "_" in front: ".txt" after.
        #expect(ShelfFileName.forFolder("quarto-x.yml") == ("quarto-x.yml", false))
        #expect(ShelfFileName.forFolder("_quarto.yml") == ("__quarto.yml", true))
        #expect(ShelfFileName.forFolder("quarto.yml").renamed == false)
        let tricky = ShelfFileName.forFolder("-theme.auto.conf")
        #expect(tricky.renamed && !ShelfFileName.isAutoLoaded(tricky.name), "\(tricky.name)")
    }

    @Test func ordinaryNamesAreAsBefore() {
        for name in ["report.md", "figure 2.png", "Rprofile", "notes", "a/b:c.txt", "CLAUDE.md.bak", "activate.sh"] {
            #expect(ShelfFileName.forFolder(name) == (ShelfFileName.sanitized(name), false), "\(name)")
        }
    }

    @Test func theListIsClaudeSciences() {
        #expect(ShelfFileName.autoLoaded.count == 116)
        #expect(ShelfFileName.autoLoaded.first == "renamed_files.txt")
    }

    @Test func theNoteSaysWhyAndListsEachFile() {
        let note = ShelfFileName.renamedNoteText([(".Rprofile", "_.Rprofile"), ("CLAUDE.md", "_CLAUDE 2.md")])
        #expect(note.hasPrefix("Some of these files were saved under new names."))
        #expect(note.hasSuffix(".Rprofile → _.Rprofile\nCLAUDE.md → _CLAUDE 2.md\n"))
        #expect(!note.contains("—"))
    }
}

// MARK: Diagnostics

struct Science0173CompatTests {
    @Test func capsidWasCheckedWith0173() {
        #expect(CompatInventory.checkedWith == "0.1.73")
        #expect(ScienceVersion.relation(running: "0.1.73") == .same)
    }

    @Test func theNewRequestFieldsAreInTheInventory() {
        let tokens = CompatInventory.database.map(\.token)
        #expect(tokens.contains { $0.contains("key_check_held") })
        #expect(tokens.contains { $0.contains("share_save") })
        #expect(tokens.contains { $0.contains("auto_mode_reason") })
    }
}
