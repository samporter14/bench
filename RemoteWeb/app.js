// Capsid on your phone. Plain JS, no dependencies, same-origin only.
// Every piece of user text goes in through textContent (h() below), never innerHTML.

const $ = (id) => document.getElementById(id);
const root = $('root');
// Every map keyed by an id or a name has no prototype, so a key like __proto__ is just a key.
const dict = () => Object.create(null);

const S = {
  view: 'boot',        // boot | pair | offline | app
  down: { status: 0, err: false },
  pairMsg: '',
  state: null,         // the last /api/state snapshot
  sig: '',             // snapshot signature without updatedAt, to skip no-op renders
  me: null,
  sess: dict(),        // id -> { phase: loading|ok|missing|error, data }
  open: dict(),        // id -> { phase: busy|done|error, down, status }
  lastOk: 0,           // when we last heard from Capsid (stream or poll)
  lastTry: 0,
  refreshing: null,
  es: null,
  esTimer: 0,
  backoff: 0,
  tickTimer: 0,
  n: 0,
  scroll: dict(),
  rk: '',
  navs: 0,
  split: false,        // the iPad layout: the Now list beside the selected session
  ui: dict(),          // id -> what the person typed or chose on that session
  sessAt: dict(),      // id -> when we last fetched it
  sessSig: dict(),     // id -> what the state said about it at that fetch
  sessTimer: 0,
  push: { loaded: false, unavailable: false, key: '', on: false, prefs: null, busy: false, msg: '' },
  side: { tab: 'now', pid: null },   // what the iPad sidebar is showing
  from: null,          // the last list screen we were on, so a session's Back says where it goes
  prevKey: '',
  projects: { list: [], loaded: false, busy: false, err: false, at: 0 },
  proj: dict(),        // pid -> { items, next, q, applied, busy, err, loaded, seq, t }
  newSess: dict(),     // pid -> the draft of a new session
  hist: dict(),        // session id -> its history rows, by index
  art: dict(),         // session id -> its artifacts
  files: dict(),       // version id -> { v, a, name, kind, size, mime, at }
  ftext: dict(),       // version id -> the text, markdown or table of a file
  seen: dict(),        // 's:<id>' / 'f:<version>' -> when it was last on screen, as a count (trimCaches)
  clock: 0,
  wrap: false,
  sinceKey: '',        // the stretch away (`since.awayAt`) the next three belong to
  sinceAsked: dict(),  // what the Since you left section has asked for, once each
  sinceNote: dict(),   // session id -> what happened to the answer chosen in the section
};
const splitQuery = matchMedia('(min-width: 768px) and (min-height: 500px)');
S.split = splitQuery.matches;

/* ---------- small DOM helpers ---------- */

function h(tag, props, ...kids) {
  const el = document.createElement(tag);
  if (props) {
    for (const [k, v] of Object.entries(props)) {
      if (v == null || v === false) continue;
      if (k === 'text') el.textContent = v;
      else if (k === 'class') el.className = v;
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v === true ? '' : v);
    }
  }
  el.append(...kids.flat(2).filter((x) => x != null && x !== false));
  return el;
}

// Images outside the viewport may still belong to the lazy-load observer. Dispose only those
// actually removed by a screen/region replacement; an image reused or moved into the new tree stays live.
function replaceContents(el, ...kids) {
  const images = [...el.querySelectorAll('img')].filter((img) => img._disposeFileImage);
  el.replaceChildren(...kids);
  for (const img of images) if (!img.isConnected && !el.contains(img)) img._disposeFileImage();
}

const PATHS = {
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
  refresh: '<polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>',
  left: '<polyline points="15 18 9 12 15 6"/>',
  chev: '<polyline points="9 18 15 12 9 6"/>',
  alert: '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>',
  moon: '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>',
  pause: '<circle cx="12" cy="12" r="10"/><line x1="10" y1="15" x2="10" y2="9"/><line x1="14" y1="15" x2="14" y2="9"/>',
  up: '<line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/>',
  check: '<polyline points="20 6 9 17 4 12"/>',
  clock: '<circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 15.5 14"/>',
  folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  compose: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
  plus: '<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>',
  file: '<path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><polyline points="13 2 13 9 20 9"/>',
  doc: '<path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><polyline points="13 2 13 9 20 9"/><line x1="8" y1="13" x2="16" y2="13"/><line x1="8" y1="17" x2="14" y2="17"/>',
  image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/>',
  table: '<rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="3" y1="15" x2="21" y2="15"/><line x1="9" y1="3" x2="9" y2="21"/>',
  code: '<polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/>',
  text: '<line x1="17" y1="10" x2="3" y2="10"/><line x1="21" y1="6" x2="3" y2="6"/><line x1="21" y1="14" x2="3" y2="14"/><line x1="17" y1="18" x2="3" y2="18"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/>',
  terminal: '<polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/>',
  list: '<line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/>',
  ask: '<circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><line x1="12" y1="17" x2="12.01" y2="17"/>',
  msg: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  helper: '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
  share: '<path d="M4 12v7a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7"/><polyline points="16 6 12 2 8 6"/><line x1="12" y1="2" x2="12" y2="15"/>',
  camera: '<path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/>',
  x: '<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>',
};

function icon(name, cls = '') {
  const t = document.createElement('template');
  t.innerHTML = `<svg class="ico ${cls}" viewBox="0 0 24 24" aria-hidden="true" focusable="false">${PATHS[name]}</svg>`;
  return t.content.firstElementChild;
}

/* ---------- times ---------- */

const fmtTime = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
const fmtDay = new Intl.DateTimeFormat(undefined, { weekday: 'short', hour: 'numeric', minute: '2-digit' });
const fmtDate = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto', style: 'short' });
const dayStart = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

function when(v) {
  const d = v instanceof Date ? v : new Date(v);
  if (isNaN(d)) return '';
  const days = Math.round((dayStart(d) - dayStart(new Date())) / 864e5);
  if (days === 0) return fmtTime.format(d);
  return (Math.abs(days) < 7 ? fmtDay : fmtDate).format(d);
}

function ago(ms) {
  if (!Number.isFinite(ms)) return '';
  const s = Math.round((ms - Date.now()) / 1000);
  const a = Math.abs(s);
  if (a < 45) return rtf.format(0, 'second');
  if (a < 3600) return rtf.format(Math.round(s / 60), 'minute');
  if (a < 86400) return rtf.format(Math.round(s / 3600), 'hour');
  return rtf.format(Math.round(s / 86400), 'day');
}

function rel(iso) {
  const el = h('time', { class: 'rel', datetime: iso || null });
  el._ms = Date.parse(iso);
  el.textContent = ago(el._ms);
  return el;
}

function mmss(ms) {
  let s = Math.max(0, Math.floor(ms / 1000));
  const hh = Math.floor(s / 3600);
  s %= 3600;
  const p = (n) => String(n).padStart(2, '0');
  return (hh ? `${hh}:${p(Math.floor(s / 60))}` : String(Math.floor(s / 60))) + ':' + p(s % 60);
}

function clockEl(iso) {
  const el = h('span', { class: 'clock' });
  el.dataset.t = String(Date.parse(iso));
  el.textContent = Number.isFinite(+el.dataset.t) ? mmss(Date.now() - +el.dataset.t) : '–:––';
  return el;
}

/* ---------- network ---------- */

class Down extends Error {
  constructor(status = 0) { super('down'); this.status = status; }
}
class Unauth extends Error {}
// A read the person left behind (a screen replaced, the page put away) was dropped on purpose: not a failure, so neither
// an error on a screen nor the offline one.
class Aborted extends Error {}

// Waits `ms`, or less when `signal` aborts.
const pause = (ms, signal) => new Promise((resolve) => {
  const done = () => { clearTimeout(timer); if (signal) signal.removeEventListener('abort', done); resolve(); };
  const timer = setTimeout(done, ms);
  if (signal) { if (signal.aborted) done(); else signal.addEventListener('abort', done, { once: true }); }
});
// Capsid answers 429 when this device asks a lot at once ({"error":"slowDown"}) or already has two
// files coming ({"error":"busy"}), with Retry-After in seconds.
const retryWait = (res, n) => Math.min(10, Math.max(1, Number(res.headers.get('Retry-After')) || n)) * 1000 + Math.random() * 500;
const isSlow = (e) => !!e && e.status === 429;
const slowText = (d) => (d && d.error === 'busy' ? 'Another file is still coming. Try again in a moment.' : 'That’s a lot at once. Try again in a moment.');

// Two file transfers at a time, as Capsid allows: thumbnails, texts and downloads take turns here.
const FQ = { n: 0, wait: [] };
// A queued image can withdraw without taking a slot. Once started, it keeps its slot until its
// load completes, just like the other transfers; leaving a screen never increases concurrency.
function fileSlot() {
  const ticket = { ready: null, cancel: () => {} };
  if (FQ.n < 2) {
    FQ.n++;
    ticket.ready = Promise.resolve(true);
  } else {
    ticket.ready = new Promise((resolve) => {
      const start = () => { ticket.cancel = () => {}; resolve(true); };
      FQ.wait.push(start);
      ticket.cancel = () => {
        const at = FQ.wait.indexOf(start);
        if (at < 0) return;
        FQ.wait.splice(at, 1);
        ticket.cancel = () => {};
        resolve(false);
      };
    });
  }
  return ticket;
}
const takeSlot = () => fileSlot().ready;
// A read's turn that a signal can withdraw: aborted while it waits, it steps out of the queue without taking a slot
// (false). With a slot it keeps it until its request ends, abort or not, so leaving never raises the two at a time.
async function takeSlotUnless(signal) {
  const ticket = fileSlot();
  if (!signal) return ticket.ready;
  const withdraw = () => ticket.cancel();
  signal.addEventListener('abort', withdraw, { once: true });
  try { return await ticket.ready; } finally { signal.removeEventListener('abort', withdraw); }
}
function giveSlot() {
  const next = FQ.wait.shift();
  if (next) next(); else FQ.n = Math.max(0, FQ.n - 1);
}
const isFile = (path) => path.startsWith('/api/files/');

/* ---------- reads that belong to a screen ---------- */

// A read for a screen takes the signal of a scope named for what it is about: 's:<session id>' for a session, its history,
// its artifacts and its files, 'p:<project id>' for a project's sessions. When a screen is left, or the page put away,
// the scopes no screen needs are aborted (`syncScopes`, `abortScopes`): a request in flight is cancelled, and Capsid stops
// reading for it too, and one still waiting for one of the two transfer slots is withdrawn. Writes and downloads the
// person asked for carry no signal, so nothing of theirs is ever aborted.
const SCOPES = dict();
const scopeSignal = (key) => (key && typeof AbortController === 'function' ? (SCOPES[key] ||= new AbortController()).signal : undefined);

function abortScopes(keep) {
  for (const key of Object.keys(SCOPES)) {
    if (keep && keep.has(key)) continue;
    const controller = SCOPES[key];
    delete SCOPES[key];
    controller.abort();
  }
}

// The scopes the screen on show needs: its session, its project, and the iPad sidebar's project.
function scopesInUse() {
  const keep = new Set();
  if (S.view !== 'app') return keep;
  const r = route();
  if (r.id) keep.add('s:' + r.id);
  if (r.pid) keep.add('p:' + r.pid);
  if (S.split && S.side.pid) keep.add('p:' + S.side.pid);
  return keep;
}
const syncScopes = () => abortScopes(scopesInUse());

// A read Capsid asks to wait is tried again quietly, twice, after the wait it names. A GET with a `scope` is dropped,
// as `Aborted`, once that scope is aborted; a POST never is.
async function api(path, method = 'GET', body, scope = '') {
  const post = method === 'POST';
  const file = isFile(path);
  const signal = post ? undefined : scopeSignal(scope);
  for (let n = 1; ; n++) {
    let res;
    if (signal && signal.aborted) throw new Aborted();
    if (file && !(await takeSlotUnless(signal))) throw new Aborted();
    try {
      try {
        res = await fetch(path, {
          method,
          cache: 'no-store',
          headers: post ? { 'Content-Type': 'application/json', 'X-Bench': '1' } : { Accept: 'application/json' },
          body: post ? JSON.stringify(body ?? {}) : undefined,
          signal,
        });
      } catch {
        throw signal && signal.aborted ? new Aborted() : new Down();
      }
      if (!(res.status === 429 && !post && n < 3)) {
        if (res.status === 401) throw new Unauth();
        if (res.status === 502 || res.status === 503 || res.status === 504) throw new Down(res.status);
        if (!res.ok) {
          const e = new Error('http ' + res.status);
          e.status = res.status;
          e.wait = Number(res.headers.get('Retry-After')) || 0;
          try { e.data = await res.json(); } catch { /* not JSON */ }
          if (signal && signal.aborted) throw new Aborted();
          throw e;
        }
        try { return await res.json(); } catch { if (signal && signal.aborted) throw new Aborted(); return null; }
      }
      try { await res.text(); } catch { /* gone */ }
    } finally {
      if (file) giveSlot();
    }
    await pause(retryWait(res, n), signal);
  }
}

// A POST whose answer matters even when it is not a 2xx: the status and any JSON body.
async function send(path, body) {
  let res;
  try {
    res = await fetch(path, { method: 'POST', cache: 'no-store', headers: { 'Content-Type': 'application/json', 'X-Bench': '1' }, body: JSON.stringify(body ?? {}) });
  } catch {
    throw new Down();
  }
  if (res.status === 401) throw new Unauth();
  if (res.status === 502 || res.status === 503 || res.status === 504) throw new Down(res.status);
  let data = null;
  try { data = await res.json(); } catch { /* not JSON */ }
  return { status: res.status, data };
}

// Foreground failures change the screen. Background ones (a quiet poll) only
// leave the "Not updating" note to appear.
function fail(e, fg) {
  if (e instanceof Unauth) return showPair();
  if (isSlow(e) && S.state) return; // Capsid asked to wait: the next poll tries again
  if (e instanceof Down) return fg || !S.state ? showOffline(e.status, false) : undefined;
  if (fg || !S.state) showOffline(e.status || -1, true);
}

function showPair(msg = '') {
  if (S.view === 'pair') return;
  S.view = 'pair';
  S.pairMsg = msg;
  S.state = null;
  applyBadge();
  S.sig = '';
  S.sess = dict();
  S.ui = dict();
  Object.assign(S, { projects: { list: [], loaded: false, busy: false, err: false, at: 0 }, proj: dict(), newSess: dict(), hist: dict(), art: dict(), files: dict(), ftext: dict(), seen: dict() });
  S.push = { loaded: false, unavailable: false, key: '', on: false, prefs: null, busy: false, msg: '' };
  S.me = null;
  disconnect();
  abortScopes();
  pill();
  render(true);
}

function showOffline(status, err) {
  if (S.view === 'offline' && S.down.err === err) return;
  S.view = 'offline';
  S.down = { status, err };
  disconnect();
  abortScopes();
  pill();
  render(true);
}

function refresh(fg = true) {
  if (S.refreshing) return S.refreshing;
  S.lastTry = Date.now();
  const p = (async () => {
    try {
      gotState(await api('/api/state'));
    } catch (e) {
      fail(e, fg);
    } finally {
      S.refreshing = null;
    }
  })();
  S.refreshing = p;
  return p;
}

function refreshAll(fg) {
  const r = route();
  const jobs = [refresh(fg)];
  if (r.name === 'session') { jobs.push(loadSession(r.id, true)); if (browseOn()) jobs.push(loadArtifacts(r.id)); }
  else if (r.name === 'artifacts') jobs.push(loadArtifacts(r.id));
  else if (r.name === 'projects') jobs.push(loadProjects(true));
  else if (r.name === 'project') jobs.push(loadProjects(true), loadProject(r.pid, false));
  return Promise.all(jobs);
}

async function start() {
  try {
    const me = await api('/api/me');
    if (me && me.paired === false) return showPair();
    S.me = me;
  } catch (e) {
    return fail(e, true);
  }
  await refresh(true);
}

async function loadMe() {
  try {
    S.me = await api('/api/me');
  } catch (e) {
    if (e instanceof Unauth) showPair();
    return;
  }
  if (S.view === 'app' && route().name === 'settings') render();
}

// What the session says about its own conversation. While it is the same, no message has been added, so the
// history already held is still right; `total` itself only comes with the history, which is why the session's stamp stands in for it.
const histStamp = (d) => {
  const last = d && Array.isArray(d.turns) && d.turns.length ? d.turns[d.turns.length - 1] : null;
  return d ? [d.updatedAt, d.state, last && last.at].join('|') : '';
};

// Read after the session, so the stamp it is filed under is never newer than what was read. Asked for on a first look,
// when the stamp moved, or when the caller knows something just happened (`fresh`: a refresh the person asked for,
// an action that was sent, a session that stopped working).
function wantHistory(id, data, fresh) {
  const r = route();
  if (r.name !== 'session' || r.id !== id || !browseOn()) return;
  const at = histStamp(data);
  const H = hist(id);
  if (fresh || !H.loaded || H.at !== at) loadHistory(id, at);
}

async function loadSession(id, fresh = false) {
  const had = S.sess[id];
  S.sessAt[id] = Date.now();
  S.sessSig[id] = JSON.stringify(lookup(id));
  let placeholder = null;
  if (!had) S.sess[id] = placeholder = { phase: 'loading', data: null };
  try {
    const data = await api('/api/sessions/' + encodeURIComponent(id), 'GET', undefined, 's:' + id);
    wantHistory(id, data, fresh);
    if (had && had.phase === 'ok' && JSON.stringify(had.data) === JSON.stringify(data)) { trimCaches(); return true; }
    S.sess[id] = { phase: 'ok', data };
    trimCaches();
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    if (e instanceof Aborted) { // left or put away while it was coming: nothing was learned, and no "Loading…" is left behind
      if (placeholder && S.sess[id] === placeholder) delete S.sess[id];
      return null;
    }
    if (e.status === 404) S.sess[id] = had && had.data ? { ...had, gone: true } : { phase: 'missing', data: null };
    else if (!had || !had.data) S.sess[id] = { phase: 'error', data: null, down: e instanceof Down };
    else return false; // kept what we had; the caller may try again
  }
  const r = route();
  if (S.view === 'app' && r.name === 'session' && r.id === id) render();
  return true;
}

function gotState(st) {
  if (S.view === 'pair') return; // a late reply from before we were signed out
  S.lastOk = Date.now();
  const wasApp = S.view === 'app';
  const sig = JSON.stringify(st, (k, v) => (k === 'updatedAt' ? undefined : v));
  S.state = st;
  applyBadge();
  pill();
  if (!wasApp) {
    S.view = 'app';
    S.sig = sig;
    connect();
    enterRoute();
    render(true);
    return;
  }
  if (sig === S.sig) return;
  S.sig = sig;
  const r = route();
  const showsState = S.split ? S.side.tab === 'now' || r.name === 'session' : r.name === 'now' || r.name === 'session';
  if (!showsState) return;
  render();
  // The open session is read again only when the state says it changed, and at most every 10 s.
  if (r.name === 'session' && JSON.stringify(lookup(r.id)) !== S.sessSig[r.id]) fetchSoon(r.id);
}

function fetchSoon(id) {
  clearTimeout(S.sessTimer);
  const wait = Math.max(0, 10000 - (Date.now() - (S.sessAt[id] || 0)));
  if (!wait) { loadSession(id); return; }
  S.sessTimer = setTimeout(() => {
    const r = route();
    if (S.view === 'app' && r.name === 'session' && r.id === id && !document.hidden) loadSession(id);
  }, wait);
}

/* ---------- live stream ---------- */

function connect() {
  disconnect();
  if (document.hidden || S.view !== 'app' || !('EventSource' in window)) return;
  const es = new EventSource('/api/events');
  S.es = es;
  es.addEventListener('state', (ev) => {
    try { gotState(JSON.parse(ev.data)); } catch { /* ignore a bad frame */ }
  });
  es.onopen = () => { S.backoff = 0; };
  es.onerror = () => {
    // While it is still CONNECTING the browser retries by itself. CLOSED means
    // it gave up (401, 5xx, Mac gone): find out why, then try again later.
    if (S.es !== es || es.readyState !== EventSource.CLOSED) return;
    S.es = null;
    refresh(false);
    S.backoff = Math.min((S.backoff || 1500) * 2, 30000);
    S.esTimer = setTimeout(connect, S.backoff);
  };
}

function disconnect() {
  clearTimeout(S.esTimer);
  if (S.es) S.es.close();
  S.es = null;
}

/* ---------- ticking: clocks, relative times, quiet polling, stale note ---------- */

function startTicker() {
  if (!S.tickTimer) S.tickTimer = setInterval(tick, 1000);
}
function stopTicker() {
  clearInterval(S.tickTimer);
  S.tickTimer = 0;
}

function tick() {
  const now = Date.now();
  S.n++;
  for (const el of root.querySelectorAll('.clock')) {
    const t = +el.dataset.t;
    el.textContent = Number.isFinite(t) ? mmss(now - t) : '–:––';
  }
  if (S.n % 20 === 0) for (const el of root.querySelectorAll('time.rel')) el.textContent = ago(el._ms);
  if (S.n % 20 === 0) for (const el of root.querySelectorAll('[data-pre]')) el.textContent = el.dataset.pre + spanText(+el.dataset.from, el.dataset.to ? +el.dataset.to : NaN);
  if (S.view === 'app') {
    // Keepalive comments never reach page code, so poll when the stream is quiet.
    if (now - S.lastOk > 30000 && !S.refreshing && now - S.lastTry > 25000) refresh(false);
    pill();
    syncLive(); // a quiet spell may be over
  } else if (S.view === 'offline' && !S.refreshing && now - S.lastTry > 15000) {
    refresh(true);
  }
}

