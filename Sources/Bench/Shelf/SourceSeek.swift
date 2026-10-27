// SourceSeek.swift — the page's side of Show Where It Came From (DESIGN.md, Shelf →
// Show Where It Came From). Capsid's main window is on a session in Claude Science's
// own page, and this script, run once in Capsid's own content world, takes that page
// to one reply and brings the files the reply made into view.
//
// What the 0.1.70 bundle gives a page to go on, read from its files only
// (index-DhEuR7nq.js): no address names a message (the routes are /projects/<p>,
// /projects/<p>/frames/<f> and /projects/<p>/artifacts/<a>, and nothing reads
// `location.hash` or a message in the query), and the page's own "go to this reply"
// (the compute chip's jump, "view in context", the reviewer's findings) is a function
// inside its bundle that nothing outside it can call. What it does leave in the
// markup, and what the jumps and the findings themselves look for, is `data-msg-idx`
// on every message it draws: the message's index in the history, the same number the daemon's
// `/api/frames/<id>/messages?from=` counts from (Capsid's `source_row`, and the `i`
// of `ShowingMessage`). The conversation is a virtual list (`data-rs-index` rows
// under `[data-testid="conversation-scroll"]`): a reply far from the screen is not
// in the page at all, and the page keeps only the last 200 messages until the
// reader scrolls up, which loads 200 more (a scroll event that goes up, with the
// scroll position under 1800 pixels). So the script does what a reader would: it
// scrolls toward the reply, a jump at a time, as far as the drawn messages say it
// is, waits for the page to draw them (a fast scroll shows placeholders for a
// moment), and at the top of what is loaded scrolls up again so that the page
// loads more. Within a few seconds it either has the reply or gives up and puts the
// page back where it found it.
//
// Once the reply's element is there it takes the reply's turn (the row, `data-rs-index`)
// and, in it, the Generated tray (`data-testid="turn-artifact-tray"`: "GENERATED · n"
// and a card, `turn-tray-card`, for each file, five at most before "+n more"), and
// scrolls so that the tray is in view: from the top of the reply when the whole turn
// fits, else with the tray at two-fifths of the way down. The item's own card (its
// picture's address names its version, as for a right-click; else its file name, when
// exactly one card has it) gets a short outline that fades, drawn with the Web
// Animations API on the card itself, so no attribute, class or style of the page's
// is changed and nothing is left behind. A card the tray folds into "+n more" is
// not opened (that would change the page's state): the tray is outlined instead.
// A turn without a tray (the page's flow layout draws none) is scrolled to by its
// reply. For a note, or when no reply is known, the mode is `newest`: the end of the
// conversation.
//
// It never reads the words of the page: it reads the numbers in `data-msg-idx`, the
// sizes of elements, an image's address and a card's label to compare them with the
// version and the file name it was given. It posts nothing. The user's own
// wheel, touch, key or mouse-down (events the browser made: `isTrusted`) ends it at once and
// leaves the page where the user put it; events the page makes itself don't. It
// returns `{steps: […]}` in the fixed words of `SourceStep`, which Swift checks word
// by word and logs as one line.
import Foundation

/// One step of a Show Where It Came From, in fixed words (the Swift side's and the
/// script's), so one click says in Capsid's log where it stopped. The line reads
/// "Source: opened → row-found → turn-found → tray-shown → card-marked" and never
/// holds a name, an id or a word of the page.
enum SourceStep: String, CaseIterable, Sendable {
    // Swift: the session.
    /// The main window was taken to the session's page.
    case opened
    /// It was on the session already; the page was not reloaded.
    case alreadyThere = "already-there"
    /// The page did not come up on the session within the wait.
    case notReady = "not-ready"
    /// Capsid is only reading (it can't sign in): Claude Science's own app was opened.
    case readOnly = "read-only"
    /// The item's ids don't make a session's address: the window only came forward.
    case noAddress = "no-address"
    // Swift: which reply.
    /// The item's README names the reply's history row.
    case rowKnown = "row-known"
    /// The row was found by looking for the reply that shows the version.
    case rowFound = "row-found"
    /// No row is known (a note, or the version's reply was not found): the newest reply.
    case rowNone = "row-none"
    // The page.
    /// The conversation's scroller was not there within the wait.
    case noScroller = "no-scroller"
    /// The script scrolled to the top of what was loaded, where the page loads earlier messages as it scrolls up.
    case topReached = "top-reached"
    case turnFound = "turn-found"
    /// The reply did not come within the time, or is not drawn at all.
    case turnNotFound = "turn-not-found"
    /// The reply's Generated tray was scrolled into view.
    case trayShown = "tray-shown"
    /// The reply has no tray (it made no files, or the page draws none).
    case trayNone = "tray-none"
    /// The tray was found but is not on the screen, where it could be put.
    case trayOut = "tray-out"
    /// The item's own card was outlined.
    case cardMarked = "card-marked"
    /// The card was not among the tray's, or is in its "+n more": the tray was outlined.
    case cardHidden = "card-hidden"
    /// The end of the conversation was scrolled to.
    case newest
    /// The user scrolled, pressed a key or clicked first: the script stopped.
    case userMoved = "user-moved"
    /// The script could not run, or threw.
    case gaveUp = "gave-up"
}

