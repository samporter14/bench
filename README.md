# Bench

**Claude Science as a real Mac app.**

[**Download Bench for Mac**](https://github.com/samporter14/bench/releases/latest/download/Bench.zip): 3 MB, for Apple silicon on macOS 26

## Why Bench

- **Tiny and light.** A 3 MB download, with no Electron and no bundled
  browser. It uses the WebKit already built into macOS. Bench itself idles at
  0% CPU and about 50 MB of memory, and the page runs in WebKit like a Safari
  tab.
- **Truly Mac native.** Written in Swift with SwiftUI and AppKit: Liquid
  Glass, a real toolbar, menus, keyboard shortcuts, Settings (⌘,) and Find
  (⌘F).
- **Nothing collected.** No Bench account, no analytics, no telemetry, no
  update checks. Bench only talks to Claude Science running on your own Mac,
  and other sites open only when you click a link. It reads Claude Science's
  session list in read-only mode and saves nothing but its own settings.
- **One home for Claude Science.** No lost browser tab. Nothing opens in
  Safari unless you ask, and pop-outs and sign-in windows stay in the app.
- **Know when it needs you.** While a session works, one of 474 little
  animated lab scenes plays in a glass panel in the corner of your screen.
  When a session needs your input, a card there takes you straight to it.
- **Usage at a glance.** The title bar shows how full your session's context
  is and how much of your plan is left, with a countdown to when it resets.

## Install

You need a Mac with Apple silicon (M1 or later) on macOS 26, with
Claude Science installed.

1. [Download Bench.zip](https://github.com/samporter14/bench/releases/latest/download/Bench.zip)
   and open it.
2. Drag **Bench** into your **Applications** folder, and open it from there
   rather than from Downloads.
3. Open Bench. The first time, macOS blocks it because it isn't from the App
   Store or a registered developer. Click **Done**, then go to **System
   Settings → Privacy & Security**, scroll down, and click **Open Anyway**
   next to Bench. You only do this once.
4. Close any Claude Science browser tab first, because Claude Science runs
   in one tab at a time. Bench starts Claude Science if it isn't running and
   signs you in.

If Bench ever opens on a "Sign in" screen, click **Sign in**.

## Build it yourself

With Xcode 27 installed, run this from the repo's folder:

```sh
Scripts/build-app.sh --open
```

It builds `build/Bench.app` and opens it.

## Notes

- Bench is a personal project, unofficial, and not affiliated with or
  endorsed by Anthropic. It's a work in progress: `TESTING.md` says what has
  been checked live so far.
- `DESIGN.md` is the spec: the look, where the glass goes, and how links are
  routed.
- `Sources/Bench/Shared` and `Resources/AppIcon.icon` are copies from the
  Science Status droplet, where the scenes are written.
  `Scripts/sync-shared.sh` refreshes them.