function pill() {
  const p = $('pill');
  const stale = S.view === 'app' && !S.refreshing && Date.now() - S.lastOk > 60000;
  if (!stale) { p.hidden = true; return; }
  if (p.hidden) {
    p.replaceChildren(h('span', { id: 'pill-t' }), h('button', { type: 'button', text: 'Retry', onclick: () => refresh(true) }));
    p.hidden = false;
  }
  $('pill-t').textContent = 'Not updating since ' + when(S.lastOk);
}

function onVisible() {
  if (document.hidden) return;
  startTicker();
  if (S.view === 'app' || S.view === 'offline') {
    refresh(true);
    if (S.view === 'app') {
      connect();
      resumeRoute();
      parkImages(false);
      syncLive();
    }
  }
}

// Asks again for what the screen was waiting on when the page was put away (`onHidden` dropped it), and for nothing it already has.
function resumeRoute() {
  const r = route();
  if (r.id && (r.name === 'session' || !S.sess[r.id])) loadSession(r.id); // a history that never arrived is read again with it (wantHistory)
  if (r.id && browseOn() && !art(r.id).loaded) loadArtifacts(r.id);
  if (r.name === 'file') maybeLoadText(r.v, r.id);
  const pid = S.split ? S.side.pid : r.name === 'project' ? r.pid : null;
  if (pid && browseOn() && !proj(pid).loaded) loadProject(pid, false);
}
function onHidden() {
  stopTicker();
  disconnect();
  abortScopes();
  parkImages(true);
  syncLive();
  trimCaches();
}

/* ---------- routing ---------- */

const RE = { sid: /^[0-9a-f-]{36}$/, pid: /^[A-Za-z0-9_-]{1,64}$/, vid: /^[A-Za-z0-9_-]{1,128}$/ };
const browseOn = () => !S.me || S.me.browse !== false;
// Names an object already has: never taken as an id from the address.
const RESERVED = new Set(['__proto__', 'constructor', 'prototype']);

function routeOf(hash) {
  const p = (hash || '').replace(/^#/, '') || '/';
  let m;
  if ((m = p.match(/^\/session\/([0-9a-f-]{36})\/file\/([A-Za-z0-9_-]{1,128})$/))) return RESERVED.has(m[2]) ? { name: 'now' } : { name: 'file', id: m[1], v: m[2] };
  if ((m = p.match(/^\/session\/([0-9a-f-]{36})\/artifacts$/))) return { name: 'artifacts', id: m[1] };
  if ((m = p.match(/^\/session\/([0-9a-f-]{36})$/))) return { name: 'session', id: m[1] };
  if ((m = p.match(/^\/projects\/([A-Za-z0-9_-]{1,64})$/))) return RESERVED.has(m[1]) ? { name: 'now' } : { name: 'project', pid: m[1] };
  if (p === '/projects') return { name: 'projects' };
  if (p === '/settings') return { name: 'settings' };
  return { name: 'now' };
}

// With browsing switched off on the Mac the Projects, History and Artifacts parts do not exist.
function route() {
  const r = routeOf(location.hash);
  if (browseOn()) return r;
  if (r.name === 'projects' || r.name === 'project') return { name: 'now' };
  if (r.name === 'artifacts' || r.name === 'file') return { name: 'session', id: r.id };
  return r;
}
const routeKey = (r = route()) => [r.name, r.pid || '', r.id || '', r.v || ''].join('|');

// The iPad sidebar follows the list screens; a session, its files and Settings leave it as it was.
function syncSide(r = route()) {
  if (r.name === 'now') S.side = { tab: 'now', pid: null };
  else if (r.name === 'projects') S.side = { tab: 'projects', pid: null };
  else if (r.name === 'project') S.side = { tab: 'projects', pid: r.pid };
  else return;
  S.from = { name: r.name, pid: r.pid || null };
}

// Where a session's Back goes, by the list it was opened from.
function sessionBack() {
  const f = S.from;
  if (f && f.name === 'projects') return ['Projects', '#/projects'];
  if (f && f.name === 'project') return [projName(f.pid), '#/projects/' + f.pid];
  return ['Now', '#/'];
}

function ensureBrowse(r) {
  if (!browseOn()) return;
  const t = S.split ? S.side : r.name === 'projects' ? { tab: 'projects', pid: null } : r.name === 'project' ? { tab: 'projects', pid: r.pid } : null;
  if (t && t.tab === 'projects') {
    loadProjects();
    if (t.pid && !proj(t.pid).loaded) loadProject(t.pid, false);
  }
}

function enterRoute() {
  const r = route();
  syncSide(r);
  syncScopes(); // reads for a screen no longer wanted are dropped before the new one's are asked for
  if (!S.me) loadMe();
  if (r.name === 'settings') { loadMe(); loadPush(); }
  if (r.name === 'session') {
    loadSession(r.id);
    if (browseOn()) loadArtifacts(r.id);
  }
  if (r.name === 'artifacts') {
    if (!S.sess[r.id]) loadSession(r.id);
    loadArtifacts(r.id);
  }
  if (r.name === 'file') {
    if (!S.sess[r.id]) loadSession(r.id);
    if (S.files[r.v]) maybeLoadText(r.v, r.id); else loadArtifacts(r.id);
  }
  ensureBrowse(r);
  trimCaches();
}

addEventListener('hashchange', () => {
  if (!S.split) S.scroll[S.rk] = window.scrollY;
  S.navs++;
  S.prevKey = S.rk;
  S.rk = routeKey();
  if (S.view === 'app') enterRoute();
  render(true);
  if (!S.split) window.scrollTo(0, /^(now|projects?)\|/.test(S.rk) ? S.scroll[S.rk] || 0 : 0);
});

/* ---------- rendering ---------- */

// `force` skips the in-place patch: used when the data a screen shows has just arrived.
function render(fresh = false, force = false) {
  const r = route();
  if (!fresh && !force && S.view === 'app' && patchApp(r)) return;
  const active = document.activeElement;
  const keep = !fresh && active && active.dataset ? active.dataset.key : '';
  // The two split panes scroll on their own: carry their positions across.
  const oldSide = root.querySelector('.side-pane');
  const oldDetail = root.querySelector('.detail');
  const sideTop = oldSide ? oldSide.scrollTop : 0;
  const detailTop = oldDetail ? oldDetail.scrollTop : 0;
  let tree = null;
  if (S.view === 'pair') tree = pairView();
  else if (S.view === 'offline') tree = offlineView();
  else if (S.view === 'app') tree = S.split ? splitView(r) : singleView(r);
  replaceContents(root, ...(tree ? [tree] : []));
  const side = root.querySelector('.side-pane');
  const detail = root.querySelector('.detail');
  if (side) side.scrollTop = sideTop;
  if (detail && !fresh) detail.scrollTop = detailTop;
  watchTitle();
  if (keep) {
    const again = root.querySelector(`[data-key="${CSS.escape(keep)}"]`);
    if (again) again.focus({ preventScroll: true });
  } else if (fresh) {
    const t = root.querySelector('.detail h1') || root.querySelector('h1');
    if (t) t.focus({ preventScroll: true });
  }
  syncLive();
}

const detailKey = (r) => (['session', 'artifacts', 'file', 'settings'].includes(r.name) ? routeKey(r) : 'empty');
const sideKey = () => S.side.tab + ':' + (S.side.pid || '');

// The screen is already up: refresh what changed without rebuilding it (and without losing a keyboard).
function patchApp(r) {
  const split = root.querySelector('.split');
  if (!!split !== S.split) return false;
  if (S.split) {
    if (split.dataset.dk !== detailKey(r) || split.dataset.sk !== sideKey()) return false;
    if (S.side.tab === 'now' || !browseOn()) refreshSide();
    if (r.name === 'session') {
      const sv = root.querySelector('.sessview');
      if (!sv) return false;
      fillSession(sv, r.id);
    }
    return true;
  }
  if (r.name !== 'session') return false;
  const sv = root.querySelector('.sessview');
  if (!sv || sv.dataset.sess !== r.id) return false;
  const t = root.querySelector('.bar-t');
  if (t) t.textContent = sessionTitle(r.id);
  fillSession(sv, r.id);
  return true;
}

function refreshSide() {
  const side = root.querySelector('.side-pane');
  if (!side) return;
  const top = side.scrollTop;
  const active = document.activeElement;
  const key = active && side.contains(active) ? active.dataset.key : '';
  side.querySelector('.pane-in').replaceChildren(...sideContent().filter(Boolean));
  side.scrollTop = top;
  if (key) { const again = side.querySelector(`[data-key="${CSS.escape(key)}"]`); if (again) again.focus({ preventScroll: true }); }
  watchTitle();
}

// A list screen: a bar, the content, and the tab bar when there is more than one tab.
function screen(header, content, tab) {
  const tabs = tab ? tabbar(tab) : null;
  return h('div', { class: tabs ? 'has-tabs' : null }, header, h('main', { class: 'wrap' }, content), tabs);
}

function tabbar(active) {
  if (!browseOn()) return null;
  const tab = (href, label, name, ic) => h('a', { class: 'tab', href, 'aria-current': active === name ? 'page' : null }, icon(ic), h('span', { text: label }));
  return h('nav', { class: 'tabbar', 'aria-label': 'Sections' }, tab('#/', 'Now', 'now', 'clock'), tab('#/projects', 'Projects', 'projects', 'folder'));
}

const composeButton = (pid) => h('button', { class: 'icon-btn', type: 'button', 'aria-label': 'New session', onclick: () => newSessionSheet(pid) }, icon('compose'));
const shortTitle = (t) => (t.length > 24 ? t.slice(0, 23) + '…' : t);

function singleView(r) {
  switch (r.name) {
    case 'session': return sessionView(r.id, false);
    case 'settings': return screen(bar('Settings', backLink('Now'), null), settingsContent());
    case 'projects': return screen(bar('Projects', null, [refreshButton()]), projectsContent(), 'projects');
    case 'project': return screen(bar(projName(r.pid), backLink('Projects', '#/projects'), composeButton(r.pid)), projectContent(r.pid), 'projects');
    case 'artifacts': return screen(bar('Artifacts', backLink(shortTitle(sessionTitle(r.id)), '#/session/' + r.id), refreshButton()), artifactsContent(r.id));
    case 'file': return screen(bar(fileName(r.v), backLink('Artifacts', '#/session/' + r.id + '/artifacts'), null), fileContent(r.id, r.v));
    default: return screen(bar('Now', null, [refreshButton(), settingsLink()]), nowContent(), 'now');
  }
}

function sideBar() {
  if (!browseOn()) return bar('Now', null, [refreshButton(), settingsLink()]);
  const seg = (href, label, name) => h('a', { class: 'seg-b', href, role: 'tab', 'aria-selected': S.side.tab === name ? 'true' : 'false', 'aria-current': S.side.tab === name ? 'page' : null, text: label });
  return h('header', { class: 'bar' }, h('div', { class: 'bar-in side-bar' },
    h('div', { class: 'seg', role: 'tablist', 'aria-label': 'Sections' }, seg('#/', 'Now', 'now'), seg('#/projects', 'Projects', 'projects')),
    h('div', { class: 'bar-r' }, [refreshButton(), settingsLink()])));
}

function sideContent() {
  if (!browseOn() || S.side.tab === 'now') return nowContent();
  if (!S.side.pid) return projectsContent();
  return [h('a', { class: 'back-row', href: '#/projects' }, icon('left'), h('span', { text: 'Projects' })), ...projectContent(S.side.pid)];
}

const crumb = (href, label) => h('a', { class: 'crumb', href }, icon('left', 'sm'), h('span', { text: label }));

function splitView(r) {
  let detail;
  if (r.name === 'session') detail = sessionView(r.id, true);
  else {
    const body = r.name === 'settings' ? settingsContent()
      : r.name === 'artifacts' ? [crumb('#/session/' + r.id, shortTitle(sessionTitle(r.id))), ...artifactsContent(r.id)]
      : r.name === 'file' ? [crumb('#/session/' + r.id + '/artifacts', 'Artifacts'), ...fileContent(r.id, r.v)]
      : emptyDetail();
    detail = h('div', { class: 'detail-col' }, h('div', { class: 'detail-body' },
      h('div', { class: 'detail-in' + (detailKey(r) === 'empty' ? ' nothing' : '') }, body)));
  }
  return h('div', { class: 'split', 'data-dk': detailKey(r), 'data-sk': sideKey() },
    h('nav', { class: 'pane side-pane', 'aria-label': 'Sessions' }, sideBar(), h('div', { class: 'pane-in' }, sideContent())),
    h('main', { class: 'pane detail' }, detail));
}

function emptyDetail() {
  return [
    h('img', { class: 'tile', src: '/icon-180.png', width: '72', height: '72', alt: '' }),
    h('h1', { tabindex: '-1', text: 'Select a session' }),
    h('p', { text: 'Its status, and its plan where there is one, will appear here.' }),
  ];
}

let titleWatcher;
function watchTitle() {
  if (titleWatcher) titleWatcher.disconnect();
  const scope = root.querySelector('.side-pane') || root;
  const t = scope.querySelector('h1.large');
  const header = scope.querySelector('.bar');
  if (!t || !header || !('IntersectionObserver' in window)) return;
  titleWatcher = new IntersectionObserver(([e]) => header.classList.toggle('scrolled', !e.isIntersecting), {
    root: scope === root ? null : scope,
    rootMargin: '-56px 0px 0px 0px',
  });
  titleWatcher.observe(t);
}

function bar(title, left, right) {
  return h('header', { class: 'bar' },
    h('div', { class: 'bar-in' },
      h('div', { class: 'bar-l' }, left),
      h('div', { class: 'bar-t', 'aria-hidden': 'true', text: title }),
      h('div', { class: 'bar-r' }, right)));
}

function backLink(label, href = '#/') {
  return h('a', {
    class: 'back',
    href,
    'aria-label': 'Back to ' + label,
    onclick: (e) => {
      // pop the history when the screen before this one is where Back goes; otherwise follow the link
      if (S.navs > 0 && S.prevKey === routeKey(routeOf(href))) { e.preventDefault(); history.back(); }
    },
  }, icon('left'), h('span', { text: label }));
}

function refreshButton() {
  return h('button', {
    class: 'icon-btn',
    type: 'button',
    'aria-label': 'Refresh',
    onclick: async (e) => {
      const b = e.currentTarget;
      b.classList.add('spin');
      await refreshAll(true);
      b.classList.remove('spin');
    },
  }, icon('refresh'));
}

const settingsLink = () => h('a', { class: 'icon-btn', href: '#/settings', 'aria-label': 'Settings', 'aria-current': S.split && route().name === 'settings' ? 'page' : null }, icon('gear'));

function section(title, count, body, cls = '') {
  const id = 'h-' + title.toLowerCase().replace(/\W+/g, '-');
  return h('section', { class: 'sec', 'aria-labelledby': id },
    h('h2', { class: 'sec-h ' + cls, id }, title, count ? h('span', { class: 'count', text: String(count) }) : null),
    body);
}

const list = (items) => h('ul', { class: 'group' }, items);
const emptyCard = (text) => h('div', { class: 'group' }, h('div', { class: 'empty', text }));
const sessionHref = (id) => '#/session/' + encodeURIComponent(id);

function subLine(project, tail) {
  return h('span', { class: 'sub' }, project || null, project && tail ? ' · ' : null, tail);
}

function snoozeText(z) {
  if (!z) return '';
  const until = z.until ? Date.parse(z.until) : NaN;
  if (until > Date.now()) return 'Reminds you at ' + when(until);
  if (z.afterFocus) return 'Reminds you after your focus session';
  return '';
}

/* ---------- Now ---------- */

// Splits show the open session's row with a quiet tint.
const current = (id) => (S.split && route().id === id ? 'page' : null);

function needsRow(n) {
  const z = snoozeText(n.snooze);
  return h('li', null,
    h('a', { class: 'row', href: sessionHref(n.id), 'data-key': 'n:' + n.id, 'aria-current': current(n.id) },
      h('span', { class: 'row-main' },
        h('span', { class: 'reason' }, h('span', { class: 'dot', 'aria-hidden': 'true' }), n.sentence || 'Needs you'),
        h('span', { class: 'title', text: n.title }),
        subLine(n.project, rel(n.since)),
        z ? h('span', { class: 'snooze', text: z }) : null),
      icon('chev', 'sm chev')));
}

function failedRow(f) {
  return h('li', null,
    h('a', { class: 'row', href: sessionHref(f.id), 'data-key': 'f:' + f.id, 'aria-current': current(f.id) },
      h('span', { class: 'row-main' },
        h('span', { class: 'reason' }, icon('alert', 'sm mark-err'), 'Stopped with an error'),
        h('span', { class: 'title', text: f.title }),
        subLine(f.project, rel(f.since))),
      icon('chev', 'sm chev')));
}

// A used-up plan limit holds this working session (`paused` on its row in the state; the state's `pause` says until
// when): nothing is happening in it, so no pulsing dot, no clock and no live text, but "Paused". Each session has its
// own: one still writing isn't paused because another waits.
const heldBy = (id) => {
  const snap = lookup(id);
  return !!(snap && snap.bucket === 'working' && snap.paused === true);
};
// A session's own data says `running`; the state stream's lists say `working`.
const runs = (state) => state === 'running' || state === 'working';

// When a paused session resumes, in this phone's own time zone and language (`tz` and `locale` are for the tests):
// "Resumes at 3:40 PM", "Resumes tomorrow at 9:00 AM", "Resumes Friday at 9:00 AM", "Resumes on Oct 22 at 9:00 AM".
// Without a time it can read, "Resumes when your limit resets": never the Mac's `sentence`, which is in the Mac's zone.
function resumeSentence(pause, now = Date.now(), tz, locale) {
  const until = pause && typeof pause.until === 'string' ? Date.parse(pause.until) : NaN;
  if (!Number.isFinite(until)) return 'Resumes when your limit resets';
  if (until <= now) return 'Resumes shortly';
  const opts = (o) => (tz ? { ...o, timeZone: tz } : o);
  const time = new Intl.DateTimeFormat(locale, opts({ hour: 'numeric', minute: '2-digit' })).format(until);
  // The calendar day of a moment where the phone is, as a number of days, to count the days between.
  const day = (t) => {
    const parts = new Intl.DateTimeFormat('en-US', opts({ year: 'numeric', month: 'numeric', day: 'numeric' })).formatToParts(t);
    const part = (type) => Number((parts.find((x) => x.type === type) || {}).value);
    return Date.UTC(part('year'), part('month') - 1, part('day')) / 86400000;
  };
  const days = Math.round(day(until) - day(now));
  if (!Number.isFinite(days) || days <= 0) return 'Resumes at ' + time;
  if (days === 1) return 'Resumes tomorrow at ' + time;
  if (days < 7) return 'Resumes ' + new Intl.DateTimeFormat(locale, opts({ weekday: 'long' })).format(until) + ' at ' + time;
  return 'Resumes on ' + new Intl.DateTimeFormat(locale, opts({ month: 'short', day: 'numeric' })).format(until) + ' at ' + time;
}

function workingRow(w) {
  const held = w.paused === true;
  return h('li', null,
    h('a', { class: 'row', href: sessionHref(w.id), 'data-key': 'w:' + w.id + (held ? ':p' : ''), 'aria-current': current(w.id) },
      h('span', { class: held ? 'dot idle' : 'dot live', 'aria-hidden': 'true' }),
      h('span', { class: 'row-main' },
        h('span', { class: 'title', text: w.title }),
        subLine(w.project, null)),
      h('span', { class: 'side' }, held ? 'Paused' : clockEl(w.startedAt)),
      icon('chev', 'sm chev')));
}

function recentRow(r) {
  return h('li', null,
    h('a', { class: 'row', href: sessionHref(r.id), 'data-key': 'r:' + r.id + r.at, 'aria-current': current(r.id) },
      h('span', { class: 'row-main' },
        h('span', { class: 'title', text: r.title }),
        subLine(r.project, r.line)),
      h('span', { class: 'side' }, rel(r.at)),
      icon('chev', 'sm chev')));
}

function usageSection(u) {
  const limits = (u && u.limits) || [];
  if (!limits.length) return null;
  return section('Usage', 0, h('ul', { class: 'group' }, limits.map((l) => {
    const pct = Math.max(0, Math.min(100, Math.round(Number(l.usedPercent) || 0)));
    const pace = l.pace || (l.resetsAt ? 'Resets at ' + when(l.resetsAt) : '');
    return h('li', { class: 'usage' },
      h('div', { class: 'u-top' },
        h('span', { class: 'u-name', text: l.name }),
        h('span', null, pct >= 90 ? h('span', { class: 'u-flag', text: 'Near the limit' }) : null, h('span', { class: 'u-pct', text: pct + '%' }))),
      h('progress', { max: '100', value: String(pct), class: pct >= 90 ? 'hot' : null, 'aria-label': (l.name || 'Usage') + ' used' }),
      pace ? h('div', { class: 'u-pace', text: pace }) : null);
  })));
}

/* ---------- Since you left ----------
   The state's `since` (version 1) says what changed while the person was away from the Mac: the counts, the sessions that
   ask, finished and stopped (at most six rows), and how long. An older Capsid sends none and an older page ignores it.
   The question, its choices and the last words of a finished session are read from the session's own screen data
   (`/api/sessions/<id>`), a few at a time and once each; a finished row's picture is its artifacts' first image. */

// "2 h 14 min", "1 h 5 min", "45 min", "1 h", "1 d 3 h".
function awaySpan(minutes) {
  const m = Math.max(1, Math.round(minutes));
  const d = Math.floor(m / 1440);
  const hh = Math.floor((m % 1440) / 60);
  const mm = m % 60;
  if (d) return hh ? `${d} d ${hh} h` : `${d} d`;
  if (hh) return mm ? `${hh} h ${mm} min` : `${hh} h`;
  return `${mm} min`;
}

// "3 finished, 1 stopped, 1 needs you": the groups that have something in them.
function sinceHeadline(c) {
  const n = (k) => Math.max(0, Math.floor(Number(c && c[k]) || 0));
  const parts = [];
  if (n('finished')) parts.push(n('finished') + ' finished');
  if (n('stopped')) parts.push(n('stopped') + ' stopped');
  if (n('needs')) parts.push(n('needs') === 1 ? '1 needs you' : n('needs') + ' need you');
  return parts.join(', ');
}

// The `since` of the state when it is one this page reads and has something to say; else null.
function sinceOf(st) {
  const sn = st && st.since;
  if (!sn || typeof sn !== 'object' || sn.v !== 1 || !Number.isFinite(Date.parse(sn.awayAt))) return null;
  const list = (k) => (Array.isArray(sn[k]) ? sn[k].filter((x) => x && RE.sid.test(String(x.id))) : []);
  const out = { sn, asks: list('asks'), finished: list('finished'), stopped: list('stopped') };
  return sinceHeadline(sn.counts) && (out.asks.length || out.finished.length || out.stopped.length) ? out : null;
}

const spanText = (from, to) => awaySpan(((Number.isFinite(to) ? to : Date.now()) - from) / 60000);
const liveSpan = (cls, prefix, from, to) => {
  const el = h('span', { class: cls });
  el.dataset.from = String(from);
  el.dataset.to = Number.isFinite(to) ? String(to) : '';
  el.dataset.pre = prefix;
  el.textContent = prefix + spanText(from, to);
  return el;
};

// What the page has asked for, once each: a session screen's data for the first asks and finished rows, the artifacts of
// the first finished rows. Asked for again only for a new stretch (`awayAt`).
const SINCE_ASKS = 2;
const SINCE_ROWS = 4;
function wantSince(v) {
  const key = v.sn.awayAt;
  if (S.sinceKey !== key) { S.sinceKey = key; S.sinceAsked = dict(); S.sinceNote = dict(); }
  const again = () => { if (S.view === 'app' && (S.split ? S.side.tab === 'now' : route().name === 'now')) render(false, true); };
  const ask = (id, what, run) => {
    if (S.sinceAsked[what + id]) return;
    S.sinceAsked[what + id] = true;
    Promise.resolve(run()).then(again, again);
  };
  v.asks.slice(0, SINCE_ASKS).forEach((a) => { if (!S.sess[a.id]) ask(a.id, 's', () => loadSession(a.id)); });
  v.finished.slice(0, SINCE_ROWS).forEach((f) => {
    if (!f.line && !S.sess[f.id]) ask(f.id, 's', () => loadSession(f.id));
    if (browseOn() && !art(f.id).loaded) ask(f.id, 'a', () => loadArtifacts(f.id));
  });
}

// The one question with options to pick from, when that is what a session asks.
function singleChoice(q) {
  if (!q || !Array.isArray(q.items) || q.items.length !== 1) return null;
  const item = q.items[0];
  return item && !item.multi && Array.isArray(item.options) && item.options.length ? { toolId: q.toolId, question: item.question, header: item.header, options: item.options } : null;
}

// A choice is the answer: the same write as the session screen's Send answer, to the same route.
async function sinceAnswer(id, q, label) {
  const u = ui(id);
  if (u.busy.question) return;
  u.busy.question = true;
  S.sinceNote[id] = '';
  render(false, true);
  let result;
  try {
    result = describe(await send('/api/sessions/' + id + '/answer', { toolId: q.toolId, answers: { [q.question]: label } }));
  } catch (e) {
    if (e instanceof Unauth) { u.busy.question = false; return showPair(); }
    result = { ok: false, refetch: false, text: 'Couldn’t reach your Mac. Try again.' };
  }
  u.busy.question = false;
  S.sinceNote[id] = result.text;
  if (result.refetch) { await loadSession(id, true); refresh(false); }
  if (S.view === 'app') render(false, true);
}

function sinceAskCard(a) {
  const d = S.sess[a.id] && S.sess[a.id].data;
  const q = d && d.can && d.can.answer ? singleChoice(d.question) : null;
  const busy = !!ui(a.id).busy.question;
  const note = S.sinceNote && S.sinceNote[a.id];
  const waiting = Date.parse(a.since);
  return h('div', { class: 'since-card', 'data-key': 'sa:' + a.id },
    h('span', { class: 'since-reason' }, a.sentence || 'Needs you', Number.isFinite(waiting) ? liveSpan('since-live', ' · ', waiting) : null),
    h('a', { class: 'since-title', href: sessionHref(a.id), text: a.title }),
    q ? h('p', { class: 'since-q', text: q.question }) : null,
    ...(q ? q.options.map((o, k) => h('button', {
      class: 'since-choice', type: 'button', text: o.label, disabled: busy, 'data-key': 'sc:' + a.id + ':' + k,
      onclick: () => sinceAnswer(a.id, q, o.label),
    })) : [h('a', { class: 'since-choice since-go', href: sessionHref(a.id), text: d && d.question ? 'Answer…' : 'Open' })]),
    note ? h('p', { class: 'since-note', role: 'status', text: note }) : null);
}

// A finished row's picture: the first image its artifacts list, else a tile with the kind of its first file.
function sinceTile(f) {
  const A = browseOn() ? art(f.id) : null;
  const img = A && A.loaded ? A.items.find((x) => x.kind === 'image') : null;
  if (img) {
    return h('span', { class: 'since-pic', 'aria-hidden': 'true' }, fileImg({ alt: '', width: '104', height: '104' }, '/api/files/' + img.v + '/thumb?w=120', (el) => el.replaceWith(icon('image', 'sm'))));
  }
  const other = A && A.loaded ? A.items[0] : null;
  const ext = other ? (String(other.name || '').split('.').pop() || '').toUpperCase() : '';
  return h('span', { class: 'since-pic kind', 'aria-hidden': 'true' }, ext && ext.length <= 5 && ext !== String(other.name || '').toUpperCase() ? ext : icon('doc', 'sm'));
}

function sinceFinishedRow(f) {
  const d = S.sess[f.id] && S.sess[f.id].data;
  const line = f.line || (d && d.reply && typeof d.reply.text === 'string' ? d.reply.text : '');
  return h('a', { class: 'since-row', href: sessionHref(f.id), 'data-key': 'sf:' + f.id },
    sinceTile(f),
    h('span', { class: 'since-main' }, h('span', { class: 'since-title', text: f.title }), line ? h('span', { class: 'since-line', text: sinceLine(line) }) : null));
}

// The first lines of an answer as one short line of plain words (the page clamps it to two).
function sinceLine(text) {
  const plain = String(text).replace(/```[\s\S]*?```/g, ' ').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/^[#>\-*+\s]+/gm, '').replace(/[*`]/g, '').replace(/\s+/g, ' ').trim();
  return plain.length > 140 ? plain.slice(0, 139).replace(/\s+\S*$/, '') + '…' : plain;
}

function sinceStoppedRow(x) {
  return h('a', { class: 'since-row', href: sessionHref(x.id), 'data-key': 'ss:' + x.id },
    h('span', { class: 'since-main' }, h('span', { class: 'since-title', text: x.title }),
      h('span', { class: 'since-line err', text: x.reason ? sinceLine(x.reason) : 'Stopped with an error' })));
}

// The header and the body; the header takes the place of the large "Now".
function sinceHead(v) {
  const from = Date.parse(v.sn.awayAt);
  const to = v.sn.back ? Date.parse(v.sn.back) : NaN;
  return h('header', { class: 'since-head' },
    liveSpan('since-over', 'Since you left · ', from, to),
    h('h1', { class: 'since-h', tabindex: '-1', text: sinceHeadline(v.sn.counts) }));
}

function sinceBody(v) {
  wantSince(v);
  const more = Math.max(0, Math.floor(Number(v.sn.more) || 0));
  return h('section', { class: 'since', 'aria-label': 'Since you left' },
    ...v.asks.map(sinceAskCard),
    v.finished.length ? h('h2', { class: 'since-label', text: 'Finished' }) : null,
    ...v.finished.map(sinceFinishedRow),
    v.stopped.length ? h('h2', { class: 'since-label', text: 'Stopped' }) : null,
    ...v.stopped.map(sinceStoppedRow),
    more ? h('p', { class: 'since-more', text: 'and ' + more + ' more, under Recent' }) : null);
}

function nowContent() {
  const st = S.state;
  const since = sinceOf(st);
  // What the section shows is not listed again below it.
  const shown = new Set(since ? [...since.asks, ...since.stopped].map((x) => x.id) : []);
  const needs = (st.needsYou || []).filter((n) => !shown.has(n.id));
  const failed = (st.failed || []).filter((f) => !shown.has(f.id));
  const working = st.working || [];
  const recent = st.recent || [];
  return [
    since ? sinceHead(since) : h('h1', { class: 'large', tabindex: '-1', text: 'Now' }),
    since ? sinceBody(since) : null,
    st.problem ? h('div', { class: 'banner', role: 'status' }, icon('alert'), h('span', { text: st.problem })) : null,
    st.pause ? h('div', { class: 'banner', role: 'status' }, icon('pause'),
      h('span', { text: 'Your usage limit is used up, so sending is paused. ' + resumeSentence(st.pause) })) : null,
    since && !needs.length && since.asks.length ? null : section('Needs you', needs.length, needs.length ? list(needs.map(needsRow)) : emptyCard('Nothing needs you')),
    failed.length ? section('Stopped with an error', failed.length, list(failed.map(failedRow))) : null,
    section('Working', 0, working.length ? list(working.map(workingRow)) : emptyCard('Nothing working right now')),
    recent.length ? section('Recent', 0, list(recent.map(recentRow))) : null,
    usageSection(st.usage),
  ];
}

/* ---------- a small, safe markdown subset: DOM nodes only, never innerHTML ----------
   Paragraphs, bullet and numbered lists, **bold**, *italic*, `inline code`, fenced
   code blocks. Everything else, links included, stays plain text. */

const txt = (s) => document.createTextNode(s);

// md(text, { image(src) -> a version id or null }). An image shows only when `image` names one of
// this session's own listed images; anything else is its alt text. Links are always plain words.
let mdImage = null;

function inline(s, depth = 0) {
  const out = [];
  const re = /`([^`\n]+)`|\*\*([^*\n]+?)\*\*|\*([^*\s][^*\n]*?)\*|!\[([^\]\n]*)\]\(([^)\s]*)\)|\[([^\]\n]*)\]\(([^)\s]*)\)/g;
  let last = 0;
  let m;
  while ((m = re.exec(s))) {
    if (m.index > last) out.push(txt(s.slice(last, m.index)));
    if (m[1] != null) out.push(h('code', { text: m[1] }));
    else if (m[2] != null) out.push(h('strong', null, depth < 3 ? inline(m[2], depth + 1) : txt(m[2])));
    else if (m[3] != null) out.push(h('em', null, depth < 3 ? inline(m[3], depth + 1) : txt(m[3])));
    else if (m[5] != null) {
      const v = mdImage ? mdImage(m[5]) : null;
      if (v && RE.vid.test(v)) {
        const alt = m[4];
        out.push(fileImg({ class: 'md-img', alt }, '/api/files/' + v + '/thumb?w=800', (img) => img.replaceWith(txt(alt || 'image'))));
      } else out.push(txt(m[4] || 'image'));
    } else out.push(txt(m[7] && m[7] !== m[6] ? `${m[6]} (${m[7]})` : m[6] || m[7])); // a link is just its words
    last = re.lastIndex;
  }
  if (last < s.length) out.push(txt(s.slice(last)));
  return out;
}

function mdLines(lines) {
  const out = [];
  lines.forEach((l, i) => { if (i) out.push(h('br')); out.push(...inline(l)); });
  return out;
}

function md(src, ctx) {
  mdImage = ctx && ctx.image ? ctx.image : null;
  const lines = String(src == null ? '' : src).slice(0, 20000).replace(/\r\n?/g, '\n').split('\n');
  const out = [];
  const bullet = /^(\s*)[-*+]\s+(.*)$/;
  const ordered = /^(\s*)(\d{1,3})[.)]\s+(.*)$/;
  const fence = /^\s*(`{3,}|~{3,})/;
  const rule = /^\s*([-*_])(\s*\1){2,}\s*$/;
  const table = /^\s*\|.*\|\s*$/;
  const special = (l) => fence.test(l) || bullet.test(l) || ordered.test(l) || rule.test(l) || table.test(l) || /^\s*(#{1,6}|>)\s/.test(l);
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const f = line.match(fence);
    if (f) {
      const body = [];
      const closer = new RegExp('^\\s*' + (f[1][0] === '`' ? '`' : '~') + '{' + f[1].length + ',}\\s*$');
      for (i++; i < lines.length && !closer.test(lines[i]); i++) body.push(lines[i]);
      i++;
      out.push(h('pre', { class: 'md-pre', tabindex: '0' }, h('code', { text: body.join('\n') })));
      continue;
    }
    if (!line.trim() || rule.test(line)) { i++; continue; }
    if (table.test(line)) {
      const rows = [];
      while (i < lines.length && table.test(lines[i])) rows.push(lines[i++]);
      out.push(h('pre', { class: 'md-pre', tabindex: '0' }, h('code', { text: rows.join('\n') })));
      continue;
    }
    const b = line.match(bullet);
    const o = line.match(ordered);
    if (b || o) {
      const isOl = !!o;
      const list = h(isOl ? 'ol' : 'ul', { class: 'md-list', start: isOl ? String(parseInt(o[2], 10) || 1) : null });
      while (i < lines.length) {
        const mb = lines[i].match(bullet);
        const mo = lines[i].match(ordered);
        if (isOl ? mo : mb) {
          const indent = Math.min(2, Math.floor((isOl ? mo[1] : mb[1]).length / 2));
          const item = h('li', { class: indent ? 'ind' + indent : null }, inline(isOl ? mo[3] : mb[2]));
          list.append(item);
          i++;
          // an indented line that is not a new item continues this one
          while (i < lines.length && lines[i].trim() && /^\s{2,}/.test(lines[i]) && !bullet.test(lines[i]) && !ordered.test(lines[i]) && !fence.test(lines[i])) {
            item.append(h('br'), ...inline(lines[i].trim()));
            i++;
          }
        } else if (!lines[i].trim() && i + 1 < lines.length && (isOl ? ordered : bullet).test(lines[i + 1])) {
          i++; // a blank line inside a loose list
        } else break;
      }
      out.push(list);
      continue;
    }
    const head = line.match(/^\s*#{1,6}\s+(.*)$/);
    if (head) { out.push(h('p', { class: 'md-h' }, h('strong', null, inline(head[1])))); i++; continue; }
    const quote = [];
    while (i < lines.length && /^\s*>\s?/.test(lines[i])) quote.push(lines[i++].replace(/^\s*>\s?/, ''));
    if (quote.length) { out.push(h('p', { class: 'md-q' }, mdLines(quote))); continue; }
    const para = [];
    while (i < lines.length && lines[i].trim() && (para.length === 0 || !special(lines[i]))) para.push(lines[i++]);
    out.push(h('p', null, mdLines(para)));
  }
  return out;
}