/// What to show: a reply by its history row, or the newest.
struct SourceSeekRequest: Equatable, Sendable {
    enum Mode: String, Sendable { case reply, newest }

    var mode: Mode
    /// The reply's history row, for `.reply`.
    var row: Int?
    /// The version of the file whose card is outlined, and its name for a card with no picture.
    var version: String?
    var name: String?
    /// How long to wait for the conversation to be drawn, how long to seek, and how long to keep the
    /// tray in place while the page's layout settles (milliseconds).
    var readyMs = SourceSeek.readyMs
    var seekMs = SourceSeek.seekMs
    var settleMs = SourceSeek.settleMs

    /// The arguments of `callAsyncJavaScript`, each a plain value.
    var arguments: [String: Any] {
        [
            "mode": mode.rawValue,
            "row": (mode == .reply ? row : nil).map { $0 as Any } ?? NSNull(),
            "version": version.map { $0 as Any } ?? NSNull(),
            "name": name.map { String($0.prefix(SourceSeek.maxName)) as Any } ?? NSNull(),
            "readyMs": readyMs, "seekMs": seekMs, "settleMs": settleMs,
        ]
    }
}

enum SourceSeek {
    /// Waits, in milliseconds: for the conversation to be drawn after the page loaded, for the reply to
    /// come, and for the layout to settle after the tray is in place.
    static let readyMs = 8_000
    static let seekMs = 6_000
    static let settleMs = 1_500
    /// A file name longer than this is cut before it is sent.
    static let maxName = 300
    /// The most steps a line holds: the Swift side's three and the script's seven at most.
    static let maxSteps = 12

    /// The steps a script answered, `{"steps": [word, …]}`, as `SourceStep`s. A word that is not
    /// one of them is dropped, so nothing the page could put there is logged. Nil when the
    /// answer isn't a list of steps.
    static func steps(of answer: Any?) -> [SourceStep]? {
        guard let text = answer as? String,
              let root = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let words = root["steps"] as? [Any] else { return nil }
        return words.prefix(maxSteps).compactMap { ($0 as? String).flatMap(SourceStep.init(rawValue:)) }
    }

    /// The log line: "Source: opened → row-found → turn-found → tray-shown".
    static func line(_ steps: [SourceStep]) -> String {
        "Source: " + (steps.isEmpty ? "no steps" : steps.map(\.rawValue).joined(separator: " → "))
    }

    /// The script: the body of an async function of `mode` ("reply" or "newest"), `row` (a whole number
    /// or null), `version` and `name` (strings or null), `readyMs`, `seekMs` and `settleMs`.
    static let body = #"""
    "use strict";
    const steps = [];
    const note = (word) => {
      if (steps.length < 12 && steps[steps.length - 1] !== word) { steps.push(word); }
    };
    const clock = () => (typeof performance === "object" && performance !== null && typeof performance.now === "function"
      ? performance.now() : Date.now());
    const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

    // The user's own hands end it. Events the page makes itself (isTrusted false) are not the user's. So does a
    // newer run of this script in the same page: the last to start is the one that scrolls.
    let moved = false;
    const mine = {};
    globalThis.capsidSourceSeek = mine;
    const halted = () => moved || globalThis.capsidSourceSeek !== mine;
    const stopWord = () => (moved ? "user-moved" : "gave-up");
    const heard = (event) => { if (event.isTrusted) { moved = true; } };
    const kinds = ["wheel", "touchstart", "keydown", "mousedown"];
    kinds.forEach((kind) => document.addEventListener(kind, heard, true));

