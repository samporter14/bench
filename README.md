# Bench

A small native Mac app for Claude Science: its web
UI in one window, with nothing opening in Safari, and a floating Liquid Glass
panel in the corner of the screen that plays little lab scenes while a session
works and tells you when one needs you.

Unofficial, a personal project, and not affiliated with or endorsed by
Anthropic. It talks only to the Claude Science daemon on your own Mac.

## What it does

- **One window.** Claude Science's web UI in a single WKWebView. Pop-outs,
  sign-in pop-ups, downloads, file uploads, the microphone and notifications
  are all handled inside the app. Other sites open in an in-app browser
  window, which has an "Open in Safari" button.
- **Scenes panel.** While a session works, a glass panel in the bottom-right
  corner plays one of 474 animated lab scenes. When a session needs your
  input, a card appears there that opens that session. Size, categories and
  individual scenes can be picked in Settings → Scenes.

It's a work in progress: `TESTING.md` says which of these have been checked
live so far.
- **Title-bar readouts.** The toolbar shows how full the current session's
  context is and how much of your plan is left, with when it resets. Click
  either one for details and your activity graph.

## Requirements

- macOS 26 or later
- Xcode 27 (Swift 6.4)
- Claude Science installed, with its `claude-science` command on your PATH
  or in `~/.local/bin`

## Build

```sh
Scripts/build-app.sh --open
```

This builds `build/Bench.app` (release, ad-hoc signed) and opens it. Bench
starts the Claude Science daemon if it isn't running and signs in with a
one-time link from `claude-science url`. Close any Claude Science browser tab
first, because Claude Science runs in one tab at a time.

## Layout

- `DESIGN.md` is the spec: the look, where the glass goes, the routing
  policy, and a testing checklist. `TESTING.md` logs what has been checked
  live.
- `Sources/Bench/Shared` and `Resources/AppIcon.icon` are copies from the
  Science Status droplet, where the scenes are written.
  `Scripts/sync-shared.sh` refreshes them.