/* ---------- Live text: what Claude is writing now, while the open session works ---------- */

// Asked every 1.5 s while the text is changing (less often once it stops), one request at a time, only while this session's screen is showing and it is
// working. What comes back is the current model call's text, which Capsid starts over now and then, so
// the card REPLACES what it shows each time and never adds to it.
const LIVE_EVERY = 1500;
// While the text and activity stay the same it is asked for less often: after 3 polls alike every 3 s, after 6 every 5 s, and every
// 1.5 s again the moment either changes. `same` counts the polls in a row that came back alike.
const liveEvery = (same) => (same >= 6 ? 5000 : same >= 3 ? 3000 : LIVE_EVERY);
const LIVE = { id: '', seq: 0, timer: 0, busy: false, shown: false, text: null, activity: null, same: 0, fails: 0, quiet: null, off: dict() };

const snapSig = (id) => JSON.stringify(lookup(id));

// The session whose live text should be coming in right now, or ''. The state stream says first; a session
// the stream doesn't list falls back to what its own page said.
function liveWanted() {
  const r = route();
  if (S.view !== 'app' || document.hidden || r.name !== 'session' || LIVE.off[r.id]) return '';
  const rec = S.sess[r.id];
  if (rec && rec.phase === 'missing') return '';
  const snap = lookup(r.id);
  const d = rec && rec.data;
  if (!(snap ? snap.bucket === 'working' : !!d && runs(d.state))) return '';
  // This session paused for a used-up limit: there is nothing being written to watch.
  if (snap && snap.paused === true) return '';
  // Told it isn't working a moment ago: wait for the state to change before asking again, or 3 s, then
  // twice as long (to a minute) each time the state still says working and Capsid says not.
  const q = LIVE.quiet;
  if (q && q.id === r.id && q.sig === snapSig(r.id) && Date.now() - q.at < q.wait) return '';
  return r.id;
}

function syncLive() {
  const want = liveWanted();
  if (want === LIVE.id) return;
  const was = LIVE.id;
  const showed = LIVE.shown;
  stopLive();
  if (want) {
    LIVE.id = want;
    LIVE.timer = setTimeout(() => liveTick(LIVE.seq), 0);
  } else if (was && showed) {
    // The state stream said it stopped working before our own ask did: read the saved reply now.
    const r = route();
    if (S.view === 'app' && !document.hidden && r.name === 'session' && r.id === was) loadSession(was);
  }
}

function stopLive() {
  const had = LIVE.id;
  clearTimeout(LIVE.timer);
  LIVE.seq++;
  Object.assign(LIVE, { id: '', timer: 0, shown: false, text: null, activity: null, same: 0, fails: 0 }); // `busy` is cleared only by the request itself
  if (had) paintLive();
}

async function liveTick(seq) {
  if (seq !== LIVE.seq || !LIVE.id) return;
  if (LIVE.busy) { LIVE.timer = setTimeout(() => liveTick(seq), 300); return; } // an earlier ask is still out: never two at once
  const id = LIVE.id;
  LIVE.busy = true;
  let d = null;
  let err = null;
  try { d = await api('/api/sessions/' + encodeURIComponent(id) + '/live', 'GET', undefined, 's:' + id); } catch (e) { err = e; }
  LIVE.busy = false;
  if (seq !== LIVE.seq) return; // left, hidden or finished while it was coming
  let wait = LIVE_EVERY;
  if (err || !d || typeof d.working !== 'boolean') {
    if (err instanceof Unauth) return showPair();
    if (err instanceof Aborted) {
      wait = LIVE_EVERY; // dropped with its screen, which is no failure; only if the screen is still wanted does it ask again
    } else {
      if (err && (err.status === 404 || err.status === 405 || err.status === 403)) { LIVE.off[id] = true; return stopLive(); } // an older version on the Mac, or the session is gone
      LIVE.fails++;
      // Capsid asked to wait (the api helper has already tried twice): do as it says, then go on.
      wait = err && isSlow(err) ? Math.min(10, Math.max(2, err.wait || 2)) * 1000 + Math.random() * 500 : Math.min(15000, LIVE_EVERY * 2 ** LIVE.fails);
    }
  } else if (!d.working) {
    return liveDone(id);
  } else {
    LIVE.fails = 0;
    const text = typeof d.text === 'string' && d.text ? d.text : null;
    const activity = typeof d.activity === 'string' && d.activity ? d.activity : null;
    LIVE.same = LIVE.shown && text === LIVE.text && activity === LIVE.activity ? LIVE.same + 1 : 1;
    LIVE.shown = true;
    LIVE.text = text;
    LIVE.activity = activity;
    wait = liveEvery(LIVE.same);
    paintLive();
  }
  LIVE.timer = setTimeout(() => liveTick(seq), wait);
}

// It stopped working: the card goes, and the saved reply is read from Capsid.
function liveDone(id) {
  const sig = snapSig(id);
  const before = LIVE.quiet;
  LIVE.quiet = { id, sig, at: Date.now(), wait: before && before.id === id && before.sig === sig ? Math.min(60000, before.wait * 2) : 3000 };
  stopLive();
  // Reads the history too. If Capsid was too busy to answer, once more a moment later.
  loadSession(id, true).then((ok) => { if (ok === false) setTimeout(() => loadSession(id, true), 4000); });
}