    const scrollerOf = () => Array.from(document.querySelectorAll('[data-testid="conversation-scroll"]'))
      .find((element) => element.clientHeight > 0) || null;
    const waitFor = async (read, ms) => {
      const until = clock() + ms;
      for (;;) {
        const value = read();
        if (value) { return value; }
        if (halted() || clock() >= until) { return null; }
        await pause(100);
      }
    };
    // The message numbers an element carries: "12" or "12 14" for a run of tool calls.
    const numbers = (element) => String(element.getAttribute("data-msg-idx") || "").split(/\s+/)
      .filter((part) => /^[0-9]{1,7}$/.test(part)).map(Number);
    // What is drawn: the lowest and highest message, the element that carries `row`, and about how
    // many pixels a message takes (the rows that carry messages, by the messages between the ends).
    const look = (scroller) => {
      let low = null, high = null, found = null;
      for (const element of Array.from(scroller.querySelectorAll("[data-msg-idx]"))) {
        for (const n of numbers(element)) {
          if (low === null || n < low) { low = n; }
          if (high === null || n > high) { high = n; }
          if (found === null && n === row) { found = element; }
        }
      }
      let height = 0;
      for (const turn of Array.from(scroller.querySelectorAll("[data-rs-index]"))) {
        if (turn.querySelector("[data-msg-idx]")) { height += turn.getBoundingClientRect().height; }
      }
      return { low: low, high: high, found: found, perMessage: low === null ? 0 : height / Math.max(1, high - low + 1) };
    };
    // A page that has only just loaded is still growing, and scrolls itself to the end as it does.
    const settleStart = async (scroller) => {
      let last = -1;
      const until = clock() + 1500;
      while (clock() < until && !halted()) {
        const now = scroller.scrollHeight;
        if (now === last) { return; }
        last = now;
        await pause(120);
      }
    };

    // Scrolls toward `row` until it is drawn. The element, or null.
    const seek = async (scroller) => {
      const view = scroller.clientHeight;
      const startTop = scroller.scrollTop;
      const atBottom = scroller.scrollHeight - startTop - view <= 4;
      let topLow = null, reached = false, stalls = 0, waits = 0, fruitless = 0;
      const until = clock() + seekMs;
      for (;;) {
        if (halted()) { note(stopWord()); return null; }
        const now = look(scroller);
        if (now.found) { return now.found; }
        if (clock() >= until) { break; }
        // Nothing drawn: placeholders while the page catches up with a fast scroll, or earlier messages arriving.
        if (now.low === null) { await pause(150); continue; }
        const upward = row < now.low, downward = row > now.high;
        if (!upward && !downward) {
          // Inside what is drawn, and not there: the page draws no element for that message.
          stalls += 1;
          if (stalls >= 4) { break; }
          await pause(180);
          continue;
        }
        stalls = 0;
        const top = scroller.scrollTop, max = Math.max(0, scroller.scrollHeight - view);
        if (upward && top <= 2) {
          // At the top of what is loaded and the reply is earlier: the page loads more when a scroll goes up, and
          // draws it a moment later. A scroll that goes up again asks again; when nothing comes, that is all there is.
          const progressed = topLow !== null && now.low < topLow;
          if (topLow === null || now.low < topLow) { topLow = now.low; }
          if (progressed) { fruitless = 0; waits = 0; } else { waits += 1; }
          if (progressed || waits >= 12) {
            if (!progressed && fruitless >= 2) { break; }
            if (!progressed) { fruitless += 1; }
            waits = 0;
            scroller.scrollTop = Math.min(view, max);
            await pause(60);
            scroller.scrollTop = 0;
            reached = true;
            note("top-reached");
          }
          await pause(80);
          continue;
        }
        waits = 0;
        // How far, by the pixels a message has taken where it is drawn. Further than the top, and it is above all
        // that is loaded: to the top, where the page loads more.
        const away = (upward ? now.low - row : row - now.high) * now.perMessage;
        const guess = isFinite(away) ? away * 0.85 : 0;
        const jump = upward && guess >= top ? top : Math.min(40 * view, Math.max(0.5 * view, guess));
        const to = upward ? Math.max(0, top - jump) : Math.min(max, top + jump);
        if (Math.abs(to - top) < 1) { break; }
        scroller.scrollTop = to;
        if (upward && to === 0) { reached = true; note("top-reached"); }
        // A fast scroll draws placeholders until it slows: the next look waits for them.
        await pause(to === 0 ? 120 : 260);
      }
      // Not reached: the page is as the user had it.
      try {
        if (atBottom) { scroller.scrollTop = scroller.scrollHeight; }
        else if (!reached) { scroller.scrollTop = startTop; }
      } catch (error) { }
      return null;
    };

