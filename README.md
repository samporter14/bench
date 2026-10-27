<img src="docs/icon.png" width="96" alt="Capsid's icon: a virus's twenty-sided shell inside a broken ring on a clay tile, one dot escaped through the gap">

# Capsid

**Claude Science as a real Mac app.** A Solanum product.

<img src="docs/scenes.gif" width="580" alt="Eight of Capsid's animated lab specimens playing: a pipette aliquoting, a cell dividing, distillation, a kinesin motor, CRISPR, a curve fit, a centrifuge and planaria">

**Install in one line**: paste into Terminal (Apple silicon, macOS 27):

```sh
curl -fsSL https://raw.githubusercontent.com/samporter14/bench/main/install.sh | zsh
```

Or [download Bench.zip](https://github.com/samporter14/bench/releases/latest/download/Bench.zip) (18 MB); see [Install](#install).

## Why Capsid

- **Small and light.** An 18 MB download, most of it the six app icons, with
  no Electron and no bundled browser. It uses the WebKit already built into
  macOS. In the recorded idle check, Capsid itself used 0% CPU and about
  50 MB of memory; the page runs in WebKit like a Safari tab.
- **Truly Mac native.** Written in Swift with SwiftUI and AppKit: Liquid
  Glass, a real toolbar, menus, keyboard shortcuts, Settings (⌘,) and Find
  (⌘F).
- **Nothing collected.** No Capsid account, no analytics, no telemetry. Capsid
  talks to nothing beyond your Mac except links you click, a once-a-day
  update check, which you can turn off, the update you choose to install,
  a model provider you configure and ask (below), and, if you turn on Capsid on your phone,
  your own paired devices over your Tailscale network, with notifications,
  if you turn them on, carried by Apple's push service and encrypted so only
  your device can read them. Capsid reads Claude Science and changes nothing
  in it, except when you press Approve on a plan's card, send an answer from
  a question's reply window, or answer, approve, send a message or start a
  session from a paired device. It saves nothing but its own settings
  (among them which session you had open, as an id, to reopen it), the
  files you choose to save, and the results you choose to keep (folders in
  your Documents, each with a README that names its session).
- **One home for Claude Science.** No lost browser tab. Nothing opens in
  Safari unless you ask, and pop-outs and sign-in windows stay in the app.
- **Know when it needs you.** While a session works, one of 549 little
  animated lab specimens plays in a glass panel in the corner of your screen.
  When a session needs your input, a card there takes you straight to it.
  Later can remind you in 5 or 15 minutes, or after a Nidus focus session.
  When a session stops with an error, the card says why, with **Copy**. If
  you've been away from the Mac for ten minutes, the specimen holds still
  until you're back.

  <img src="docs/panel-working.png" width="336" alt="The floating panel while a session works: a specimen playing, and the session's name, project and running time"> <img src="docs/panel-card.png" width="360" alt="The panel's card when a session asked a question, with Open and Later buttons">
- **Approve a plan from its card.** When a session asks you to approve its
  plan, the card shows the plan's summary, how many steps it has (their
  titles one click away) and Claude's own feasibility estimate, with an
  **Approve** button. Capsid checks it's still the
  same plan just before approving; if anything is off, Open takes you to the
  session instead. **Request changes…** lets you type what to change, and
  Claude revises the plan and asks again. Never from a Mac notification.
  Turn it off in Settings → Alerts.
- **Answer from its card.** The card shows what the session asks, with
  **Reply**, which opens a small window beside the panel with what Claude
  said last, to pick an answer (⌘1–⌘9) or type your own and send it (⌘↩).
  It always shows which session and project you're answering, and **Next**
  takes you to the next session waiting. A permission request shows what it
  wants, with **Allow Once** for a read-only tool, **Review** to read code
  before allowing it once, and **Deny**; anything that needs more opens in
  Capsid. Capsid checks it's still the same question or request just before
  sending, and keeps your answer if sending fails. Nothing takes the keyboard
  from what you're doing; only your click does. With Mac notifications on, a
  question with a few choices can be answered from its notification too.
- **Results.** File → Results… (⇧⌘R), the tray in the toolbar, or
  **Results** on a session's Finished card: the files your sessions made, by
  project and session. Preview any of them with Quick Look (Space), drag one
  out to Finder or another app, copy an image, text or PDF, Save… one or Save
  All… of a session into a folder (remembered per project), and jump back to
  the conversation each came from. It reads your most recent sessions when it
  opens, and older ones only when you ask. Quick Look's copies live in a
  private temporary folder that is emptied when the window closes.