// The card sits in its own region and is updated in place, so a reader's place in the text is kept.
function paintLive(sv = root.querySelector('.sessview')) {
  if (!sv) return;
  const el = sv.querySelector('.sess-body > [data-r="live"]');
  if (!el) return;
  if (!(LIVE.shown && LIVE.id && sv.dataset.sess === LIVE.id)) { if (el.firstChild) el.replaceChildren(); return; }
  let sec = el.firstChild;
  if (!sec) {
    sec = h('section', { class: 'sec', 'aria-labelledby': 'live-h' },
      h('h2', { class: 'sec-h', id: 'live-h' }, h('span', { class: 'live-dot', 'aria-hidden': 'true' }), 'Writing…'),
      h('div', { class: 'card live' }, h('p', { class: 'live-act' }), h('div', { class: 'md live-text', tabindex: '0', role: 'region', 'aria-label': 'What Claude is writing' })));
    el.append(sec);
  }
  const card = sec.querySelector('.card');
  const act = card.querySelector('.live-act');
  const box = card.querySelector('.live-text');
  card.hidden = !LIVE.activity && !LIVE.text;
  act.hidden = !LIVE.activity;
  if (act.textContent !== (LIVE.activity || '')) act.textContent = LIVE.activity || '';
  box.hidden = !LIVE.text;
  if (LIVE.text && box._t !== LIVE.text) {
    const stick = box._t === undefined || box.scrollHeight - box.scrollTop - box.clientHeight < 28; // follow the end unless the reader scrolled up
    box.replaceChildren(...md(LIVE.text));
    box._t = LIVE.text;
    if (stick) box.scrollTop = box.scrollHeight;
  }
}

/* ---------- Session: built from regions, so a refresh never disturbs what you are typing ---------- */

const STATE_LABELS = {
  needsInput: 'Needs you',
  working: 'Working',
  running: 'Working',
  error: 'Stopped with an error',
  failed: 'Stopped with an error',
  finished: 'Finished',
  done: 'Finished',
  idle: 'Idle',
};
const stateLabel = (s) => STATE_LABELS[s] || (s ? String(s).replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^./, (c) => c.toUpperCase()) : '');

function lookup(id) {
  const st = S.state || {};
  for (const k of ['needsYou', 'failed', 'working', 'recent']) {
    const hit = (st[k] || []).find((x) => x.id === id);
    if (hit) return { ...hit, bucket: k };
  }
  return null;
}

function openLabel(id) {
  const o = S.open[id];
  if (o && o.phase === 'busy') return 'Opening…';
  if (o && o.phase === 'done') return 'Opened on your Mac ✓';
  return 'Open on Mac';
}

function openMessage(id) {
  const o = S.open[id];
  if (!o || o.phase !== 'error') return '';
  if (o.down) return 'Couldn’t reach your Mac. Try again.';
  if (o.status === 404) return 'That session isn’t available any more.';
  if (o.status === 429) return 'Wait a moment, then try again.';
  return 'Capsid couldn’t open it (error ' + (o.status || '?') + ').';
}

function paintOpen(id) {
  const b = $('open-btn');
  const m = $('open-msg');
  if (!b || b.dataset.id !== id) return;
  const o = S.open[id];
  b.textContent = openLabel(id);
  b.disabled = !!o && o.phase === 'busy';
  b.className = 'btn ' + (b.dataset.low === '1' || (o && o.phase === 'done') ? 'ok' : 'primary');
  m.textContent = openMessage(id);
  m.hidden = !m.textContent;
}

async function openOnMac(id) {
  S.open[id] = { phase: 'busy' };
  paintOpen(id);
  try {
    await api('/api/sessions/' + encodeURIComponent(id) + '/open', 'POST', {});
    S.open[id] = { phase: 'done' };
    setTimeout(() => {
      if (S.open[id] && S.open[id].phase === 'done') { delete S.open[id]; paintOpen(id); }
    }, 6000);
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    S.open[id] = { phase: 'error', down: e instanceof Down, status: e.status };
  }
  paintOpen(id);
}

function openBlock(id, low = false) {
  const block = h('div', { class: 'act', 'aria-live': 'polite' },
    h('button', { id: 'open-btn', class: 'btn primary', type: 'button', 'data-key': 'open', 'data-id': id, 'data-low': low ? '1' : '0', onclick: () => openOnMac(id) }),
    h('p', { id: 'open-msg', class: 'msg bad', hidden: true }));
  queueMicrotask(() => paintOpen(id));
  return block;
}

const sessionTitle = (id) => {
  const rec = S.sess[id];
  const snap = lookup(id);
  return (rec && rec.data && rec.data.title) || (snap && snap.title) || 'Session';
};

// A status is a shape and a label, never a colour alone.
function statusMark(state, held = false) {
  if (state === 'needsInput') return h('span', { class: 'dot', 'aria-hidden': 'true' });
  if (state === 'error' || state === 'failed') return icon('alert', 'sm mark-err');
  if (runs(state) && held) return icon('pause', 'sm');
  if (runs(state)) return h('span', { class: 'dot live', 'aria-hidden': 'true' });
  return h('span', { class: 'dot idle', 'aria-hidden': 'true' });
}

// What the person has typed or chosen on a session, kept across every redraw.
const ui = (id) => (S.ui[id] ||= { draft: '', msg: null, picks: dict(), other: dict(), otherOn: dict(), qTool: '', busy: dict(), note: null, noteT: 0, shown: 4, more: dict(), photo: null, permId: '', permDecision: '' });

const REGIONS = ['head', 'open', 'unread', 'permission', 'question', 'plan', 'live', 'reply', 'toyou', 'artifacts', 'convo', 'times', 'openlow'];

function sessionView(id, inPane) {
  const body = h('div', { class: (inPane ? 'detail-in' : 'wrap') + ' sess-body' }, REGIONS.map((n) => h('div', { 'data-r': n })));
  const sv = inPane
    ? h('div', { class: 'detail-col sessview', 'data-sess': id }, h('div', { class: 'detail-body' }, body))
    : h('div', { class: 'sessview single', 'data-sess': id }, bar(sessionTitle(id), backLink(...sessionBack()), refreshButton()), h('main', null, body));
  fillSession(sv, id);
  return sv;
}

// What has focus inside `el`, and where its caret is: the function returned puts both back on the element with
// the same data-key once `el` has been redrawn.
function holdFocus(el) {
  const active = document.activeElement;
  const key = active && el.contains(active) ? active.dataset.key : '';
  const caret = key && active.selectionStart != null ? [active.selectionStart, active.selectionEnd] : null;
  return () => {
    if (!key) return;
    const again = el.querySelector(`[data-key="${CSS.escape(key)}"]`);
    if (!again) return;
    again.focus({ preventScroll: true });
    if (caret && again.setSelectionRange) try { again.setSelectionRange(caret[0], caret[1]); } catch { /* not a text field */ }
  };
}

// Replace a region's children only when what it shows changed; keep focus and caret.
function setRegion(body, name, sig, build) {
  const el = body.querySelector(`:scope > [data-r="${name}"]`);
  if (!el || el.dataset.sig === sig) return;
  const restore = holdFocus(el);
  el.dataset.sig = sig;
  el._hist = null; // whatever the conversation kept here (setHistory) goes with the contents
  replaceContents(el, ...build().filter(Boolean));
  restore();
}

function fillSession(sv, id) {
  const body = sv.querySelector('.sess-body');
  const rec = S.sess[id];
  const d = rec && rec.data;
  const snap = lookup(id);
  const u = ui(id);
  const q = d && d.question;
  if (q && u.qTool !== q.toolId) Object.assign(u, { qTool: q.toolId, picks: dict(), other: dict(), otherOn: dict() });
  const perm = validPermission(d && d.permission);
  if (perm && u.permId !== perm.id) Object.assign(u, { permId: perm.id, permDecision: '' });
  const set = (name, sig, build) => setRegion(body, name, JSON.stringify(sig) ?? '', build);
  const none = () => [];

  set('head', [sessionTitle(id), rec && rec.phase, rec && rec.down, rec && rec.gone, d && [d.project, d.state, d.sentence, d.statusLine], snap && [snap.project, snap.snooze], heldBy(id) ? resumeSentence(S.state.pause) : null], () => headNodes(id, rec, d, snap));
  // When the phone can act, Open on Mac is a quiet button after the details; otherwise it is the main one.
  // A permission the phone can't allow carries its own Open on Mac, so there is only ever one.
  const acts = !!(d && d.can && (d.can.approve || d.can.answer || d.can.message)) || !!(perm && (perm.canAllow || perm.canDeny));
  const gone = rec && rec.phase === 'missing';
  const permOpen = !!perm && !perm.canAllow;
  set('open', gone || acts || permOpen ? 0 : 1, () => (gone || acts || permOpen ? [] : [openBlock(id)]));
  set('openlow', acts && !permOpen ? 1 : 0, () => (acts && !permOpen ? [openBlock(id, true)] : []));
  set('unread', d && d.version >= 2 && d.readable === false, () => (d && d.version >= 2 && d.readable === false
    ? [h('p', { class: 'quiet', text: 'Capsid can’t show this session’s messages. Open it on your Mac.' })] : []));
  set('permission', perm ? [perm, u.busy.permission, u.permDecision] : 0, () => (perm ? [permissionCard(id, perm, u)] : []));
  set('question', d && q ? [q, u.picks, u.otherOn, u.busy.question] : 0, () => (d && q ? [questionCard(id, q, u)] : []));
  set('plan', d && d.plan ? [d.plan, d.can && d.can.approve, u.busy.plan] : 0, () => (d && d.plan ? [planCard(id, d, u)] : []));
  paintLive(sv);
  set('reply', d && d.reply ? d.reply : 0, () => (d && d.reply && d.reply.text
    ? [section('Latest reply', 0, h('div', { class: 'card reply' }, h('div', { class: 'md' }, md(d.reply.text)), d.reply.at ? h('p', { class: 'foot-t' }, rel(d.reply.at)) : null))] : []));
  set('toyou', d && d.toYou && d.toYou.length ? d.toYou : 0, () => (d && d.toYou && d.toYou.length
    ? [section('Messages to you', 0, h('ul', { class: 'group' }, d.toYou.map((m) => h('li', { class: 'turn' },
      h('div', { class: 'md' }, md(m.text)), m.at ? h('p', { class: 'foot-t' }, rel(m.at)) : null))))] : []));
  // Artifacts: a row with a count, once the list is in.
  const A = art(id);
  const nArt = browseOn() && A.loaded ? A.items.length : 0;
  set('artifacts', nArt, () => (nArt ? [h('ul', { class: 'group sec' }, h('li', null, h('a', { class: 'row', href: `#/session/${id}/artifacts`, 'data-key': 'artifacts' },
    h('span', { class: 'kind-ic', 'aria-hidden': 'true' }, icon('file', 'sm')),
    h('span', { class: 'row-main' }, h('span', { class: 'title', text: 'Artifacts' })),
    h('span', { class: 'side', text: String(nArt) }),
    icon('chev', 'sm chev'))))] : []));
  // Conversation: the whole history once it has arrived, the last few turns until then.
  const H = browseOn() ? hist(id) : null;
  const fullHist = !!(H && H.loaded);
  if (fullHist) {
    setHistory(body, id, H, u);
  } else {
    set('convo', d && d.turns && d.turns.length ? [d.turns, u.shown, u.more] : 0, () => (d && d.turns && d.turns.length ? [convo(id, d.turns, u)] : []));
  }
  set('times', d ? [d.state, d.startedAt, d.updatedAt, heldBy(id)] : 0, () => (d ? [timesCard(d, heldBy(id))] : []));

  let dock = sv.querySelector('.dock');
  if (d && d.can) {
    if (!dock) { dock = buildDock(id); sv.append(dock); }
    paintDock(id, dock);
  } else if (dock) dock.remove();
  requestAnimationFrame(() => { measureClamps(sv); watchHistTop(sv, id); });
  syncLive();
}

function headNodes(id, rec, d, snap) {
  const heading = h('h1', { class: 'sess', tabindex: '-1', text: sessionTitle(id) });
  if (!d) {
    const note = !rec || rec.phase === 'loading' ? 'Loading…'
      : rec.phase === 'missing' ? 'This session isn’t available any more.'
      : rec.down ? 'Couldn’t reach your Mac.' : 'Couldn’t load this session.';
    const retry = rec && rec.phase === 'error'
      ? h('div', { class: 'act' }, h('button', { class: 'btn', type: 'button', text: 'Try again', onclick: () => { delete S.sess[id]; loadSession(id, true); render(); } }))
      : null;
    return [heading, snap ? h('p', { class: 'sub tight-sub', text: snap.project }) : null, h('p', { class: 'lede', text: note }), retry];
  }
  const snooze = snap && snap.snooze ? snoozeText(snap.snooze) : '';
  const held = runs(d.state) && heldBy(id);
  return [
    heading,
    d.project ? h('p', { class: 'sub tight-sub', text: d.project }) : null,
    h('p', { class: 'status' + (d.state === 'needsInput' || d.state === 'error' || d.state === 'failed' ? '' : ' calm') },
      statusMark(d.state, held), held ? 'Paused · usage limit' : (d.sentence || stateLabel(d.state))),
    held ? h('p', { class: 'status-line', text: resumeSentence(S.state.pause) })
      : d.statusLine ? h('p', { class: 'status-line', text: d.statusLine }) : null,
    snooze ? h('p', { class: 'snooze lone', text: snooze }) : null,
    rec.gone ? h('p', { class: 'snooze lone', text: 'This session is no longer on your list.' }) : null,
  ];
}

function timesCard(d, held = false) {
  const rows = [];
  const kv = (k, v) => h('div', { class: 'kv' }, h('dt', { text: k }), h('dd', null, v));
  if (runs(d.state) && d.startedAt && !held) rows.push(kv('Working for', clockEl(d.startedAt)));
  if (d.startedAt) rows.push(kv('Started', [when(d.startedAt), ' ', h('span', { class: 'sub' }, '(', rel(d.startedAt), ')')]));
  if (d.updatedAt) rows.push(kv('Updated', rel(d.updatedAt)));
  return rows.length ? h('dl', { class: 'group sec' }, rows) : null;
}

function planCard(id, d, u) {
  const plan = d.plan;
  const steps = Array.isArray(plan.steps) ? plan.steps : [];
  const canApprove = !!(d.can && d.can.approve && plan.version);
  return section('Plan', 0, h('div', { class: 'card plan' },
    plan.summary ? h('p', { text: plan.summary }) : null,
    steps.length ? h('ol', null, steps.map((s) => h('li', { text: typeof s === 'string' ? s : (s && (s.text || s.title)) || '' }))) : null,
    plan.feasibility ? h('p', { class: 'feas', text: 'Feasibility: ' + plan.feasibility }) : null,
    canApprove ? h('button', {
      class: 'btn primary plan-go',
      type: 'button',
      text: u.busy.plan ? 'Approving…' : 'Approve plan',
      disabled: !!u.busy.plan,
      'data-key': 'approve',
      onclick: () => confirmSheet({
        title: 'Approve this plan?',
        message: 'Claude will start on it.',
        confirm: 'Approve',
        run: () => doAction(id, 'plan', '/api/sessions/' + id + '/approve', { version: plan.version }),
      }),
    }) : null));
}

/* ----- the permission card ----- */

const CODE_MAX = 8000;

// The code the person is asked to run, as the lines a reader (and Python) would count: every line break
// the page could mistake is a break here too, so a lone CR can't hide a second statement on one drawn line.
const LINE_BREAK = /\r\n|[\n\r\v\f\u001c-\u001e\u0085\u2028\u2029]/;
// Characters that draw nothing (or change what is drawn) are shown as their code point, never left invisible.
const UNSEEN = /[\u0000-\u0008\u000e-\u001b\u001f\u007f-\u009f\u00ad\u061c\u180e\u200b-\u200f\u202a-\u202e\u2060-\u206f\u3164\ufe00-\ufe0f\ufeff\ufff9-\ufffb]|[\u{e0000}-\u{e0fff}]/gu;
const codeLines = (code) => code.replace(/(?:\r\n|[\n\r\v\f\u001c-\u001e\u0085\u2028\u2029])+$/, '').split(LINE_BREAK);

function codeLine(text) {
  const parts = [];
  let at = 0;
  for (const m of text.matchAll(UNSEEN)) {
    if (m.index > at) parts.push(text.slice(at, m.index));
    const hex = m[0].codePointAt(0).toString(16).toUpperCase().padStart(4, '0');
    parts.push(h('span', { class: 'unseen', title: 'U+' + hex, text: '‹' + hex + '›' }));
    at = m.index + m[0].length;
  }
  if (at < text.length) parts.push(text.slice(at));
  return h('span', { class: 'ln' }, parts);
}

// The one request the phone may answer, or null when the page sent something else.
function validPermission(p) {
  if (!p || typeof p !== 'object') return null;
  const canAllow = p.canAllow === true;
  const canDeny = p.canDeny === true;
  const named = typeof p.id === 'string' && !!p.id && p.id.length <= 200;
  if (!named && (canAllow || canDeny)) return null; // an answer has to name the request
  const kind = typeof p.kind === 'string' ? p.kind : '';
  const code = typeof p.code === 'string' && p.code ? p.code : '';
  const cut = code.length > CODE_MAX; // never offer Allow on code the phone could only show a part of
  const why = typeof p.why === 'string' ? p.why : '';
  return {
    id: named ? p.id : 'kind:' + kind,
    kind,
    title: typeof p.title === 'string' && p.title ? p.title : kind === 'ask' ? (p.helper === true ? 'A helper agent asked a question' : 'Asks you a question') : 'Wants your permission',
    detail: typeof p.detail === 'string' ? p.detail : '',
    code: code.slice(0, CODE_MAX),
    cut,
    helper: p.helper === true,
    canAllow: canAllow && !cut,
    canDeny,
    why: canAllow && cut ? 'This code is too long to read here. Open it on your Mac.' : why,
  };
}

function askPermission(id, p, decision) {
  const u = ui(id);
  u.permDecision = decision;
  return doAction(id, 'permission', '/api/sessions/' + id + '/permission', { id: p.id, decision });
}

function permissionCard(id, p, u) {
  const busy = !!u.busy.permission;
  const isCode = !!p.code;
  const lines = isCode ? codeLines(p.code) : [];
  const buttons = [];
  if (p.canAllow) {
    buttons.push(h('button', {
      class: 'btn primary', type: 'button', text: busy && u.permDecision === 'allow' ? 'Allowing…' : 'Allow once', disabled: busy, 'data-key': 'perm-allow',
      onclick: () => confirmSheet({
        title: p.kind === 'local_exec' ? (lines.length === 1 ? 'Run this 1 line of code once?' : `Run these ${lines.length} lines of code once?`) : 'Allow this once?',
        message: (isCode ? 'It runs on your Mac, this one time.' : 'Only this once.') + ' Anything more asks you again.',
        confirm: 'Allow once',
        run: () => askPermission(id, p, 'allow'),
      }),
    }));
  }
  if (p.canDeny) {
    buttons.push(h('button', {
      class: 'btn', type: 'button', text: busy && u.permDecision === 'deny' ? 'Denying…' : 'Deny', disabled: busy, 'data-key': 'perm-deny',
      onclick: () => askPermission(id, p, 'deny'),
    }));
  }
  const asks = p.kind === 'ask';
  // The helper is named once: in the title when it asks a question, in its own line otherwise.
  const named = asks && /helper/i.test(p.title);
  return h('div', { class: 'card perm', role: 'group', 'aria-labelledby': 'perm-t' },
    h('div', { class: 'perm-body' },
      h('p', { class: 'sec-h perm-over', text: asks ? 'Question' : 'Permission' }),
      p.helper && !named ? h('p', { class: 'perm-who' }, icon('helper', 'sm'), h('span', { text: 'A helper agent is asking' })) : null,
      h('p', { class: 'perm-title', id: 'perm-t', text: p.title }),
      p.detail ? h('p', { class: 'perm-detail', text: p.detail }) : null,
      // The whole code, wrapped inside the page: the page scrolls, never the box. A number marks each line it starts.
      isCode ? h('pre', { class: 'perm-code', role: 'region', 'aria-label': `The code to run, ${lines.length === 1 ? '1 line' : lines.length + ' lines'}` }, h('code', null, lines.map(codeLine))) : null,
      isCode && p.cut ? h('p', { class: 'perm-why', text: 'Only the first part is shown here.' }) : null,
      !p.canAllow ? h('p', { class: 'perm-why', text: p.why || 'Open it on your Mac to answer.' }) : null),
    buttons.length ? h('div', { class: 'q-actions' }, buttons) : null,
    !p.canAllow ? h('div', { class: 'perm-open' }, openBlock(id, true)) : null);
}

/* ----- the question card ----- */

const answerOf = (u, item, i) => {
  const picked = (u.picks[i] || []).filter((k) => item.options[k]).sort((a, b) => a - b).map((k) => item.options[k].label);
  const typed = u.otherOn[i] ? (u.other[i] || '').trim() : '';
  if (item.multi) return [...picked, ...(typed ? [typed] : [])].join(', ');
  return u.otherOn[i] ? typed : picked[0] || '';
};
const answersComplete = (q, u) => q.items.every((item, i) => answerOf(u, item, i));

function pickOption(id, i, k, multi) {
  const u = ui(id);
  const cur = u.picks[i] || [];
  if (multi) u.picks[i] = cur.includes(k) ? cur.filter((x) => x !== k) : [...cur, k];
  else { u.picks[i] = [k]; u.otherOn[i] = false; }
  redrawSession(id);
}

