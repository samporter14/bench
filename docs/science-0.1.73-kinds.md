# Claude Science 0.1.73: what is new in `pending_input_requests`

Read 2026-11-19 from the running install, not from the app bundle:
`/Applications/Claude Science.app` is still 0.1.70 (the shell; bundle id
`com.anthropic.operon`), while `claude-science status` reports the daemon as
**0.1.73**. The strings below come from the daemon binary
`~/.claude-science/bin/claude-science` (compared with the 0.1.72 binary kept
beside it as `claude-science.before-catalog-fix-0.1.72`) and from the web UI
in `~/.claude-science/runtime/0.1.73-release/web-dist/assets/index-*.js`.
The database was not read; no credential value was looked at.

## The daemon's table of kinds

The daemon's registry of request kinds (each `{mode, defaultResult, scopes, …}`)
in 0.1.73:

`ask`, `network`, `host`, `host_delete`, `artifact_delete`, `mcp_tool`,
`customize_mutation`, `local_exec`, `remote_exec`, `remote_read`,
`credential_access`, `byoc_submit`, `byoc_kernel`, `infer_submit`,
`managed_endpoint_register`, `provider_discovery`, `skill_license`,
`contact_email`, `credential_request`, `ssh_password`, `set_goal`,
`usage_checkpoint`, `grant_scan`, **`share_save`**.

0.1.72 has the same list without `share_save`. So **one new kind**. The two
other release-note features are flags on existing kinds, not kinds.

## (c) Saving into a Read & write folder: `share_save` (new kind)

- Registry: `share_save: {mode: "live", capPerRoot: 10, defaultResult: {approved: false}, scopes: []}`.
- Raised by the daemon's save path with `frameId`, `rootFrameId`, `projectId`,
  `userId`: **no `tool_id`**.
- UI: kind label "Host files", card `share-save-*`.
- Fields (names only): `what` (`"folder"` when it asks to make a folder),
  `path`, `share` (the granted folder), `source`, `bytes`, `sha256`,
  `replaces` (`{bytes, sha256, rights}`), `later` (`{path, what: "repo" | "folder"}`:
  the once-per-session offer for source files in a git repo or granted
  folder), `reasons` (`[{reason, path}]`), `created_folders`, `text`,
  `previous_text`, `text_note` (`too_long` | `binary` | `encoding`), `unshown`
  (`{kind, opening}`).
- Headlines: "Save this file into your folder?", "Replace this file?",
  "Make this folder?", "Allow Claude to save source files in this repo/folder?".
- Answers: **Don't save** / **Don't make it** sends `{approved: false}`
  (action `deny`). **Save it** sends `{approved: true, shown: {path, sha256}}`,
  and **Allow in this repo/folder** adds `shown.later = later.path`. The daemon
  refuses an allow whose `shown` doesn't match what the card showed ("This
  page is older than the app and can't show what would be saved."). Allow-once
  exists, but only with `shown`. No scopes.

## (a) and (b) The saved-key check: `key_check_held` on existing kinds

New in 0.1.73 (absent from the 0.1.72 binary). When code would use a saved
key (an OpenAlex key, a GitHub token…), the daemon holds the card even with a
saved allow and even in auto mode, and sets on the request:

- `key_check_held: true`
- `key_check_reason`: a sentence (shown on the card as the check's reason).
- `key_check_cell` (`credential_access` only): `{code}`, the cell that would read the key.
- `scopes` is emptied for `local_exec` and `credential_access`: the card is
  once only.

Kinds: `credential_access` (feature (a): the Credentials card, kind label
"Credentials", "Agent wants to read credential: <name>"), and `local_exec`
(feature (b): the code that uses a key).

**Timeout.** A held card with `key_check_held` is denied after **10 minutes**
(`600000` ms, checked every 30 s) with no attention from a focused Claude
Science page (the person is in another session or app). The settle is
`{approved: false, timedOut: true, via: "unwatched"}`, and Claude is told not
to try another way and to raise it again when the person is back.

Answers: the generic card. Allow sends `{approved: true}` plus
`code_shown: true` when there is a `key_check_cell`; Deny sends
`{approved: false}` (action `deny`).

## Auto mode's own held steps (not new)

`local_exec` cards held by auto mode's classifier carry `auto_mode_reason`
(the classifier's sentence), `auto_mode_check_failed`, `auto_mode_paused` and
`auto_mode_verdict` (`{model, decision}`, decisions `approved`, `blocked`,
`unavailable`, `gate_closed`). These were already in 0.1.72. The same
10-minute denial applies to them only when the organisation's auto-mode
config sets both `denyUnwatchedHeldSteps` and `pauseAfterBlocks`.

## What Capsid does with them (1.1.7)

| What | Capsid's waiting reason | Phone and Mac card |
|---|---|---|
| `share_save` | Save to folder: "Wants to save a file into your folder" | Open on Mac (no `tool_id`, and an allow needs `shown`) |
| `key_check_held` on any request (first in the queue) | Saved-key check: "Auto mode's check wants your OK. Skipped after 10 minutes" | Deny only, never Allow |
| `credential_access` | Credentials: "Wants to use a saved key" | Deny (as before) |
| `local_exec` | Run code: "Wants to run code" | as before, but Deny only (never Allow) when auto mode held it (`auto_mode_reason` a string, or `auto_mode_paused` true) |

Only booleans and plain fields are read: never `key_check_reason`,
`key_check_cell`, `auto_mode_reason`, `text`, `previous_text`, `reasons` or
`unshown`.

## Save All's names

Claude Science 0.1.73 renames files in a zip it hands out and writes
`renamed_files.txt` beside them. A name that starts with a dot, or matches one
of 116 patterns of files that programs load by themselves (`CLAUDE.md`,
`AGENTS.md`, `nextflow.config`, `latexmkrc`, `matplotlibrc`, `activate`,
`compose.y*ml`, `*.bazelrc`…, matched case-insensitively with `*` as any
run), gets `_` in front (`.Rprofile` → `_.Rprofile`); if that still matches,
`.txt` is added; `: < > | ? *` become `_`. Capsid's Save All follows the same
rule for the "_" and the ".txt" (see DESIGN.md, Save All…); its own character
rule is unchanged (`/`, `:` and control characters become `_`, which is what a
Mac folder refuses).