- **Mac notifications, if you want them.** Off until you turn on **Also
  send a Mac notification** in Settings → Alerts → Mac notifications. Then
  a session that needs you or stops with an error sends a notification too,
  so you see it in full screen or with the panel off, and finishes can as
  well.
  macOS asks your permission once, and you can hide the session and project
  names.
- **Every session in one list.** Click the status in the toolbar, or
  right-click Capsid in the Dock, for what needs you (longest waiting first,
  anything put off with Later underneath), what's working and what happened
  lately, each one click from its session. Hover a session that needs you to
  reply, approve or allow right there, as on its card. **⌥⌘↓** (File → Next
  Waiting Session) opens the next one waiting, and the next. Press ⌘⇧O to
  jump to any session by typing part of its name or project, however old.
  Capsid reopens the session you had open when it last quit.

  <img src="docs/activity.png" width="390" alt="The activity list under the toolbar's 2 need you: two sessions waiting, one stopped with an error, two working with their clocks, and Recent below">
- **A heads-up before you hit a wall.** A card when your plan is nearly
  used up, when at this pace it will run out within 45 minutes, and when it
  resets, and when the session you have open has used most of its context.
  Once a new week starts, a quiet week in review.
- **Plays well with Nidus.** While a [Nidus](https://github.com/samporter14/nidus)
  focus session runs, "Finished" cards wait until it ends and come as one;
  questions and errors still come at once. If you turn on **Settings → General
  → Share the task I'm viewing with Nidus**, Capsid also writes the focused
  Claude Science task's project and title to a small local file for Nidus.
  It clears the file when you leave that task or switch away from Capsid.
  Conversation text is never included.
- **Quiet while you present.** Turn on **Quiet While Presenting** in
  Settings → Alerts, the Capsid menu or the Dock menu, or add Capsid's filter to a Focus in System
  Settings → Focus (a "Presenting" Focus, say). Until it ends, the specimen
  and its cards stay out of sight, with no sounds or Mac notifications, so
  nothing pops up over your slides with a project's name on it. Afterwards,
  whatever still needs you is there, and what finished comes as one card.
- **Optional menu bar specimen.** Turn it on in Settings to see a session
  working, or a count of those waiting, from the menu bar.
- **Usage at a glance.** The title bar shows how full your session's context
  is and how much of your 5-hour limit is left, with a countdown to when it
  resets (or, if you prefer, whichever limit is lowest: Settings → Usage). A
  weekly limit that's nearly used up shows instead, so it never catches you
  out.

  <img src="docs/toolbar.png" width="418" alt="The title bar: a working session's timer, the context ring at 9%, and 54% of the plan left, resetting in 1 hour 28 minutes">

## Make it yours

Pick how big the specimens play, turn whole categories on or off, or choose
them one by one, in Settings → Specimens: click a specimen to switch it on or
off, or right-click it to play only that one. Star your favorites and switch
Play to Only favorites to play just those; your other picks wait for when
you switch back. Show only the ones that are on, off or starred to check
your picks. The preview plays only what's on, in light or
dark. Hover a specimen to see it play big, with a few words about it. Search
matches what a specimen is about as well as its name, and the Topics menu
beside the search field finds a whole subject at once, "microscopy" say. Turn
on Settings → Panel → Name the specimen that's playing for its name and a
caption under the session in the panel. Turn on **Play short sequences** and,
now and then, a few specimens play in order, like a little story. Tired of the
one playing right now? Right-click the panel and choose Don't Play. The panel can sit in any
corner of your screen, on any display: Settings → Panel → Corner and
Screen. And Capsid's own icon comes in six of Solanum's colorways (Clay,
Ivory, Slate, two one-color versions and Ivory with a clay capsid): Settings →
General → App icon. It changes the Dock icon while Capsid is open; Finder and
Launchpad keep the Clay one, because macOS doesn't let an app change those
without altering itself.

<img src="docs/scene-picker.png" width="520" alt="Settings, Specimens tab: a size picker, a checkbox per category (Lab 130 of 131, Biology 211 of 214), a search field with an All, On and Off filter, and a grid of specimens under a Lab heading, each with a clay check when on">

## Your shelf

Claude Science makes a lot of figures, notes and tables, and the one you
meant is easy to lose. **Right-click a figure, file link or document tile in a
conversation and choose Add to Shelf** (or click the seal on a file in Results, or the pill
under a figure in the reference window). It's copied onto your shelf with what
Claude said about it and exactly where it came from. **The Shelf** (⇧⌘K, or
the Shelf button in the toolbar) shows everything you've shelved, by project
and kind, with search; pick one and **Show Where It Came From** opens the very
answer it came from, with the figure marked. Shelved files live in folders you
own, `~/Documents/Kept/<project>/`, each with a README that says where it came
from; Remove puts one in the Trash.

**Search finds figures and files in every session**, not only the ones on the
shelf: type in the Shelf's search (or Open Session…) and what Claude made
anywhere shows under your shelf's own matches, with Add to Shelf and Show
Where It Came From. For lab meeting, pick several figures (⌘-click) and
choose **Export Figure as PDF…** (⌘P; "Export 3 Figures as PDF…" with
several): one 16:9 page each, with its title, legend and where it came from.

**Compare two of them.** Right-click a picture or a text file and choose
**Compare With**, then the other one. Pictures sit side by side with their zoom
linked, or one over the other with **Wipe** when they're the same size; for two
text files you see what changed, line by line, with Previous and Next Change.
With two picked, **Compare** in the title bar does the same.

**Add Selection to Shelf** keeps selected words as a note. Its card shows the
passage, with where it came from; Copy copies the words. Search also looks
inside notes, Markdown and text documents, and the legend files kept beside
figures, so you can find a passage without remembering its file name.

When a figure is going into a paper, **Keep with Data and Code…** (⌥⌘K) keeps
the real version with the data it was drawn from and the script that drew it.
If Claude made a legend file, Keep can keep it too; on the Shelf, **Use
Claude’s legend** puts its words into Your legend, where you can edit them.

<img src="docs/shelf.png" width="600" alt="The Shelf window with heatmap typed in its search: two shelved heatmaps as cards, then In your sessions with five more files from other sessions, each with Add to Shelf, and the selected figure's detail with where it came from">

## An answer beside the work

When you're writing from what Claude found, you want the answer next to the
document, not in a tab behind it. **Open as Reference** (⌥↩ in Open Session…,
the right-click menu of any session in the activity list, or a card's Later
menu) opens a small read-only window with Claude's latest reply in that
session: the figures it made, full width, then what it said, with your
question above. Each figure has **Keep…** under it. Earlier and Later step
through the replies (⌥⌘← and ⌥⌘→). **Copy with Source** (⇧⌘C) copies what you
selected, or the whole reply, with a line saying which session and project it
came from and when, and a link that opens the session in Capsid. **Window →
Keep on Top** floats the window over your document; Open Conversation takes
you to the session itself. The window reads the conversation the way the
phone does, a page at a time, waits while you type, and writes nothing.

**Come back to a project.** Each project keeps its last conversation, up to four
references you pin to it (the ⋯ at the foot of the reference window) and a
small Working Note. **History → Project Workspace** (⌥⌘P) shows them, and
**Return to Project** brings them back together, with the Shelf on that
project. There's nothing to save.

<img src="docs/reference.png" width="300" alt="A reference window titled Plate reader QC, read only: the question, then Claude's figure full width with Add to Shelf under it, and Copy with Source and Open Conversation at the foot">

## Ask another model

Ask a model at another provider, with your own key. **Ask Another Model…**
is in the File menu and toolbar. Turn it on in Settings → General, paste
your key, and choose a model at an OpenAI-compatible provider
(Abliteration.ai is the default; OpenRouter works too).

It is off by default. Your question and, if you choose, the conversation
shown beside it go to that provider only when you press **Ask**. The answer
streams into its own window, with Copy and **Send to Session** when it
finishes. It cannot change Claude Science’s own model.

<img src="docs/ask-another-model.png" width="420" alt="Ask Another Model for the made-up Plate reader QC session: a question, the included conversation, a finished answer, Copy and Send to Session">

## Start from anywhere

**Quick Start** (⌃⌥⌘Space, or File → Quick Start…) is a small panel over
whatever you're doing: type a request, drop files in, pick the project, and
press Return for a new session (Shift-Return sends it to the session you're
looking at instead). Messages sent from the Mac can be up to 32,000
characters; the phone keeps its 4,000-character limit. Save the requests you
make often as **recipes**
(Settings → Recipes) and fill them with ⌘1 to ⌘9. Finder's Services menu
starts a session with the files or text you've selected, and Shortcuts has
actions to start a session, run a recipe, send a message or list the sessions
that need you; they ask before they start or send anything unless you allow it
in Settings.

Capsid also lives in the **menu bar**: a quiet glyph with a count of what
needs you. A click opens a glass home with a Quick Start field, what needs you
(answer from the row), what's working, today's results and your 5-hour limit.
Turn it off in Settings → General.

<img src="docs/quick-start.png" width="420" alt="Quick Start over the desktop: a request, an attached spreadsheet, project chips, Ask for a plan first, three recipes with their keys, and Start"> <img src="docs/menu-bar.png" width="250" alt="The menu-bar home: a Quick Start field, Needs you with Reply and Approve, two working sessions with their clocks, today's results as tiles, and the 5-hour limit">

## The panel, while it works

The specimen that plays is matched to what the session is about when one of
yours fits (a session about a gel plays the gel; Settings → Specimens). While
Claude follows a plan, the panel says which step it's on ("Step 4 of 6 · Check
against published screens") with a thin bar. When a session finishes, the
card shows its figures, how many files it made and what the reviewer found,
with Results and, for a single figure, Keep…. When one stops with an error,
it says why. A note Claude sends while it works comes up as a quiet card. A
question, a plan, a failure and a finish each have their own sound. With two
or more sessions working, hover over the panel to see them all.

## Since you left

Come back after half an hour or more and one sheet says what changed while you
were away: what needs you (answer a question right there), what finished
(Claude's last words and a few of its files, with Add to Shelf), what stopped
and why, and how much of your 5-hour limit it used. It opens over Capsid's
window when that's the window you're using; otherwise the panel shows a card,
and the activity list keeps a section at the top until you press Done. Your
phone shows the same. Turn the sheet off in its own foot, or in Settings →
Alerts.

<img src="docs/since-you-left.png" width="520" alt="The Since you left sheet after 2 hours 14 minutes: 3 finished, 1 stopped, 1 needs you; a question to answer with its choices, finished sessions with Claude's last words and their files, a stopped session with why, and the 5-hour limit used while away">

## Capsid on your phone

Use Claude Science from your iPhone, iPad or another computer while you're
away from your Mac: a private web app that Capsid serves to your own devices
over your [Tailscale](https://tailscale.com) network. **[The setup guide](docs/phone.md)**
takes about five minutes. Nothing is on the
public internet: Capsid listens only on your Mac, and Tailscale Serve passes
on what your devices ask, with a certificate for your tailnet.

- **Now**: what needs you, what stopped with an error, what's working (with
  live clocks) and what happened lately, plus your plan's usage.
- **A session**: its latest reply and the whole conversation (scroll up for
  more), with tool steps as one quiet line each, and the files it made:
  images, documents and tables open on the phone, anything else downloads.
- **Act on it**: answer its question, approve its plan, send it a message
  (it waits for the next pause if Claude is busy) or a photo, and answer its
  permission requests: running code and read-only tools can be allowed once;
  anything that would grant lasting access is Deny or Open on Mac. Capsid
  checks the session hasn't changed on your Mac just before it acts.
- **Watch it work**: while a session works, its reply appears as it's
  written, with what it's doing ("Executing code").
- **Projects**: every project and all its sessions, with search, and a new
  session in any of them.
- **Notifications**, if you turn them on, on each device: when a session
  needs you, stops with an error or (if you like) finishes; by default only
  while you're away from your Mac and without session names. They travel
  through Apple's push service, encrypted so only your device can read them.
- **A count on the Capsid icon** of sessions that need you.
- On iPad, a sidebar and the session side by side.

It's **off** until you turn it on in **Settings → Phone**, which walks you
through six steps and ticks each one off as you go: Tailscale on your Mac,
signed in, HTTPS on, Tailscale on your phone, the switch, and pairing (scan
the QR code, add the page to your Home Screen, open it from there and enter
the one-time code). Settings lists paired devices, each
with Remove (a device unused for 60 days has to pair again), and has two
switches: one for answering, approving and sending messages, one for
browsing projects, full conversations and files. Turning Capsid on your phone
off, or quitting Capsid, stops serving and leaves your other Tailscale Serve
settings as they are.

## Install

You need a Mac with Apple silicon (M1 or later) on macOS 27, with
Claude Science installed. Close any Claude Science browser tab first, because
Claude Science runs in one tab at a time. Capsid starts Claude Science if it
isn't running and signs you in. The first time, a short welcome shows you
around; Help → Welcome to Capsid shows it again.

**Coming from Bench?** Capsid was called Bench until 0.6.0. Installing or
updating it the usual way replaces Bench in Applications with Capsid, and
your settings and paired devices carry over. The download is still called
Bench.zip, and this repository is still `bench`.

### Easiest: one line in Terminal

```sh
curl -fsSL https://raw.githubusercontent.com/samporter14/bench/main/install.sh | zsh
```

It downloads the latest Capsid from this page's releases, checks its
signature, puts it in Applications (quitting an older one, which it keeps
aside until the new one is running), and opens it. **Run the same line again
to update.** macOS doesn't show its "can't verify" warning
for apps installed this way, because it only flags apps downloaded through a
web browser. You're trusting this page instead, so [install.sh](install.sh)
is short enough to read first.

**Updates.** On unless you turn off **Settings → General → Updates → Check for
updates once a day**: Capsid asks GitHub for its latest release about once a
day. When a newer one is out, a card says so and an **Update** button appears
in the toolbar, with **Install and Reopen**, **Release Notes** and **Skip This
Version**; the Dock icon's menu has an Install item too. The request carries
only the name `Capsid` and its version, nothing about you or your sessions,
though GitHub sees your IP address as any site you visit does.
**Capsid → Check for Updates…** and **Check Now** ask at once, with the
switch off too. Installing is Capsid's own work: it downloads that release's
Bench.zip from GitHub, checks that the copy is signed the way the one you're
running is and says the version it was offered, then quits and swaps it in.
The copy you had is kept beside the new one until the new one is running, and
put back if it doesn't start; nothing is deleted before then. The toolbar
button shows the download, and Cancel stops it until the swap begins. A copy
that isn't in Applications can't replace itself, so it offers only the
release notes.

### Or download it

1. [Download Bench.zip](https://github.com/samporter14/bench/releases/latest/download/Bench.zip)
   and open it.
2. Drag **Capsid** into your **Applications** folder, and open it from there
   rather than from Downloads. If Bench is there from before, quit it and
   move it to the Trash: Capsid replaces it.
3. Open Capsid. The first time, macOS blocks it because it isn't from the App
   Store or a registered developer. Click **Done**, then go to **System
   Settings → Privacy & Security**, scroll down, and click **Open Anyway**
   next to Capsid.

To update a downloaded copy, quit Capsid first with **⌘Q**. Closing its window
isn't enough, because Capsid keeps running in the background to watch your
sessions. Then replace it in Applications, open it, and click **Open Anyway**
once more. **Capsid → About Capsid** shows which version is running.

### If something's off

If Capsid ever opens on a "Sign in" screen, click **Sign in**.

If the specimens or the "needs you" cards never show up, open **Help → Capsid
Diagnostics**. It checks each step Capsid takes to see your sessions and has a
**Copy** button; nothing in it names your projects or sessions. It also says
which Claude Science version Capsid was last checked with, looks (without
changing anything) at the parts of Claude Science's page and API Capsid relies
on, and shows the last time one of them wasn't what Capsid expected: worth a
look after a Claude Science update. The same
report prints in Terminal with the command below, once macOS has let that
version of Capsid open:

```sh
/Applications/Capsid.app/Contents/MacOS/Capsid --diagnose
```

## Build it yourself

With Xcode 27 installed, run this from the repo's folder:

```sh
Scripts/build-app.sh --open
```

It builds `build/Capsid.app` and opens it.

## Notes

- Capsid is a personal project, unofficial, and not affiliated with or
  endorsed by Anthropic. It's a work in progress: `TESTING.md` says what has
  been checked live so far.
- `DESIGN.md` is the spec: the look, where the glass goes, and how links are
  routed.
- The screenshots use made-up sessions: `Capsid --demo working|card|plan|toolbar|general|specimens`
  shows the real UI with invented names (add `--quiet`, and launch with
  `open -g -n`, to keep it from taking the keyboard),
  `Capsid --demo phone-settings --step 1…7` shows Settings → Phone at each
  step of its setup checklist, `Capsid --demo remote` serves the phone page with them on
  `http://127.0.0.1:47280` (pairing code `000000`), and
  `Capsid --render-scenes` records the scene GIF.
- `Sources/Bench/Shared` holds the specimens and the session reader. They
  began in the Science Status droplet and are Capsid's own since 1.0.
- MIT licensed; see [LICENSE](LICENSE).