function paintAnswerButton(id) {
  const q = S.sess[id] && S.sess[id].data && S.sess[id].data.question;
  const b = root.querySelector('[data-act="answer"]');
  if (b && q) b.disabled = !!ui(id).busy.question || !answersComplete(q, ui(id));
}

function questionCard(id, q, u) {
  const busy = !!u.busy.question;
  const items = q.items.map((item, i) => {
    const multi = !!item.multi;
    const picks = u.picks[i] || [];
    const row = (on, label, detail, key, onclick) => h('button', {
      class: 'opt', type: 'button', role: multi ? 'checkbox' : 'radio', 'aria-checked': on ? 'true' : 'false', 'data-key': key, disabled: busy, onclick,
    }, h('span', { class: 'ind' + (multi ? ' sq' : ''), 'aria-hidden': 'true' }, on ? icon('check', 'sm') : null),
    h('span', { class: 'opt-main' }, h('span', { class: 'opt-l', text: label }), detail ? h('span', { class: 'opt-d', text: detail }) : null));
    const otherOn = !!u.otherOn[i];
    const other = row(otherOn, 'Other…', '', 'o:' + i + ':x', () => {
      u.otherOn[i] = !u.otherOn[i];
      if (u.otherOn[i] && !multi) u.picks[i] = [];
      redrawSession(id);
      const f = root.querySelector(`[data-key="t:${i}"]`);
      if (f && u.otherOn[i]) f.focus();
    });
    const field = otherOn ? h('textarea', {
      class: 'opt-other', rows: '2', placeholder: 'Type your answer', 'aria-label': 'Your own answer', 'data-key': 't:' + i,
      enterkeyhint: 'done', autocapitalize: 'sentences', maxlength: '1000', disabled: busy,
      oninput: (e) => { u.other[i] = e.target.value; paintAnswerButton(id); },
    }) : null;
    if (field) field.value = u.other[i] || '';
    return h('div', { class: 'q-item' },
      h('p', { class: 'sec-h q-head', text: item.header || 'Question' }),
      h('p', { class: 'q-text', id: 'q-' + i, text: item.question }),
      h('div', { class: 'opts', role: multi ? 'group' : 'radiogroup', 'aria-labelledby': 'q-' + i },
        item.options.map((o, k) => row(picks.includes(k), o.label, o.detail, 'o:' + i + ':' + k, () => pickOption(id, i, k, multi))),
        other, field));
  });
  const send = h('button', {
    class: 'btn primary', type: 'button', 'data-act': 'answer', 'data-key': 'send-answer',
    text: busy ? 'Sending…' : 'Send answer', disabled: busy || !answersComplete(q, u),
    onclick: () => doAction(id, 'question', '/api/sessions/' + id + '/answer', {
      toolId: q.toolId,
      answers: Object.fromEntries(q.items.map((item, i) => [item.question, answerOf(u, item, i)])),
    }),
  });
  return h('div', { class: 'card q-card' }, items,
    h('div', { class: 'q-actions' }, send,
      h('button', { class: 'btn', type: 'button', text: 'Choose for me', disabled: busy, 'data-key': 'choose', onclick: () => doAction(id, 'question', '/api/sessions/' + id + '/answer', { toolId: q.toolId, action: 'chooseForMe' }) }),
      h('button', { class: 'btn-quiet', type: 'button', text: 'Cancel question', disabled: busy, 'data-key': 'cancel-q', onclick: () => doAction(id, 'question', '/api/sessions/' + id + '/answer', { toolId: q.toolId, action: 'cancel' }) })));
}

/* ----- conversation ----- */

function convo(id, turns, u) {
  const shown = Math.min(turns.length, u.shown);
  const slice = turns.slice(turns.length - shown);
  const items = slice.map((t, n) => {
    const key = (turns.length - shown + n) + ':' + t.at;
    const open = !!u.more[key];
    return h('li', { class: 'turn' },
      h('div', { class: 'turn-h' }, h('span', { class: 'who', text: t.role === 'you' ? 'You' : 'Claude' }), t.at ? h('span', { class: 'when', text: when(t.at) }) : null),
      h('div', { class: 'md clamp' + (open ? ' open' : '') }, md(t.text)),
      h('button', {
        class: 'more', type: 'button', hidden: !open, text: open ? 'Less' : 'More', 'data-more': '1', 'data-key': 'm:' + key,
        onclick: () => { u.more[key] = !open; redrawSession(id); },
      }));
  });
  return section('Conversation', 0, [
    turns.length > shown ? h('button', { class: 'btn earlier', type: 'button', text: 'Show earlier', 'data-key': 'earlier', onclick: () => { u.shown = 12; redrawSession(id); } }) : null,
    h('ul', { class: 'group' }, items),
  ]);
}

// Show "More" only on turns that really are cut off.
function measureClamps(sv) {
  for (const el of sv.querySelectorAll('.md.clamp:not(.open)')) {
    const b = el.nextElementSibling && el.nextElementSibling.dataset && el.nextElementSibling.dataset.more ? el.nextElementSibling : el.parentElement.querySelector('[data-more]');
    if (b) b.hidden = el.scrollHeight <= el.clientHeight + 1;
  }
}

function redrawSession(id) {
  const sv = root.querySelector('.sessview');
  if (sv && sv.dataset.sess === id) fillSession(sv, id);
}

/* ----- photos: made ready in the page, sent as one JPEG ----- */

// The page draws the picture at 3,072 px on its long side (the browser applies the camera's rotation) and
// sends a JPEG. Capsid takes a body up to 6 MB; base64 adds a third, so the JPEG stays under 4.2 MB.
// The page's CSP has no blob: images, so a picture is only ever read as a data: URL.
const PHOTO_SIDE = 3072;
const PHOTO_BYTES = 4200000;
const PHOTO_STEPS = [[PHOTO_SIDE, 0.85], [PHOTO_SIDE, 0.7], [2400, 0.7], [1800, 0.7], [1200, 0.7]];
const PHOTO_NOTE_KEY = 'bench-photo-note';
const PHOTO_NOTE = 'Photos are saved to the project’s uploads, where its other sessions can see them.';
const notPhoto = () => Object.assign(new Error('not a photo'), { code: 'notImage' });

const readDataURL = (blob) => new Promise((resolve, reject) => {
  const r = new FileReader();
  r.onload = () => resolve(String(r.result));
  r.onerror = () => reject(r.error || new Error('read'));
  r.readAsDataURL(blob);
});

async function decodePhoto(file) {
  if ('createImageBitmap' in window) {
    try { return await createImageBitmap(file, { imageOrientation: 'from-image' }); } catch { /* an older browser: use an Image */ }
  }
  const url = await readDataURL(file);
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('decode'));
    img.src = url;
  });
}

const toJPEG = (canvas, q) => new Promise((resolve) => { try { canvas.toBlob(resolve, 'image/jpeg', q); } catch { resolve(null); } });

// -> { blob, thumb (a small data: URL), w, h, size }. Throws with code 'notImage' when it can't be read as a picture.
async function preparePhoto(file) {
  let src;
  try { src = await decodePhoto(file); } catch { throw notPhoto(); }
  const w0 = src.naturalWidth || src.width;
  const h0 = src.naturalHeight || src.height;
  if (!w0 || !h0) throw notPhoto();
  let out = null;
  for (const [side, q] of PHOTO_STEPS) {
    const k = Math.min(1, side / Math.max(w0, h0));
    const c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(w0 * k));
    c.height = Math.max(1, Math.round(h0 * k));
    const g = c.getContext('2d');
    g.fillStyle = '#fff'; // a picture with see-through parts is flattened onto white, not black
    g.fillRect(0, 0, c.width, c.height);
    g.drawImage(src, 0, 0, c.width, c.height);
    const blob = await toJPEG(c, q);
    if (!blob) continue;
    out = { blob, w: c.width, h: c.height, size: blob.size };
    if (blob.size <= PHOTO_BYTES) break;
  }
  if (!out) throw new Error('encode');
  const t = document.createElement('canvas');
  t.width = t.height = 96;
  const tg = t.getContext('2d');
  const k = Math.max(96 / w0, 96 / h0);
  tg.fillStyle = '#fff';
  tg.fillRect(0, 0, 96, 96);
  tg.drawImage(src, (96 - w0 * k) / 2, (96 - h0 * k) / 2, w0 * k, h0 * k);
  out.thumb = t.toDataURL('image/jpeg', 0.7);
  if (src.close) src.close();
  return out;
}

const photoNoteSeen = () => { try { return localStorage.getItem(PHOTO_NOTE_KEY) === '1'; } catch { return S.photoNote === true; } };
const photoNoteSeenNow = () => { S.photoNote = true; try { localStorage.setItem(PHOTO_NOTE_KEY, '1'); } catch { /* this run only */ } };

// `holder.photo` is the photo being added to a message or a new session: { phase: prep | ready | err, blob, thumb, w, h, size, id, note, err }.
// The first photo a person ever picks also says where it goes. `repaint` redraws whatever shows it.
async function stagePhoto(holder, file, repaint) {
  const mine = { phase: 'prep', id: uuid(), note: !photoNoteSeen(), sent: null };
  if (mine.note) photoNoteSeenNow();
  holder.photo = mine;
  repaint();
  try {
    Object.assign(mine, await preparePhoto(file), { phase: 'ready' });
  } catch (e) {
    Object.assign(mine, { phase: 'err', err: e && e.code === 'notImage' ? 'That doesn’t look like a photo. Try another.' : 'Couldn’t get that photo ready. Try another.' });
  }
  if (holder.photo === mine) repaint();
}

const photoReady = (p) => !!p && p.phase === 'ready';

function photoChip(p, remove, locked) {
  const label = p.phase === 'prep' ? 'Getting the photo ready…' : p.phase === 'err' ? p.err : `Photo · ${fmtSize(p.size)}`;
  return h('div', { class: 'photo' },
    h('div', { class: 'photo-chip' + (p.phase === 'err' ? ' bad' : '') },
      p.thumb ? h('img', { class: 'photo-img', src: p.thumb, alt: 'The photo you picked', width: '44', height: '44' }) : h('span', { class: 'photo-ph', 'aria-hidden': 'true' }, icon('camera', 'sm')),
      h('span', { class: 'photo-t', role: p.phase === 'err' ? 'alert' : null, text: label }),
      h('button', { class: 'photo-x', type: 'button', 'aria-label': 'Remove the photo', 'data-key': 'photo-x', disabled: !!locked, onclick: remove }, icon('x', 'sm'))),
    p.note ? h('p', { class: 'photo-note', text: PHOTO_NOTE }) : null);
}

// A hidden picker and the button that opens it. iOS offers the camera or the library.
function photoButton(cls, label, onFile, ...kids) {
  const input = h('input', { type: 'file', accept: 'image/*', hidden: true, tabindex: '-1', 'aria-hidden': 'true' });
  input.addEventListener('change', () => {
    const f = input.files && input.files[0];
    input.value = '';
    if (f) onFile(f);
  });
  const button = h('button', { class: cls, type: 'button', 'aria-label': label, onclick: () => input.click() }, kids);
  return { input, button };
}

const blobBase64 = async (blob) => (await readDataURL(blob)).split(',')[1] || '';

/* ----- the composer, pinned at the bottom ----- */

const PLACEHOLDER = {
  send: 'Message Claude',
  queue: 'Queue a message — Claude will read it at the next pause',
  resume: 'Message Claude to pick it up again',
};

function uuid() {
  if (crypto.randomUUID) return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  const x = [...b].map((v) => v.toString(16).padStart(2, '0')).join('');
  return `${x.slice(0, 8)}-${x.slice(8, 12)}-${x.slice(12, 16)}-${x.slice(16, 20)}-${x.slice(20)}`;
}

// On a touch-only device Return makes a newline and the Send button sends. A hardware
// keyboard (seen by a key a soft keyboard never makes) or a trackpad brings back Enter to send.
let hardwareKeys = false;
const touchOnly = () => matchMedia('(hover: none) and (pointer: coarse)').matches && !hardwareKeys;
document.addEventListener('keydown', (e) => {
  if (hardwareKeys || !(e.ctrlKey || e.metaKey || e.altKey || /^(Shift|Tab|Escape|Arrow|F\d)/.test(e.key))) return;
  hardwareKeys = true;
  const ta = $('composer');
  if (ta) ta.setAttribute('enterkeyhint', 'send');
});

function buildDock(id) {
  const u = ui(id);
  const ta = h('textarea', {
    id: 'composer', class: 'composer-ta', rows: '1', maxlength: '4000', enterkeyhint: touchOnly() ? 'enter' : 'send', autocapitalize: 'sentences',
    'aria-label': 'Message to Claude', 'data-key': 'composer',
  });
  const grow = h('div', { class: 'grow' }, ta);
  ta.value = u.draft;
  ta.addEventListener('input', () => { u.draft = ta.value; paintDock(id); });
  ta.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && !touchOnly()) { e.preventDefault(); sendMessage(id); }
  });
  const cam = photoButton('cam', 'Add a photo', (f) => stagePhoto(u, f, () => paintDock(id)), icon('camera'));
  return h('div', { class: 'dock', 'data-sess': id }, h('div', { class: 'dock-in' },
    h('div', { class: 'dock-photo', hidden: true }),
    h('div', { class: 'dock-note', role: 'status', hidden: true }),
    h('div', { class: 'composer' }, cam.button, cam.input, grow, h('button', { class: 'send', type: 'button', 'aria-label': 'Send', onclick: () => sendMessage(id) }, icon('up'))),
    h('p', { class: 'dock-count', hidden: true })));
}

function paintDock(id, dock = root.querySelector('.dock')) {
  const d = S.sess[id] && S.sess[id].data;
  // a late timer or reply for a session we have left must not repaint the one on screen
  if (!dock || dock.dataset.sess !== id || !d || !d.can) return;
  const u = ui(id);
  const can = d.can;
  const ta = dock.querySelector('textarea');
  const note = dock.querySelector('.dock-note');
  const count = dock.querySelector('.dock-count');
  const posting = !!u.busy.message || !!u.sending;
  ta.disabled = !can.message;
  ta.readOnly = posting;
  ta.placeholder = can.message ? PLACEHOLDER[can.message] || 'Message Claude' : can.why || 'You can’t message this session right now';
  // A photo can go with no words; a photo still being made ready, or one that failed, holds Send back.
  dock.querySelector('.send').disabled = !can.message || posting || (u.photo ? !photoReady(u.photo) : !u.draft.trim());
  dock.querySelector('.cam').disabled = !can.message || posting;
  paintDockPhoto(id, dock, posting);
  dock.classList.toggle('off', !can.message);
  // The field grows to its text, or to its hint when empty, so a long hint is never clipped.
  ta.parentElement.dataset.v = u.draft || ta.placeholder;
  const len = u.draft.length;
  count.hidden = len <= 3500;
  count.textContent = len.toLocaleString() + ' / 4,000';
  // one line above the field: a result first, else why it is off, else what is queued
  note.replaceChildren();
  let text = '';
  let withOpen = false;
  if (u.note) ({ text, open: withOpen } = u.note);
  else if (d.queued > 0) text = d.queued === 1 ? '1 message is waiting for Claude’s next pause.' : d.queued + ' messages are waiting for Claude’s next pause.';
  note.hidden = !text;
  if (text) {
    note.append(h('span', { text }));
    if (withOpen) {
      note.append(h('button', {
        class: 'btn-link', type: 'button', text: 'Open on Mac',
        onclick: () => openOnMac(id).then(() => setNote(id, S.open[id] && S.open[id].phase === 'done' ? { text: 'Opened on your Mac ✓' } : { text: openMessage(id) || 'Couldn’t open it on your Mac.' }, 5000)),
      }));
    }
  }
}

// The chip for the photo that is about to go, redrawn only when it changes.
function paintDockPhoto(id, dock, posting) {
  const u = ui(id);
  const area = dock.querySelector('.dock-photo');
  const p = u.photo;
  const sig = p ? [p.id, p.phase, !!p.note, !!posting].join('|') : '';
  if (area.dataset.sig === sig) return;
  area.dataset.sig = sig;
  area.hidden = !p;
  area.replaceChildren(...(p ? [photoChip(p, () => { u.photo = null; paintDock(id); }, posting)] : []));
}

function setNote(id, note, ms = 6000) {
  const u = ui(id);
  clearTimeout(u.noteT);
  u.note = note;
  paintDock(id);
  if (note) u.noteT = setTimeout(() => { u.note = null; paintDock(id); }, ms);
}

// What went wrong with a photo, in a sentence: too big, not a picture, or a caption holding a file link.
function photoTrouble(status, data) {
  const err = data && typeof data.error === 'string' ? data.error : '';
  if (status === 413) return 'That photo is too big to send from here. Try a smaller one.';
  if (status === 415 || err === 'notAnImage') return 'That doesn’t look like a photo Capsid can use. Try another.';
  if (status === 400 && err === 'reference') return 'The message has something that looks like a file link in it. Take that out and try again.';
  return '';
}

function describe(out) {
  const { status, data } = out;
  const result = data && typeof data.result === 'string' ? data.result : '';
  const sentence = data && typeof data.sentence === 'string' ? data.sentence : '';
  if (status === 429) return { ok: false, refetch: false, text: data && data.error === 'tooMany' ? 'Too many actions just now. Try again in a minute.' : slowText(data) };
  const trouble = photoTrouble(status, data);
  if (trouble) return { ok: false, refetch: false, text: trouble };
  if (result === 'changed') return { ok: false, refetch: true, text: 'This changed on your Mac. Showing the latest.' };
  if (['approved', 'allowed', 'denied', 'sent', 'queued', 'resumed'].includes(result) && status < 300) {
    return { ok: true, refetch: true, text: sentence || { approved: 'Approved', allowed: 'Allowed once', denied: 'Denied', sent: 'Sent', queued: 'Queued', resumed: 'Picked up again' }[result] };
  }
  if (result === 'blocked') return { ok: false, refetch: true, text: sentence || 'That isn’t possible right now.' };
  // A write that got no answer, which Capsid has looked for in the session: it isn't there (send it again), or that can't be told.
  // Either way the words stay where they are, so a second try is the same message, which the Mac knows.
  if (result === 'retry') return { ok: false, refetch: true, text: sentence || 'That didn’t go through. Try again.' };
  if (result === 'unknown') return { ok: false, refetch: true, text: sentence || 'Not sure that went through. Look at it on your Mac before you try again.' };
  if (status === 403 && !sentence) return { ok: false, refetch: true, text: 'Actions are off in Capsid’s Settings.' };
  return { ok: false, refetch: true, open: true, text: sentence || 'Couldn’t do that from here. Open it on your Mac.' };
}

// How long the Mac gives a write before it looks for it in the session (20 s, and a read), and a photo's upload as well.
const WRITE_SLOW_MS = 22000;
const PHOTO_SLOW_MS = 85000;

// One path for approve, answer, permission and message: disable, post, say what happened, refetch.
async function doAction(id, kind, path, body, slowMs = WRITE_SLOW_MS) {
  const u = ui(id);
  if (u.busy[kind]) return null;
  u.busy[kind] = true;
  redrawSession(id);
  // No answer yet: by now the Mac is looking for the write in the session, and the phone says so until it hears.
  const slow = setTimeout(() => setNote(id, { text: 'Not sure that went through. Checking…' }, 120000), slowMs);
  let result;
  try {
    result = describe(await send(path, body));
  } catch (e) {
    clearTimeout(slow);
    if (e instanceof Unauth) { u.busy[kind] = false; showPair(); return null; }
    result = { ok: false, refetch: false, text: 'Couldn’t reach your Mac. Try again.' };
  }
  clearTimeout(slow);
  u.busy[kind] = false;
  setNote(id, { text: result.text, open: !!result.open }, result.open ? 12000 : result.ok ? 5000 : 9000);
  if (result.refetch) await loadSession(id, true);
  redrawSession(id);
  return result;
}

async function sendMessage(id) {
  const u = ui(id);
  const text = u.draft.trim();
  const d = S.sess[id] && S.sess[id].data;
  if (u.busy.message || u.sending || !d || !d.can || !d.can.message) return;
  if (u.photo) {
    if (photoReady(u.photo)) await sendPhoto(id, text, u.photo);
    return;
  }
  if (!text) return;
  if (!u.msg || u.msg.text !== text) u.msg = { id: uuid(), text }; // a retry of the same words keeps its id
  const result = await doAction(id, 'message', '/api/sessions/' + id + '/message', { text, id: u.msg.id });
  if (result && result.ok) clearComposer(id);
}

function clearComposer(id) {
  const u = ui(id);
  u.draft = '';
  u.msg = null;
  u.photo = null;
  const dock = root.querySelector('.dock');
  const ta = dock && dock.dataset.sess === id ? dock.querySelector('.composer-ta') : null;
  if (ta) ta.value = '';
  paintDock(id);
}