    // The reply's turn and its tray, found again from the reply each time since the page redraws rows.
    const locate = (scroller) => {
      const message = look(scroller).found;
      if (!message) { return null; }
      const turn = message.closest("[data-rs-index]");
      return { message: message, turn: turn, tray: turn ? turn.querySelector('[data-testid="turn-artifact-tray"]') : null };
    };
    // Where the scroller should be: the whole turn from near the top when it fits, else the tray at
    // two-fifths of the way down; with no tray, the reply a quarter of the way down, as the page's own jumps put it.
    const aim = (scroller, place) => {
      const frame = scroller.getBoundingClientRect();
      const turnBox = place.turn ? place.turn.getBoundingClientRect() : null;
      let subject = place.message.getBoundingClientRect(), fraction = 0.25;
      if (place.tray) {
        if (turnBox && turnBox.height <= frame.height * 0.85) { subject = turnBox; fraction = 0.07; }
        else { subject = place.tray.getBoundingClientRect(); fraction = 0.4; }
      }
      return Math.max(0, scroller.scrollTop + (subject.top - frame.top) - frame.height * fraction);
    };
    const onScreen = (scroller, element) => {
      const frame = scroller.getBoundingClientRect(), box = element.getBoundingClientRect();
      return box.bottom > frame.top + 8 && box.top < frame.bottom - 8;
    };
    // The card for the item among the tray's: its picture's address names the version, else the one card
    // whose file-name label is the name.
    const cardIn = (tray) => {
      const cards = Array.from(tray.querySelectorAll('[data-testid="turn-tray-card"]'));
      if (typeof version === "string" && version !== "") {
        const byVersion = cards.find((card) => {
          const picture = card.querySelector("img");
          return picture && String(picture.currentSrc || picture.src || "").indexOf(version) >= 0;
        });
        if (byVersion) { return byVersion; }
      }
      if (typeof name === "string" && name !== "") {
        const named = cards.filter((card) => {
          const label = card.querySelector('[data-testid="middle-truncated-filename"]');
          return label && label.title === name;
        });
        if (named.length === 1) { return named[0]; }
      }
      return null;
    };
    // An outline that holds and fades, drawn by the browser on the element alone: no attribute, class or
    // style of the page's is touched, and it leaves nothing behind.
    const mark = (element) => {
      if (typeof element.animate !== "function") { return false; }
      const ring = (alpha) => ({ outlineStyle: "solid", outlineWidth: "2px", outlineOffset: "3px",
                                 outlineColor: "rgba(217, 119, 87, " + alpha + ")" });
      element.animate([Object.assign({ offset: 0 }, ring(0.95)), Object.assign({ offset: 0.4 }, ring(0.95)),
                       Object.assign({ offset: 1 }, ring(0))], { duration: 2400, easing: "ease-out" });
      return true;
    };

    try {
      const scroller = await waitFor(scrollerOf, readyMs);
      if (!scroller) { note(halted() ? stopWord() : "no-scroller"); return JSON.stringify({ steps: steps }); }
      await waitFor(() => scroller.querySelector("[data-msg-idx]"), readyMs);
      await settleStart(scroller);
      if (halted()) { note(stopWord()); return JSON.stringify({ steps: steps }); }
      if (mode !== "reply" || typeof row !== "number") {
        scroller.scrollTop = scroller.scrollHeight;
        note("newest");
        return JSON.stringify({ steps: steps });
      }
      if (!(await seek(scroller))) {
        if (!halted()) { note("turn-not-found"); }
        return JSON.stringify({ steps: steps });
      }
      note("turn-found");
      let place = locate(scroller);
      if (!place) { note("turn-not-found"); return JSON.stringify({ steps: steps }); }
      scroller.scrollTop = aim(scroller, place);
      await pause(120);
      // The page measures what it has drawn once it is in view, so the place is looked at again before it is judged.
      place = locate(scroller) || place;
      const want = aim(scroller, place);
      if (Math.abs(want - scroller.scrollTop) > 24) {
        scroller.scrollTop = want;
        await pause(120);
        place = locate(scroller) || place;
      }
      if (!place.tray) { note("tray-none"); }
      else if (onScreen(scroller, place.tray)) {
        note("tray-shown");
        const card = cardIn(place.tray);
        if (card && onScreen(scroller, card)) { if (mark(card)) { note("card-marked"); } }
        else if (mark(place.tray)) { note("card-hidden"); }
      } else { note("tray-out"); }
      // And it is kept for a moment more, since pictures and text still arriving change what is above it.
      const until = clock() + settleMs;
      while (clock() < until && !halted()) {
        await pause(150);
        const again = locate(scroller);
        if (!again) { break; }
        const target = aim(scroller, again);
        if (Math.abs(target - scroller.scrollTop) > 24) { scroller.scrollTop = target; }
      }
      if (halted()) { note(stopWord()); }
      return JSON.stringify({ steps: steps });
    } catch (error) {
      note("gave-up");
      return JSON.stringify({ steps: steps });
    } finally {
      kinds.forEach((kind) => document.removeEventListener(kind, heard, true));
      if (globalThis.capsidSourceSeek === mine) { globalThis.capsidSourceSeek = null; }
    }
    """#
}