// The photo, with the words as its caption, as one message. A retry of the same photo and words keeps its id.
async function sendPhoto(id, text, photo) {
  const u = ui(id);
  if (!photo.sent || photo.sent.text !== text) photo.sent = { id: photo.sent ? uuid() : photo.id, text };
  u.sending = true;
  setNote(id, { text: 'Sending photo…' }, 180000);
  let image = '';
  try { image = await blobBase64(photo.blob); } catch { /* handled below */ }
  u.sending = false;
  if (!image) return setNote(id, { text: 'Couldn’t read the photo. Remove it and pick it again.' }, 9000);
  const result = await doAction(id, 'message', '/api/sessions/' + id + '/photo', { image, text, id: photo.sent.id }, PHOTO_SLOW_MS);
  if (result && result.ok) clearComposer(id);
}

/* ---------- Browse: projects, a project's sessions, starting a session ---------- */

const quiet = (t) => h('p', { class: 'quiet', text: t });
const isBrowseOff = (x) => !!x && x.status === 403 && !!x.data && x.data.error === 'browseOff';
const errorCard = (text, retry) => h('div', { class: 'card pad' }, h('p', { class: 'n-note', text }), h('button', { class: 'btn retry', type: 'button', text: 'Try again', onclick: retry }));

function setBrowseOff() {
  S.me = { ...(S.me || {}), browse: false };
  render(true);
}

const projName = (pid) => (S.projects.list.find((p) => p.id === pid) || {}).name || 'Project';
const proj = (pid) => (S.proj[pid] ||= { items: [], next: null, q: '', applied: null, busy: false, err: false, loaded: false, seq: 0, t: 0 });

async function loadProjects(force = false) {
  const P = S.projects;
  if (P.busy || (!force && P.loaded && Date.now() - P.at < 10000)) return;
  P.busy = true;
  try {
    const d = await api('/api/projects');
    P.list = Array.isArray(d && d.projects) ? d.projects.filter((p) => p && RE.pid.test(p.id)) : [];
    P.loaded = true;
    P.err = false;
    P.at = Date.now();
  } catch (e) {
    P.busy = false;
    if (e instanceof Unauth) return showPair();
    if (isBrowseOff(e)) return setBrowseOff();
    P.err = true;
    return onProjects();
  }
  P.busy = false;
  onProjects();
}

function onProjects() {
  const r = route();
  for (const el of root.querySelectorAll('[data-ptitle]')) el.textContent = projName(el.dataset.ptitle);
  if (r.name === 'project') { const t = root.querySelector('.bar-t'); if (t) t.textContent = projName(r.pid); }
  if (S.split) { if (S.side.tab === 'projects' && !S.side.pid) refreshSide(); } else if (r.name === 'projects') render(false, true);
}

function projectsContent() {
  const P = S.projects;
  let body;
  if (!P.loaded) body = P.err ? errorCard('Couldn’t load your projects.', () => { P.err = false; loadProjects(true); }) : quiet('Loading…');
  else if (!P.list.length) body = h('div', { class: 'group' }, h('div', { class: 'empty', text: 'No projects yet' }));
  else {
    body = h('ul', { class: 'group' }, P.list.map((p) => h('li', null,
      h('a', { class: 'row', href: '#/projects/' + p.id, 'data-key': 'p:' + p.id },
        h('span', { class: 'row-main' },
          h('span', { class: 'title', text: p.name || 'Untitled project' }),
          h('span', { class: 'sub' }, `${p.sessions || 0} ${p.sessions === 1 ? 'session' : 'sessions'}`, p.lastActive ? [' · ', rel(p.lastActive)] : null)),
        icon('chev', 'sm chev')))));
  }
  return [h('h1', { class: 'large', tabindex: '-1', text: 'Projects' }), body];
}

async function loadProject(pid, more) {
  const P = proj(pid);
  if (more && (P.busy || !P.next)) return;
  const q = P.q.trim().length >= 2 ? P.q.trim() : '';
  const seq = ++P.seq;
  P.busy = true;
  P.err = false;
  paintProject(pid);
  const qs = [];
  if (more) qs.push('before=' + encodeURIComponent(P.next));
  if (q) qs.push('q=' + encodeURIComponent(q));
  try {
    const d = await api(`/api/projects/${pid}/sessions` + (qs.length ? '?' + qs.join('&') : ''), 'GET', undefined, 'p:' + pid);
    if (seq !== P.seq) return; // a newer search has taken over
    const rows = Array.isArray(d && d.sessions) ? d.sessions.filter((x) => x && RE.sid.test(x.id)) : [];
    P.items = more ? P.items.concat(rows) : rows;
    P.next = (d && d.next) || null;
    P.applied = q;
    P.loaded = true;
  } catch (e) {
    if (seq !== P.seq) return;
    if (e instanceof Unauth) { P.busy = false; return showPair(); }
    if (isBrowseOff(e)) { P.busy = false; return setBrowseOff(); }
    if (!(e instanceof Aborted)) P.err = true; // left while it was coming: not an error, and the list is asked for again on return
  }
  P.busy = false;
  paintProject(pid);
}

// 300 ms after the last keystroke; one character is not a search.
function onSearch(pid, value) {
  const P = proj(pid);
  P.q = value;
  clearTimeout(P.t);
  const eff = value.trim().length >= 2 ? value.trim() : '';
  if (eff === P.applied) return;
  P.t = setTimeout(() => loadProject(pid, false), 300);
}

function sessionRow(s) {
  return h('li', null, h('a', { class: 'row', href: sessionHref(s.id), 'data-key': 's:' + s.id, 'aria-current': current(s.id) },
    h('span', { class: 'mk', 'aria-hidden': 'true' }, statusMark(s.state, heldBy(s.id))),
    h('span', { class: 'row-main' },
      h('span', { class: 'title', text: s.title || 'Untitled session' }),
      s.sentence ? h('span', { class: 'sub', text: s.sentence }) : null),
    h('span', { class: 'side' }, rel(s.updatedAt)),
    icon('chev', 'sm chev')));
}

function projectRows(pid) {
  const P = proj(pid);
  const q = P.q.trim().length >= 2 ? P.q.trim() : '';
  const rows = [h('li', null, h('button', { class: 'row newrow', type: 'button', 'data-key': 'new:' + pid, onclick: () => newSessionSheet(pid) },
    icon('plus', 'sm'), h('span', { class: 'row-main' }, h('span', { class: 'title', text: 'New session' }))))];
  rows.push(...P.items.map(sessionRow));
  const out = [h('ul', { class: 'group' }, rows)];
  if (!P.loaded && !P.err) out.push(quiet('Loading…'));
  if (P.err) out.push(errorCard('Couldn’t load these sessions.', () => loadProject(pid, P.items.length > 0 && !!P.next)));
  if (P.loaded && !P.items.length) out.push(quiet(q ? `No sessions match “${q}”.` : 'No sessions in this project yet.'));
  if (P.next && !P.err) {
    out.push(h('button', { class: 'btn load-more', type: 'button', text: P.busy ? 'Loading…' : 'Load more', disabled: P.busy, 'data-key': 'more:' + pid, onclick: () => loadProject(pid, true) }));
  }
  return out;
}

function paintProject(pid) {
  for (const el of root.querySelectorAll(`.plist[data-pid="${pid}"]`)) el.replaceChildren(...projectRows(pid));
}

function projectContent(pid) {
  const P = proj(pid);
  const search = h('input', {
    class: 'search', type: 'search', placeholder: 'Search sessions', 'aria-label': 'Search sessions in ' + projName(pid), enterkeyhint: 'search',
    autocomplete: 'off', autocapitalize: 'off', autocorrect: 'off', spellcheck: 'false', 'data-key': 'search',
    oninput: (e) => onSearch(pid, e.target.value),
  });
  search.value = P.q;
  const list = h('div', { class: 'plist', 'data-pid': pid });
  list.append(...projectRows(pid));
  return [h('h1', { class: 'large', tabindex: '-1', 'data-ptitle': pid, text: projName(pid) }), h('div', { class: 'search-wrap' }, search), list];
}

/* ----- starting a session ----- */

function newSessionSheet(pid) {
  const st = (S.newSess[pid] ||= { text: '', msg: null, plan: false, photo: null });
  const before = document.activeElement;
  let busy = false;
  const ta = h('textarea', {
    class: 'ns-text', rows: '5', maxlength: '4000', placeholder: 'What should Claude work on?', 'aria-label': 'What should Claude work on?',
    autocapitalize: 'sentences', enterkeyhint: 'enter', 'data-key': 'ns-text',
  });
  ta.value = st.text;
  const sw = h('button', {
    class: 'row sw ns-sw', type: 'button', role: 'switch', 'aria-checked': st.plan ? 'true' : 'false', 'data-key': 'ns-plan',
    onclick: () => { st.plan = !st.plan; sw.setAttribute('aria-checked', st.plan ? 'true' : 'false'); },
  }, h('span', { class: 'row-main' }, h('span', { class: 'title', text: 'Plan first' }), h('span', { class: 'sub', text: 'Claude drafts a plan for you to approve before it starts.' })),
  h('span', { class: 'switch', 'aria-hidden': 'true' }));
  const note = h('p', { class: 'msg', role: 'status', hidden: true });
  const say = (t) => { note.textContent = t; note.hidden = !t; };
  // A photo can start a session with no words; one still being made ready, or one that failed, holds Start back.
  const canStart = () => !busy && (st.photo ? photoReady(st.photo) : !!ta.value.trim());
  const start = h('button', { class: 'btn primary', type: 'button', text: 'Start', disabled: !st.text.trim() && !photoReady(st.photo), 'data-key': 'ns-start', onclick: () => go() });
  const cam = photoButton('btn small ns-cam', 'Add a photo', (f) => stagePhoto(st, f, paintPhoto), icon('camera', 'sm'), 'Add a photo');
  const photoBox = h('div', { class: 'ns-photo' });
  function paintPhoto() {
    const p = st.photo;
    photoBox.replaceChildren(...(p ? [photoChip(p, () => { st.photo = null; paintPhoto(); }, busy)] : [cam.button]));
    start.disabled = !canStart();
  }
  const cancel = h('button', { class: 'btn', type: 'button', text: 'Cancel', onclick: () => close() });
  const scrim = h('div', { class: 'scrim top', onclick: (e) => { if (e.target === scrim) close(); } },
    h('div', { class: 'sheet wide', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'ns-h' },
      h('div', { class: 'box left' },
        h('p', { class: 'sec-h', id: 'ns-h', text: projName(pid) }),
        ta, photoBox, cam.input, h('div', { class: 'group ns-opts' }, sw), note, start),
      cancel));
  paintPhoto();
  ta.addEventListener('input', () => { st.text = ta.value; start.disabled = !canStart(); });
  function key(e) { if (e.key === 'Escape') close(); }
  function close() {
    document.removeEventListener('keydown', key);
    root.inert = false;
    scrim.remove();
    if (before && before.isConnected) before.focus({ preventScroll: true });
  }
  async function go() {
    const text = ta.value.trim();
    const photo = photoReady(st.photo) ? st.photo : null;
    if ((!text && !photo) || busy || (st.photo && !photo)) return;
    // a retry of the same words (and photo) keeps its id
    if (!st.msg || st.msg.text !== text || st.msg.plan !== st.plan || st.msg.photo !== (photo ? photo.id : '')) st.msg = { id: photo && !st.msg ? photo.id : uuid(), text, plan: st.plan, photo: photo ? photo.id : '' };
    busy = true;
    start.disabled = true;
    start.textContent = photo ? 'Sending photo…' : 'Starting…';
    if (st.photo) paintPhoto();
    say('');
    let out;
    try {
      if (photo) {
        const image = await blobBase64(photo.blob);
        out = await send(`/api/projects/${pid}/photo`, { image, text, id: st.msg.id, planFirst: st.plan });
      } else out = await send(`/api/projects/${pid}/sessions`, { text, id: st.msg.id, planFirst: st.plan });
    } catch (e) {
      busy = false;
      start.textContent = 'Start';
      if (st.photo) paintPhoto();
      start.disabled = !canStart();
      if (e instanceof Unauth) { close(); return showPair(); }
      say(e instanceof Down ? 'Couldn’t reach your Mac. Try again.' : 'Couldn’t read the photo. Remove it and pick it again.');
      return;
    }
    busy = false;
    start.textContent = 'Start';
    if (st.photo) paintPhoto();
    start.disabled = !canStart();
    const d = out.data;
    if (d && d.result === 'started' && typeof d.id === 'string' && RE.sid.test(d.id) && out.status < 300) {
      Object.assign(st, { text: '', msg: null, plan: false, photo: null });
      close();
      location.hash = '#/session/' + d.id;
      return;
    }
    const trouble = photoTrouble(out.status, d);
    if (trouble) say(trouble);
    else if (out.status === 429) say(d && d.error === 'tooMany' ? 'Too many actions just now. Try again in a minute.' : slowText(d));
    else if (isBrowseOff(out)) { close(); setBrowseOff(); } else if (out.status === 403 && !(d && d.sentence)) say('Actions are off in Capsid’s Settings.');
    else say((d && typeof d.sentence === 'string' && d.sentence) || 'Couldn’t start it from here. Open Capsid on your Mac.');
  }
  document.addEventListener('keydown', key);
  document.body.append(scrim);
  root.inert = true;
  ta.focus();
}

/* ---------- Artifacts and the file viewer ---------- */

const KIND_ICON = { image: 'image', svg: 'image', markdown: 'doc', text: 'text', table: 'table', html: 'code', pdf: 'file', notebook: 'file', other: 'file' };
const KIND_LABEL = { image: 'Image', svg: 'SVG image', markdown: 'Markdown', text: 'Text', table: 'Table', html: 'HTML', pdf: 'PDF', notebook: 'Notebook', other: 'File' };
const kindIcon = (k) => KIND_ICON[k] || 'file';
const MAX_DOWNLOAD = 8 * 1024 * 1024;

function fmtSize(n) {
  if (!Number.isFinite(n) || n < 0) return '';
  if (n < 1024) return n + ' B';
  if (n < 1048576) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + ' KB';
  return (n / 1048576).toFixed(1) + ' MB';
}

const art = (id) => (S.art[id] ||= { items: [], loaded: false, busy: false, err: false });
// A name is shown without bidi overrides and control characters, so it can't pose as another extension.
const dispName = (n) => String(n == null ? '' : n).replace(/[\u0000-\u001f\u007f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, '').trim();
const fileName = (v) => dispName(S.files[v] && S.files[v].name) || 'File';
const fileHref = (id, v) => (RE.vid.test(v) ? `#/session/${id}/file/${v}` : null);
const safeName = (n) => dispName(n).replace(/[\\/]/g, '_').slice(0, 200) || 'file';

// An image from Capsid's files: loaded once it is near the screen, taking its turn with the other
// transfers, and tried twice more a few seconds apart before `failed` runs (Capsid may have asked
// it to wait).
const nearScreen = 'IntersectionObserver' in window
  ? new IntersectionObserver((es) => {
    for (const e of es) if (e.isIntersecting) { nearScreen.unobserve(e.target); e.target._load(); }
  }, { rootMargin: '300px 0px' })
  : null;

function fileImg(props, src, failed) {
  const img = h('img', props);
  let tries = 0;
  let disposed = false;
  let slot = null;
  let retryTimer = 0;
  let parked = false;
  img._disposeFileImage = () => {
    disposed = true;
    if (nearScreen) nearScreen.unobserve(img);
    if (slot) slot.cancel();
    clearTimeout(retryTimer);
  };
  // The page is put away: a load still waiting for a slot steps out of the queue, and a retry waits. A load that has
  // started keeps its slot until it ends. `_resume` asks again once the page is back.
  img._park = () => {
    if (disposed) return;
    if (slot) { parked = true; slot.cancel(); }
    if (retryTimer) { clearTimeout(retryTimer); retryTimer = 0; parked = true; }
  };
  img._resume = () => {
    if (!parked || disposed) return;
    parked = false;
    img._load();
  };
  img._load = async () => {
    if (disposed || !img.isConnected) return;
    slot = fileSlot();
    const started = await slot.ready;
    slot = null;
    if (!started) return;
    if (disposed || !img.isConnected) { giveSlot(); return; } // gone while waiting, even on the first try
    const ok = await new Promise((r) => {
      let t = 0;
      const over = (v) => { clearTimeout(t); img.onload = img.onerror = null; r(v); };
      img.onload = () => over(true);
      img.onerror = () => over(false);
      t = setTimeout(() => over(false), 20000);
      img.removeAttribute('src');
      img.src = src;
    });
    giveSlot();
    if (ok || disposed || !img.isConnected) return;
    if (++tries < 3) retryTimer = setTimeout(() => { retryTimer = 0; img._load(); }, tries * 2500 + Math.random() * 1000);
    else failed(img);
  };
  if (nearScreen) nearScreen.observe(img); else queueMicrotask(img._load);
  return img;
}

function parkImages(park) {
  for (const img of root.querySelectorAll('img')) {
    const call = park ? img._park : img._resume;
    if (call) call();
  }
}

// A file's bytes for the person: its turn among the transfers, then one try. What Capsid answered
// says what went wrong.
async function getFile(f) {
  await takeSlot();
  try {
    const res = await fetch('/api/files/' + f.v + '/download', { cache: 'no-store' });
    if (res.status === 401) return { unauth: true };
    if (!res.ok) {
      let data = null;
      try { data = await res.json(); } catch { /* not JSON */ }
      return { status: res.status, data };
    }
    return { file: new File([await res.blob()], safeName(f.name), { type: res.headers.get('Content-Type') || 'application/octet-stream' }) };
  } catch {
    return { down: true };
  } finally {
    giveSlot();
  }
}

const fileTrouble = (r) => (r.status === 429 ? slowText(r.data)
  : r.status === 413 ? 'Too big for the phone. Open it on your Mac.'
    : r.down || r.status === 502 || r.status === 504 ? 'Couldn’t reach your Mac. Try again.' : 'Couldn’t get this file from your Mac. Try again.');

function rememberFiles(files) {
  for (const f of files || []) if (f && RE.vid.test(f.v)) S.files[f.v] = { ...S.files[f.v], ...f };
}

async function loadArtifacts(id) {
  if (!browseOn()) return;
  const A = art(id);
  if (A.busy) return;
  A.busy = true;
  try {
    const d = await api('/api/sessions/' + id + '/artifacts', 'GET', undefined, 's:' + id);
    A.items = (Array.isArray(d && d.artifacts) ? d.artifacts : []).filter((f) => f && RE.vid.test(f.v));
    rememberFiles(A.items);
    A.loaded = true;
    A.err = false;
  } catch (e) {
    A.busy = false;
    if (e instanceof Aborted) return;
    if (e instanceof Unauth) return showPair();
    if (isBrowseOff(e)) return setBrowseOff();
    A.err = true;
    return onArtifacts(id);
  }
  A.busy = false;
  onArtifacts(id);
  trimCaches();
}

function onArtifacts(id) {
  const r = route();
  if ((r.name === 'artifacts' || r.name === 'file') && r.id === id) {
    if (r.name === 'file') maybeLoadText(r.v, id);
    render(false, true);
  } else if (r.name === 'session' && r.id === id) redrawSession(id);
}

function maybeLoadText(v, id) {
  const f = S.files[v];
  const had = S.ftext[v];
  if (!f || !['markdown', 'text', 'table'].includes(f.kind) || (had && !(had.phase === 'err' && had.status === 429))) return;
  const mine = (S.ftext[v] = { phase: 'loading' });
  api('/api/files/' + v + '/text', 'GET', undefined, 's:' + id)
    .then((d) => { S.ftext[v] = { phase: 'ok', data: d }; trimCaches(); })
    .catch((e) => {
      if (e instanceof Unauth) return showPair();
      if (e instanceof Aborted) { // left while it was coming: it is asked for again when the file is opened, or the page comes back
        if (S.ftext[v] === mine) delete S.ftext[v];
        return;
      }
      if (isBrowseOff(e)) return setBrowseOff();
      S.ftext[v] = { phase: 'err', status: e.status };
    })
    .finally(() => { const r = route(); if (r.name === 'file' && r.v === v) render(false, true); });
}

// This session's own listed images: the only ones a markdown file may show.
function imagesOf(id) {
  const out = art(id).items.filter((f) => f.kind === 'image');
  const H = S.hist[id];
  if (H) for (const it of Object.values(H.items)) for (const f of it.files || []) if (f.kind === 'image' && !out.some((o) => o.v === f.v)) out.push(f);
  return out;
}

function imageFor(id, src) {
  let name = String(src);
  try { name = decodeURIComponent(name); } catch { /* keep it as written */ }
  name = name.split('#')[0].split('?')[0].split('/').pop();
  if (!name) return null;
  const imgs = imagesOf(id);
  const hit = imgs.find((f) => f.name === name) || imgs.find((f) => String(f.name).toLowerCase() === name.toLowerCase());
  return hit ? hit.v : null;
}

const mdFor = (id) => ({ image: (src) => imageFor(id, src) });

function thumbTile(id, f) {
  const img = fileImg({ alt: '', width: '120', height: '120' }, '/api/files/' + f.v + '/thumb?w=120', (el) => el.replaceWith(icon('image', 'big')));
  return h('a', { class: 'thumb', href: fileHref(id, f.v), 'aria-label': dispName(f.name) || 'Image', 'data-key': 'f:' + f.v }, img);
}

function fileRow(id, f) {
  return h('li', null, h('a', { class: 'row', href: fileHref(id, f.v), 'data-key': 'f:' + f.v },
    h('span', { class: 'kind-ic', 'aria-hidden': 'true' }, icon(kindIcon(f.kind), 'sm')),
    h('span', { class: 'row-main' },
      h('span', { class: 'title fname', text: dispName(f.name) || 'File' }),
      h('span', { class: 'sub' }, [KIND_LABEL[f.kind] || 'File', fmtSize(f.size)].filter(Boolean).join(' · '), f.at ? [' · ', rel(f.at)] : null)),
    icon('chev', 'sm chev')));
}

function artifactsContent(id) {
  const A = art(id);
  const nodes = [h('h1', { class: 'sess', tabindex: '-1', text: 'Artifacts' }), h('p', { class: 'sub tight-sub', text: sessionTitle(id) })];
  if (!A.loaded) nodes.push(A.err ? errorCard('Couldn’t load the artifacts.', () => { A.err = false; render(false, true); loadArtifacts(id); }) : quiet('Loading…'));
  else if (!A.items.length) nodes.push(h('div', { class: 'group' }, h('div', { class: 'empty', text: 'This session has made no artifacts yet.' })));
  else {
    const imgs = A.items.filter((f) => f.kind === 'image');
    const rest = A.items.filter((f) => f.kind !== 'image');
    if (imgs.length) nodes.push(section('Images', imgs.length, h('div', { class: 'thumbs' }, imgs.map((f) => thumbTile(id, f)))));
    if (rest.length) nodes.push(section('Files', rest.length, h('ul', { class: 'group' }, rest.map((f) => fileRow(id, f)))));
  }
  return nodes;
}

const canShareFiles = () => {
  try { return typeof navigator.share === 'function' && typeof navigator.canShare === 'function' && navigator.canShare({ files: [new File(['x'], 'x.txt', { type: 'text/plain' })] }); } catch { return false; }
};

function downloadBlock(id, f, quietStyle) {
  if (f.size > MAX_DOWNLOAD) {
    const b = h('button', { class: 'btn', type: 'button', text: 'Open on Mac', onclick: async () => { b.disabled = true; await openOnMac(id); b.disabled = false; b.textContent = S.open[id] && S.open[id].phase === 'done' ? 'Opened on your Mac ✓' : 'Open on Mac'; } });
    return h('div', { class: 'act' }, h('p', { class: 'quiet', text: 'Too big for the phone. Open it on your Mac.' }), b);
  }
  const note = h('p', { class: 'msg bad', role: 'status', hidden: true });
  const say = (t) => { note.textContent = t; note.hidden = !t; };
  // Fetched first, so a busy Capsid is a sentence here rather than a saved file holding its answer.
  const link = h('a', {
    class: 'btn' + (quietStyle ? '' : ' primary'), href: '/api/files/' + f.v + '/download', download: safeName(f.name),
    onclick: async (e) => {
      e.preventDefault();
      if (link.getAttribute('aria-busy') === 'true') return;
      link.setAttribute('aria-busy', 'true');
      say('');
      const r = await getFile(f);
      link.removeAttribute('aria-busy');
      if (r.unauth) return showPair();
      if (!r.file) return say(fileTrouble(r));
      const url = URL.createObjectURL(r.file);
      const a = h('a', { href: url, download: r.file.name, hidden: true });
      document.body.append(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    },
  }, icon('download', 'sm'), 'Download · ' + fmtSize(f.size));
  const out = h('div', { class: 'act dl' }, link);
  if (canShareFiles()) {
    const share = h('button', { class: 'btn', type: 'button', onclick: async () => {
      share.disabled = true;
      say('');
      const r = await getFile(f);
      if (r.unauth) return showPair();
      if (!r.file) say(fileTrouble(r));
      else {
        try {
          if (navigator.canShare({ files: [r.file] })) await navigator.share({ files: [r.file] });
        } catch { /* cancelled or unsupported: the Download button is still there */ }
      }
      share.disabled = false;
    } }, icon('share', 'sm'), 'Share');
    out.append(share);
  }
  out.append(note);
  return out;
}

function tableViewer(d) {
  const cols = Array.isArray(d.columns) ? d.columns : [];
  const rows = Array.isArray(d.rows) ? d.rows : [];
  const cell = (v) => (v == null ? '' : String(v));
  const table = h('table', { class: 'tbl' },
    h('thead', null, h('tr', null, cols.map((c) => h('th', { scope: 'col', text: cell(c) })))),
    h('tbody', null, rows.map((r) => h('tr', null, cols.map((_, k) => (k === 0 ? h('th', { scope: 'row', text: cell(r[k]) }) : h('td', { text: cell(r[k]) })))))));
  return [
    h('div', { class: 'tbl-wrap', tabindex: '0', role: 'region', 'aria-label': 'Table' }, table),
    d.truncated ? h('p', { class: 'foot', text: `Showing the first ${rows.length} rows${cols.length >= 30 ? ' and 30 columns' : ''}. Download the file for the rest.` }) : null,
  ];
}

function textViewer(id, f) {
  const T = S.ftext[f.v];
  if (!T || T.phase === 'loading') return [quiet('Loading…')];
  if (T.phase === 'err') return [h('p', { class: 'quiet', text: T.status === 413 ? 'This file is too big to show here.' : T.status === 429 ? 'Capsid is busy. Open this file again in a moment.' : 'Couldn’t show this file here.' }), downloadBlock(id, f, false)];
  const d = T.data || {};
  if (f.kind === 'table' && d.kind === 'table') return [...tableViewer(d), downloadBlock(id, f, true)];
  const text = typeof d.text === 'string' ? d.text : '';
  const note = d.truncated ? h('p', { class: 'foot', text: 'Showing the first 256 KB. Download the file for the rest.' }) : null;
  if (f.kind === 'markdown' || d.kind === 'markdown') {
    return [h('div', { class: 'card pad' }, h('div', { class: 'md' }, md(text, mdFor(id)))), note, downloadBlock(id, f, true)];
  }
  const pre = h('pre', { class: 'viewer-pre' + (S.wrap ? ' wrap' : ''), tabindex: '0' }, h('code', { text }));
  const wrap = h('button', {
    class: 'btn small', type: 'button', 'aria-pressed': S.wrap ? 'true' : 'false', text: 'Wrap lines',
    onclick: (e) => { S.wrap = !S.wrap; pre.classList.toggle('wrap', S.wrap); e.currentTarget.setAttribute('aria-pressed', String(S.wrap)); },
  });
  return [h('div', { class: 'viewer-tools' }, wrap), pre, note, downloadBlock(id, f, true)];
}

function fileContent(id, v) {
  const f = S.files[v];
  const A = art(id);
  if (!f) {
    const note = A.err ? errorCard('Couldn’t load this file.', () => { A.err = false; render(false, true); loadArtifacts(id); }) : A.loaded ? quiet('This file isn’t available any more.') : quiet('Loading…');
    return [h('h1', { class: 'sess', tabindex: '-1', text: 'File' }), note];
  }
  const nodes = [
    h('h1', { class: 'sess fname', tabindex: '-1', text: dispName(f.name) || 'File' }),
    h('p', { class: 'sub tight-sub', text: [KIND_LABEL[f.kind] || 'File', fmtSize(f.size)].filter(Boolean).join(' · ') }),
  ];
  if (f.kind === 'image') {
    const box = h('div', { class: 'viewer-img-wrap' });
    box.append(fileImg({ class: 'viewer-img', alt: dispName(f.name) || 'Image' }, '/api/files/' + f.v + '/thumb?w=800',
      () => box.replaceChildren(h('p', { class: 'quiet', text: 'Couldn’t show this image here.' }))));
    nodes.push(box, downloadBlock(id, f, true));
  } else if (f.kind === 'markdown' || f.kind === 'text' || f.kind === 'table') {
    nodes.push(...textViewer(id, f));
  } else {
    // HTML, SVG and notebooks are never shown on this page; everything else is a download too.
    nodes.push(downloadBlock(id, f, false));
  }
  return nodes;
}

/* ---------- History: the whole conversation, paged backward ---------- */

const hist = (id) => (S.hist[id] ||= { items: dict(), total: 0, from: null, at: '', busy: false, err: false, loaded: false, failed: false, rev: 0, full: dict(), cutBusy: dict(), cutErr: dict() });

function mergeHist(H, d) {
  for (const it of Array.isArray(d && d.items) ? d.items : []) {
    if (!it || !Number.isInteger(it.i)) continue;
    // A row read again that says the same keeps its object, so its element stays as it is (setHistory).
    const had = H.items[it.i];
    if (!had || JSON.stringify(had) !== JSON.stringify(it)) H.items[it.i] = it;
    rememberFiles(it.files);
  }
  if (Number.isInteger(d && d.total)) H.total = d.total;
  if (Number.isInteger(d && d.from)) H.from = H.from == null ? d.from : Math.min(H.from, d.from);
  H.rev++;
}

// The newest page, merged by index. `at` is the session's stamp (histStamp) it was read after, kept once it has been read.
async function loadHistory(id, at = '') {
  if (!browseOn()) return;
  const H = hist(id);
  try {
    mergeHist(H, await api(`/api/sessions/${id}/history`, 'GET', undefined, 's:' + id));
    H.loaded = true;
    H.failed = false;
    H.at = at;
  } catch (e) {
    if (e instanceof Aborted) return;
    if (e instanceof Unauth) return showPair();
    if (isBrowseOff(e)) return setBrowseOff();
    if (!H.loaded) H.failed = true;
    return;
  }
  redrawSession(id);
  trimCaches();
}

const scroller = () => (S.split ? root.querySelector('.detail') : document.scrollingElement);

// Keep whatever row is at the top of the screen where it is while rows are added above it.
function captureAnchor() {
  const sc = scroller();
  if (!sc) return null;
  const edge = S.split ? sc.getBoundingClientRect().top : 0;
  for (const r of root.querySelectorAll('[data-r="convo"] [data-i]')) {
    const b = r.getBoundingClientRect();
    if (b.bottom > edge + 60) return { i: r.dataset.i, top: b.top };
  }
  return null;
}
function restoreAnchor(a) {
  if (!a) return;
  const el = root.querySelector(`[data-r="convo"] [data-i="${a.i}"]`);
  if (!el) return;
  const d = el.getBoundingClientRect().top - a.top;
  if (!d) return;
  if (S.split) root.querySelector('.detail').scrollTop += d;
  else window.scrollBy(0, d);
}

async function loadEarlier(id) {
  const H = hist(id);
  if (H.busy || H.from == null || H.from <= 0) return;
  H.busy = true;
  H.err = false;
  redrawSession(id);
  let d;
  try {
    d = await api(`/api/sessions/${id}/history?before=${H.from}`, 'GET', undefined, 's:' + id);
  } catch (e) {
    H.busy = false;
    if (e instanceof Unauth) return showPair();
    if (isBrowseOff(e)) return setBrowseOff();
    if (!(e instanceof Aborted)) H.err = true; // left while it was coming: not an error; scrolling to the top asks again
    return redrawSession(id);
  }
  const anchor = captureAnchor();
  mergeHist(H, d);
  H.busy = false;
  redrawSession(id);
  restoreAnchor(anchor);
  trimCaches();
  // "More" buttons are placed a frame later and can change a row's height: hold the position then too
  requestAnimationFrame(() => requestAnimationFrame(() => restoreAnchor(anchor)));
}

async function showAll(id, i) {
  const H = hist(id);
  if (H.cutBusy[i]) return;
  H.cutBusy[i] = true;
  H.cutErr[i] = false;
  H.rev++;
  redrawSession(id);
  try {
    const d = await api(`/api/sessions/${id}/turn/${i}`, 'GET', undefined, 's:' + id);
    if (d && typeof d.text === 'string') H.full[i] = d.text;
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    if (!(e instanceof Aborted)) H.cutErr[i] = true; // left while it was coming: not an error; "Show all" is still there
  }
  H.cutBusy[i] = false;
  H.rev++;
  redrawSession(id);
  trimCaches();
}

function chips(id, files) {
  const list = (files || []).filter((f) => f && RE.vid.test(f.v));
  if (!list.length) return null;
  return h('div', { class: 'chips' }, list.map((f) => h('a', { class: 'chip', href: fileHref(id, f.v), 'data-key': 'chip:' + f.v },
    icon(kindIcon(f.kind), 'sm'), h('span', { class: 'chip-n', text: dispName(f.name) || 'File' }), h('span', { class: 'chip-s', text: fmtSize(f.size) }))));
}

// Steps, plans, questions and helpers are one quiet line each.
const quietRow = (it, ic, text, cls = '') => h('li', { class: 'qrow ' + cls, 'data-i': String(it.i) }, icon(ic, 'sm'), h('span', { text }));

function histRow(id, it, H, u) {
  if (it.role === 'you' || it.role === 'claude') {
    const key = 'h' + it.i;
    const open = !!u.more[key];
    const full = H.full[it.i];
    const text = typeof full === 'string' ? full : it.text;
    const cut = it.cut && typeof full !== 'string';
    return h('li', { class: 'turn', 'data-i': String(it.i) },
      h('div', { class: 'turn-h' }, h('span', { class: 'who', text: it.role === 'you' ? 'You' : 'Claude' }), it.at ? h('span', { class: 'when', text: when(it.at) }) : null),
      h('div', { class: 'md clamp' + (open ? ' open' : '') }, md(text, mdFor(id))),
      h('div', { class: 'turn-acts' },
        h('button', { class: 'more', type: 'button', hidden: !open, text: open ? 'Less' : 'More', 'data-more': '1', 'data-key': 'm:' + key, onclick: () => { u.more[key] = !open; redrawSession(id); } }),
        cut ? h('button', { class: 'more', type: 'button', text: H.cutBusy[it.i] ? 'Loading…' : 'Show all', disabled: !!H.cutBusy[it.i], 'data-key': 'all:' + it.i, onclick: () => showAll(id, it.i) }) : null,
        H.cutErr[it.i] ? h('span', { class: 'when', text: 'Couldn’t load the whole message.' }) : null),
      chips(id, it.files));
  }
  switch (it.kind) {
    case 'steps': return it.failed
      ? h('li', { class: 'qrow', 'data-i': String(it.i) }, icon('alert', 'sm mark-err'), h('span', { text: (it.line || 'Ran some steps') + ' (it failed)' }))
      : quietRow(it, 'terminal', it.line || 'Ran some steps');
    case 'plan': return quietRow(it, 'list', 'Drafted a plan' + (Number.isFinite(it.steps) ? ` · ${it.steps} ${it.steps === 1 ? 'step' : 'steps'}` : ''));
    case 'ask': return h('li', { class: 'qrow ask', 'data-i': String(it.i) }, icon('ask', 'sm'), h('span', null,
      h('span', { text: 'Asked you: ' + (it.q || '') }), it.a ? [h('br'), h('span', { text: 'You answered: ' + it.a })] : null));
    case 'helper': return quietRow(it, 'helper', 'Asked a helper agent');
    case 'toYou': {
      const key = 'h' + it.i;
      const open = !!u.more[key];
      return h('li', { class: 'turn tou', 'data-i': String(it.i) },
        h('div', { class: 'turn-h' }, h('span', { class: 'who quiet-who' }, icon('msg', 'sm'), 'Message to you')),
        h('div', { class: 'md clamp' + (open ? ' open' : '') }, md(it.text, mdFor(id))),
        h('div', { class: 'turn-acts' }, h('button', { class: 'more', type: 'button', hidden: !open, text: open ? 'Less' : 'More', 'data-more': '1', 'data-key': 'm:' + key, onclick: () => { u.more[key] = !open; redrawSession(id); } })),
        chips(id, it.files));
    }
    default: return null;
  }
}

// The top of the conversation: the way to earlier rows, or that there are none. Made again only when it changes
// kind, so a new one is watched (watchHistTop) as before.
function histTop(id, H) {
  if (H.from > 0) {
    if (H.err) return h('div', { class: 'hist-top' }, h('p', { class: 'quiet', text: 'Couldn’t load earlier messages.' }), h('button', { class: 'btn earlier', type: 'button', text: 'Try again', 'data-key': 'earlier', onclick: () => loadEarlier(id) }));
    if (H.busy) return h('div', { class: 'hist-top' }, h('p', { class: 'quiet', text: 'Loading earlier messages…' }));
    return h('div', { class: 'hist-top' }, 'IntersectionObserver' in window ? null : h('button', { class: 'btn earlier', type: 'button', text: 'Load earlier messages', 'data-key': 'earlier', onclick: () => loadEarlier(id) }));
  }
  return h('p', { class: 'hist-begin', text: 'Beginning of the conversation' });
}

// Puts `nodes` in `parent` in that order, leaving in place whatever already is.
function syncChildren(parent, nodes) {
  const wanted = new Set(nodes);
  for (const node of Array.from(parent.childNodes)) if (!wanted.has(node)) node.remove();
  nodes.forEach((node, k) => { if (parent.childNodes[k] !== node) parent.insertBefore(node, parent.childNodes[k] || null); });
}

const sameList = (a, b) => a.length === b.length && a.every((x, k) => x === b[k]);

// The conversation, by index. Each row is kept with what it was drawn from (its item, whether it is open, its whole
// text, its loading and failing), and is made again only when that changes: earlier rows arriving above, or one row's
// More, builds those rows alone and leaves every other element, its images and its place on screen as they are.
// A row with an image link in its text is made again each time, to pick up files listed since.
function setHistory(body, id, H, u) {
  const el = body.querySelector(':scope > [data-r="convo"]');
  if (!el) return;
  const day = dayStart(new Date());
  const sig = JSON.stringify([H.rev, H.from, H.busy, H.err, u.more, Object.keys(H.full).length, H.cutBusy, H.cutErr, day]);
  if (el._hist && el._hist.H === H && el.dataset.sig === sig) return;
  const restore = holdFocus(el);
  el.dataset.sig = sig;
  if (!el._hist || el._hist.H !== H) {
    const ul = h('ul', { class: 'group hist' });
    el._hist = { H, ul, top: null, topKind: '', rows: new Map() };
    replaceContents(el, section('Conversation', 0, [ul]));
  }
  const hs = el._hist;
  const kind = H.from > 0 ? (H.err ? 'err' : H.busy ? 'busy' : 'idle') : 'begin';
  if (kind !== hs.topKind) {
    const top = histTop(id, H);
    if (hs.top) hs.top.replaceWith(top); else hs.ul.before(top);
    hs.top = top;
    hs.topKind = kind;
  }
  // Integer keys come out in ascending order, whatever order they were added in: the rows are in conversation order.
  const items = Object.values(H.items);
  const rows = new Map();
  const stale = [];
  const nodes = [];
  for (const it of items) {
    const made = [it, !!u.more['h' + it.i], H.full[it.i], !!H.cutBusy[it.i], !!H.cutErr[it.i], it.at ? day : 0];
    const text = typeof H.full[it.i] === 'string' ? H.full[it.i] : it.text;
    let row = hs.rows.get(it.i);
    if (row && !(sameList(row.made, made) && !(typeof text === 'string' && text.includes('![')))) { stale.push(row.el); row = null; }
    if (!row) row = { made, el: histRow(id, it, H, u) };
    rows.set(it.i, row);
    if (row.el) nodes.push(row.el);
  }
  for (const [i, row] of hs.rows) if (!rows.has(i)) stale.push(row.el);
  hs.rows = rows;
  syncChildren(hs.ul, nodes);
  for (const old of stale) {
    if (!old || old.isConnected) continue;
    for (const img of old.querySelectorAll('img')) if (img._disposeFileImage) img._disposeFileImage(); // their images go with them
  }
  restore();
}

// Reaching the top of what is loaded loads 50 earlier rows.
let histWatcher = null;
function watchHistTop(sv, id) {
  const el = sv.querySelector('.hist-top');
  if (histWatcher && histWatcher.el === el) return;
  if (histWatcher) histWatcher.io.disconnect();
  histWatcher = null;
  if (!el || !('IntersectionObserver' in window)) return;
  const io = new IntersectionObserver((es) => { if (es.some((e) => e.isIntersecting)) loadEarlier(id); }, { root: S.split ? sv.closest('.detail') : null, rootMargin: '300px 0px -55% 0px' }); // only the upper part of the screen counts
  io.observe(el);
  histWatcher = { el, io };
}

/* ---------- What is kept of screens already left ---------- */

// Reads of sessions and files stay in memory, so going back shows them at once. A Home Screen app lives for days and
// visits many, so what is not on screen is kept within a budget, the one shown least recently going first:
//   sessions  at most 8 other than the open one, and 1.5 million characters (JSON) between them: a session's data, its history
//             rows and its artifact list; one long history can be most of that, and a history page is under 64 KB;
//   texts     at most 4 other than the open file, and 768,000 characters: a text is read up to 256 KB, a table can reach about 1 MB.
// The open session and file are kept however big. What the person typed or chose (`S.ui`, `S.newSess`: drafts, photos,
// answers) is not a read and is never touched; nor is `S.files` (names and sizes, about 200 bytes each: a file named by
// an address must still open). A session or text with a read under way, or a write, is kept until that ends.
const KEEP = { sessions: 8, sessionChars: 1500000, texts: 4, textChars: 768000 };

// The size of a value that does not change, worked out once.
const weights = new WeakMap();
function weigh(value, measure) {
  if (value === null || typeof value !== 'object') return measure(value);
  let n = weights.get(value);
  if (n === undefined) weights.set(value, (n = measure(value)));
  return n;
}
const jsonChars = (value) => JSON.stringify(value).length;

function histChars(H) {
  let n = 0;
  for (const it of Object.values(H.items)) n += weigh(it, jsonChars);
  for (const i in H.full) n += H.full[i].length;
  return n;
}

function sessChars(id) {
  const rec = S.sess[id];
  const H = S.hist[id];
  const A = S.art[id];
  return (rec && rec.data ? weigh(rec.data, jsonChars) : 0) + (H ? histChars(H) : 0) + (A ? weigh(A.items, jsonChars) : 0);
}

function sessBusy(id) {
  const rec = S.sess[id];
  const H = S.hist[id];
  const A = S.art[id];
  const u = S.ui[id];
  const o = S.open[id];
  return !!((rec && rec.phase === 'loading') || (A && A.busy) || (H && (H.busy || Object.values(H.cutBusy).some(Boolean)))
    || (u && (u.sending || Object.values(u.busy).some(Boolean))) || (o && o.phase === 'busy'));
}

function dropSession(id) {
  delete S.sess[id];
  delete S.hist[id];
  delete S.art[id];
  delete S.sessAt[id];
  delete S.sessSig[id];
  delete S.seen['s:' + id];
}

// Evicts the least recently shown until both limits hold. Called when a screen is entered, when a read lands, and when the page is put away.
function trimCaches() {
  if (S.view !== 'app') return;
  const r = route();
  const openSession = r.id || '';
  const openFile = r.name === 'file' ? r.v : '';
  if (openSession) S.seen['s:' + openSession] = ++S.clock;
  if (openFile) S.seen['f:' + openFile] = ++S.clock;

  const others = [];
  let chars = 0;
  for (const id of new Set([...Object.keys(S.sess), ...Object.keys(S.hist), ...Object.keys(S.art)])) {
    if (id === openSession) continue;
    const n = sessChars(id);
    others.push({ id, n, at: S.seen['s:' + id] || 0 });
    chars += n;
  }
  let count = others.length;
  for (const o of others.sort((a, b) => a.at - b.at)) {
    if (count <= KEEP.sessions && chars <= KEEP.sessionChars) break;
    if (sessBusy(o.id)) continue;
    dropSession(o.id);
    count--;
    chars -= o.n;
  }

  const texts = [];
  chars = 0;
  for (const v of Object.keys(S.ftext)) {
    if (v === openFile) continue;
    const entry = S.ftext[v];
    const n = entry.data ? weigh(entry.data, jsonChars) : 0;
    texts.push({ v, n, at: S.seen['f:' + v] || 0, busy: entry.phase === 'loading' });
    chars += n;
  }
  count = texts.length;
  for (const t of texts.sort((a, b) => a.at - b.at)) {
    if (count <= KEEP.texts && chars <= KEEP.textChars) break;
    if (t.busy) continue;
    delete S.ftext[t.v];
    delete S.seen['f:' + t.v];
    count--;
    chars -= t.n;
  }
}

/* ---------- Settings ---------- */

function settingsContent() {
  const me = S.me;
  const version = (me && me.bench) || (S.state && S.state.bench) || '';
  const msg = h('p', { id: 'unpair-msg', class: 'msg bad', role: 'alert', hidden: true });
  return [
    h('h1', { class: 'large', tabindex: '-1', text: 'Settings' }),
    h('dl', { class: 'group sec' }, h('div', { class: 'kv' }, h('dt', { text: 'This device' }), h('dd', { text: (me && me.device) || '…' }))),
    notifSection(),
    h('div', { class: 'act' },
      h('button', {
        class: 'btn',
        type: 'button',
        text: 'Unpair this device',
        onclick: () => confirmSheet({
          title: 'Unpair this device?',
          message: 'It will stop showing your sessions. You’ll need a new code from your Mac to pair it again.',
          confirm: 'Unpair',
          run: unpair,
        }),
      }),
      msg),
    h('p', { class: 'foot', text: 'Only people on your Tailscale network can reach this page, and only a paired device can see your sessions.' }),
    h('p', { class: 'foot', text: 'Capsid' + (version ? ' ' + version : '') + '. A Solanum product. Unofficial, and not affiliated with Anthropic.' }),
  ];
}

/* ---------- Notifications (Web Push, opt in per device) ---------- */

const canPush = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
const DEFAULT_PREFS = { needsYou: true, errors: true, finishes: false, names: false, onlyAway: true, badge: true };
const BADGE_LABEL = ['badge', 'Show a count on the Capsid icon'];
const PREF_LABELS = [
  ['needsYou', 'When a session needs you'],
  ['errors', 'When a session stops with an error'],
  ['finishes', 'When a session finishes'],
  ['names', 'Show session names'],
  ['onlyAway', 'Only when I’m away from my Mac'],
  BADGE_LABEL,
];

/* ---------- The count on the Home Screen icon ---------- */

// Sessions that need you plus sessions that stopped with an error, as on Mail's icon. iOS shows it only for a
// Home Screen app that has notification permission, so the app asks for nothing more. The choice is kept in
// localStorage (per device, there before Settings has loaded) and in this device's push prefs on the Mac,
// because the service worker can't read localStorage and sets the count when a push arrives.
const BADGE_KEY = 'bench-badge';
const storedBadge = () => { try { return localStorage.getItem(BADGE_KEY) !== 'off'; } catch { return true; } };
const storeBadge = (on) => { try { localStorage.setItem(BADGE_KEY, on ? 'on' : 'off'); } catch { /* this run only */ } };
const currentPrefs = () => S.push.prefs || { ...DEFAULT_PREFS, badge: storedBadge() };
const badgeOn = () => currentPrefs().badge !== false;

// Called whenever the state arrives or the choice changes. Off, or no state (signed out), clears it.
function applyBadge() {
  if (!('setAppBadge' in navigator) || !standalone()) return;
  const st = S.state;
  const n = badgeOn() && st ? (st.needsYou || []).length + (st.failed || []).length : 0;
  try {
    const done = n > 0 ? navigator.setAppBadge(n) : navigator.clearAppBadge();
    if (done && done.catch) done.catch(() => { /* not allowed: no count */ });
  } catch { /* not allowed: no count */ }
}

const swReady = () => Promise.race([navigator.serviceWorker.ready, new Promise((r) => setTimeout(r, 3000))]);
const keyBytes = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(s.length / 4) * 4, '=')), (c) => c.charCodeAt(0));
const redrawSettings = () => { if (S.view === 'app' && route().name === 'settings') render(); };

async function loadPush() {
  const p = S.push;
  try {
    const info = await api('/api/push');
    p.key = info.publicKey || '';
    p.prefs = { ...DEFAULT_PREFS, ...(info.prefs || {}) };
    storeBadge(p.prefs.badge !== false);
    applyBadge();
    let have = false;
    if (canPush() && Notification.permission === 'granted') {
      try { const reg = await swReady(); have = !!(reg && (await reg.pushManager.getSubscription())); } catch { /* none */ }
    }
    p.on = !!info.subscribed && have;
    p.unavailable = false;
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    if (e.status === 404 || e.status === 403) p.unavailable = true; // an older version on the Mac
  }
  p.loaded = true;
  redrawSettings();
}

// Called straight from the tap: iOS only shows its permission prompt for a user gesture.
async function pushOn() {
  const p = S.push;
  if (p.busy) return;
  const asked = Notification.requestPermission();
  p.busy = true;
  p.msg = '';
  redrawSettings();
  try {
    if ((await asked) !== 'granted') {
      p.msg = Notification.permission === 'denied' ? '' : 'Notifications weren’t turned on.';
      return;
    }
    if (!p.key) await loadPush();
    if (!p.key) throw new Error('no key');
    const reg = await swReady();
    if (!reg) throw new Error('no worker');
    const options = { userVisibleOnly: true, applicationServerKey: keyBytes(p.key) };
    let sub;
    try {
      sub = await reg.pushManager.subscribe(options);
    } catch (e) {
      if (e.name !== 'InvalidStateError') throw e;
      const old = await reg.pushManager.getSubscription(); // made with another key: start over
      if (old) await old.unsubscribe();
      sub = await reg.pushManager.subscribe(options);
    }
    const j = sub.toJSON();
    const out = await send('/api/push/subscribe', { endpoint: j.endpoint, keys: { p256dh: j.keys.p256dh, auth: j.keys.auth }, prefs: currentPrefs() });
    if (out.status >= 300) throw new Error('refused');
    p.on = true;
    p.msg = 'Notifications are on.';
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    p.msg = e instanceof Down ? 'Couldn’t reach your Mac. Try again.' : 'Couldn’t turn on notifications. Try again.';
  } finally {
    p.busy = false;
    redrawSettings();
  }
}

async function pushOff() {
  const p = S.push;
  if (p.busy) return;
  p.busy = true;
  p.msg = '';
  redrawSettings();
  try {
    try {
      const reg = await swReady();
      const sub = reg && (await reg.pushManager.getSubscription());
      if (sub) await sub.unsubscribe();
    } catch { /* the Mac side still goes */ }
    const out = await send('/api/push/unsubscribe', {});
    if (out.status >= 300) throw new Error('refused');
    p.on = false;
    p.msg = 'Notifications are off.';
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    p.msg = 'Couldn’t turn them off. Try again.';
  } finally {
    p.busy = false;
    redrawSettings();
  }
}

async function pushTest() {
  const p = S.push;
  if (p.busy) return;
  p.busy = true;
  p.msg = '';
  redrawSettings();
  try {
    const out = await send('/api/push/test', {});
    p.msg = out.status < 300 ? 'Test sent. It should arrive in a moment.' : out.status === 429 ? 'That’s a few tests just now. Wait a minute, then try again.' : 'Couldn’t send a test.';
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    p.msg = 'Couldn’t reach your Mac. Try again.';
  } finally {
    p.busy = false;
    redrawSettings();
  }
}

async function setPref(key) {
  const p = S.push;
  const before = currentPrefs();
  const prefs = { ...before, [key]: !before[key] };
  p.prefs = prefs;
  p.msg = '';
  if (key === 'badge') { storeBadge(prefs.badge); applyBadge(); }
  redrawSettings();
  try {
    const out = await send('/api/push/prefs', prefs);
    if (out.status >= 300) throw Object.assign(new Error('refused'), { status: out.status });
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    p.prefs = before;
    if (key === 'badge') { storeBadge(before.badge); applyBadge(); }
    p.msg = isSlow(e) ? 'Couldn’t save that just now. Try again in a moment.' : 'Couldn’t save that. Try again.';
    redrawSettings();
  }
}

function prefRow([k, label]) {
  return h('li', null, h('button', {
    class: 'row sw', type: 'button', role: 'switch', 'aria-checked': currentPrefs()[k] ? 'true' : 'false', 'data-key': 'sw:' + k, onclick: () => setPref(k),
  }, h('span', { class: 'row-main' }, h('span', { class: 'title', text: label })), h('span', { class: 'switch', 'aria-hidden': 'true' })));
}

function notifSection() {
  const p = S.push;
  const note = (t) => h('p', { class: 'n-note', text: t });
  let body;
  if (!standalone()) {
    body = [h('div', { class: 'card pad' }, note('Open Capsid from your Home Screen to turn on notifications.'))];
  } else if (!canPush()) {
    body = [h('div', { class: 'card pad' }, note('This browser can’t receive notifications.'))];
  } else if (p.unavailable) {
    body = [h('div', { class: 'card pad' }, note('This version of Capsid can’t send notifications.'))];
  } else if (Notification.permission === 'denied') {
    body = [h('div', { class: 'card pad' }, note('Notifications are blocked for Capsid. To allow them, open the Settings app on your iPhone, choose Notifications, then Capsid, and turn on Allow Notifications. Then come back here.'))];
  } else if (!p.on) {
    body = [
      h('div', { class: 'card pad' }, note('Get a notification when a session needs you, even when Capsid isn’t open. They are encrypted, so only this device can read them.')),
      h('div', { class: 'act tight' }, h('button', {
        class: 'btn primary', type: 'button', text: p.busy ? 'Turning on…' : 'Turn On Notifications', disabled: p.busy, 'data-key': 'push-on', onclick: () => pushOn(),
      })),
      // Notifications off but allowed: the icon's count still works, so it can still be turned off.
      Notification.permission === 'granted' ? h('ul', { class: 'group' }, prefRow(BADGE_LABEL)) : null,
    ];
  } else {
    body = [
      h('ul', { class: 'group' }, PREF_LABELS.map((entry) => prefRow(entry))),
      h('div', { class: 'act tight pair-btns' },
        h('button', { class: 'btn', type: 'button', text: 'Send a Test', disabled: p.busy, 'data-key': 'push-test', onclick: () => pushTest() }),
        h('button', { class: 'btn', type: 'button', text: 'Turn Off', disabled: p.busy, 'data-key': 'push-off', onclick: () => pushOff() })),
    ];
  }
  if (p.msg) body.push(h('p', { class: 'msg', role: 'status', text: p.msg }));
  return section('Notifications', 0, body);
}

async function unpair() {
  const msg = $('unpair-msg');
  try {
    await api('/api/unpair', 'POST', {});
  } catch (e) {
    if (!(e instanceof Unauth)) {
      if (msg) { msg.textContent = e instanceof Down ? 'Couldn’t reach your Mac. Try again.' : 'Couldn’t unpair (error ' + (e.status || '?') + ').'; msg.hidden = false; }
      return;
    }
  }
  try {
    const reg = await Promise.race([navigator.serviceWorker.ready, new Promise((r) => setTimeout(r, 1500))]);
    const sub = reg && (await reg.pushManager.getSubscription());
    if (sub) await sub.unsubscribe();
  } catch { /* nothing to drop */ }
  history.replaceState(null, '', location.pathname);
  S.rk = 'now';
  showPair();
}

function confirmSheet({ title, message, confirm, run }) {
  const before = document.activeElement;
  const cancel = h('button', { class: 'btn', type: 'button', text: 'Cancel', onclick: close });
  const scrim = h('div', { class: 'scrim', onclick: (e) => { if (e.target === scrim) close(); } },
    h('div', { class: 'sheet', role: 'alertdialog', 'aria-modal': 'true', 'aria-labelledby': 'sheet-t', 'aria-describedby': 'sheet-d' },
      h('div', { class: 'box' },
        h('h2', { id: 'sheet-t', text: title }),
        h('p', { id: 'sheet-d', text: message }),
        h('button', { class: 'btn primary', type: 'button', text: confirm, onclick: () => { close(); run(); } })),
      cancel));
  function key(e) { if (e.key === 'Escape') close(); }
  function close() {
    document.removeEventListener('keydown', key);
    root.inert = false;
    scrim.remove();
    if (before && before.isConnected) before.focus({ preventScroll: true });
  }
  document.addEventListener('keydown', key);
  document.body.append(scrim);
  root.inert = true;
  cancel.focus();
}

/* ---------- Pairing ---------- */

const standalone = () => navigator.standalone === true || matchMedia('(display-mode: standalone)').matches;

function pairView() {
  const code = h('input', {
    id: 'code', class: 'code', type: 'text', inputmode: 'numeric', pattern: '[0-9]*', 'aria-label': '6-digit code',
    autocomplete: 'one-time-code', autocapitalize: 'off', autocorrect: 'off', spellcheck: 'false', placeholder: '••••••',
  });
  const name = h('input', { id: 'dname', type: 'text', value: 'iPhone', maxlength: '40', autocomplete: 'off', autocapitalize: 'words', enterkeyhint: 'go' });
  const go = h('button', { class: 'btn primary', type: 'submit', text: 'Pair this device', disabled: true });
  const err = h('p', { class: 'msg bad', role: 'alert', hidden: !S.pairMsg, text: S.pairMsg || null });
  const say = (t) => { err.textContent = t; err.hidden = !t; };

  code.addEventListener('input', () => {
    code.value = code.value.replace(/\D/g, '').slice(0, 6);
    go.disabled = code.value.length !== 6;
  });

  async function submit(e) {
    e.preventDefault();
    if (code.value.length !== 6) return;
    go.disabled = true;
    go.textContent = 'Pairing…';
    say('');
    let res = null;
    try {
      res = await fetch('/pair', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Bench': '1' },
        body: JSON.stringify({ code: code.value, name: name.value.trim() || 'iPhone' }),
      });
    } catch { /* offline: handled below */ }
    if (res && res.ok) {
      go.textContent = 'Paired';
      try {
        S.me = await api('/api/me');
      } catch (e2) {
        go.textContent = 'Pair this device';
        go.disabled = code.value.length !== 6;
        if (e2 instanceof Unauth) say('Paired, but this page didn’t keep the sign-in. Open Capsid from your Home Screen and try again.');
        else fail(e2, true);
        return;
      }
      S.view = 'boot';
      await refresh(true);
      return;
    }
    go.textContent = 'Pair this device';
    go.disabled = code.value.length !== 6;
    if (!res || res.status >= 500) say('Couldn’t reach Capsid on your Mac. Check that it’s running, then try again.');
    else if (res.status === 429) say('Too many tries. Make a new code in Capsid → Settings → Phone, then try again.');
    else say('That code didn’t work. Check the code on your Mac. It lasts 10 minutes.');
    code.select();
  }

  const inHome = standalone();
  return h('main', { class: 'wrap pair' },
    h('div', { class: 'hero' },
      h('img', { class: 'tile', src: '/icon-180.png', width: '64', height: '64', alt: '' }),
      h('h1', { tabindex: '-1', text: 'Pair this phone' }),
      h('p', { class: 'lede', text: 'See what needs you in Claude Science, then answer, approve and send messages from here. It all stays on your own Tailscale network.' })),
    h('form', { onsubmit: submit, novalidate: true },
      h('ol', { class: 'group steps' },
        h('li', null,
          h('b', { text: inHome ? 'You’re on the Home Screen ✓' : 'Open this from your Home Screen' }),
          inHome ? null : h('span', { class: 'warn', text: 'You’re in Safari. Tap Share → Add to Home Screen first, then open Capsid from your Home Screen.' })),
        h('li', null,
          h('label', { for: 'code', text: 'Enter the 6-digit code' }),
          h('span', { text: 'It’s in Capsid → Settings → Phone on your Mac.' }),
          code),
        h('li', null,
          h('label', { for: 'dname', text: 'Name this device' }),
          h('span', { text: 'So you can recognize it on your Mac.' }),
          name)),
      go, err));
}

/* ---------- Offline ---------- */

function offlineView() {
  const d = S.down;
  return h('main', { class: 'wrap center' },
    icon('moon', 'big'),
    h('h1', { tabindex: '-1', text: d.err ? 'Something went wrong' : 'Capsid isn’t running on your Mac, or your Mac is asleep' }),
    h('p', { text: d.err ? 'Capsid answered with an error (' + d.status + '). Try again in a moment.' : 'Wake your Mac or open Capsid, then try again. This page keeps trying on its own.' }),
    h('button', {
      class: 'btn primary',
      type: 'button',
      text: 'Retry',
      onclick: async (e) => {
        const b = e.currentTarget;
        b.disabled = true;
        b.textContent = 'Trying…';
        await refresh(true);
        if (b.isConnected) { b.disabled = false; b.textContent = 'Retry'; }
      },
    }));
}

/* ---------- pull to refresh ---------- */

const pullEl = $('pull');
let pullFrom = -1;
let pullStage = 0;

function setPull(stage) {
  if (stage === pullStage) return;
  pullStage = stage;
  pullEl.hidden = !stage;
  pullEl.textContent = stage === 2 ? 'Release to refresh' : stage === 1 ? 'Pull to refresh' : '';
}

document.addEventListener('touchstart', (e) => {
  const ok = S.view === 'app' && !S.split && window.scrollY <= 0 && e.touches.length === 1 && !document.querySelector('.scrim');
  pullFrom = ok ? e.touches[0].clientY : -1;
}, { passive: true });
document.addEventListener('touchmove', (e) => {
  if (pullFrom < 0) return;
  if (window.scrollY > 0) { pullFrom = -1; setPull(0); return; }
  const dy = e.touches[0].clientY - pullFrom;
  setPull(dy > 90 ? 2 : dy > 24 ? 1 : 0);
}, { passive: true });
document.addEventListener('touchend', async () => {
  const go = pullStage === 2;
  pullFrom = -1;
  if (go) {
    pullEl.textContent = 'Refreshing…';
    await refreshAll(true);
  }
  setPull(0);
}, { passive: true });
document.addEventListener('touchcancel', () => { pullFrom = -1; setPull(0); }, { passive: true });

/* ---------- go ---------- */

document.addEventListener('visibilitychange', () => (document.hidden ? onHidden() : onVisible()));
addEventListener('pageshow', (e) => { if (e.persisted) onVisible(); });
addEventListener('online', onVisible);
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => { /* notifications just stay off */ });
  navigator.serviceWorker.addEventListener('message', (e) => {
    const u = e.data && e.data.type === 'open' ? e.data.url : '';
    if (typeof u === 'string' && /^\/#\/(session\/[0-9a-f-]{36})?$/.test(u)) location.hash = u.slice(1);
  });
}
// With the keyboard up the home-indicator padding under the composer is not needed.
if (window.visualViewport) {
  visualViewport.addEventListener('resize', () => document.documentElement.classList.toggle('kb', innerHeight - visualViewport.height > 140));
}
splitQuery.addEventListener('change', (e) => {
  S.split = e.matches;
  syncScopes();
  if (S.view === 'app') render(true);
});
S.rk = routeKey();
startTicker();
start();
