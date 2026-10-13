// Bench on your phone. Plain JS, no dependencies, same-origin only.
// Every piece of user text goes in through textContent (h() below), never innerHTML.

const $ = (id) => document.getElementById(id);
const root = $('root');

const S = {
  view: 'boot',        // boot | pair | offline | app
  down: { status: 0, err: false },
  pairMsg: '',
  state: null,         // the last /api/state snapshot
  sig: '',             // snapshot signature without updatedAt, to skip no-op renders
  me: null,
  sess: {},            // id -> { phase: loading|ok|missing|error, data }
  open: {},            // id -> { phase: busy|done|error, down, status }
  lastOk: 0,           // when we last heard from Bench (stream or poll)
  lastTry: 0,
  refreshing: null,
  es: null,
  esTimer: 0,
  backoff: 0,
  tickTimer: 0,
  n: 0,
  scroll: {},
  rk: '',
  navs: 0,
  split: false,        // the iPad layout: the Now list beside the selected session
  ui: {},              // id -> what the person typed or chose on that session
  sessAt: {},          // id -> when we last fetched it
  sessSig: {},         // id -> what the state said about it at that fetch
  sessTimer: 0,
  push: { loaded: false, unavailable: false, key: '', on: false, prefs: null, busy: false, msg: '' },
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

const PATHS = {
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
  refresh: '<polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>',
  left: '<polyline points="15 18 9 12 15 6"/>',
  chev: '<polyline points="9 18 15 12 9 6"/>',
  alert: '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>',
  moon: '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>',
  up: '<line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/>',
  check: '<polyline points="20 6 9 17 4 12"/>',
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

async function api(path, method = 'GET', body) {
  const post = method === 'POST';
  let res;
  try {
    res = await fetch(path, {
      method,
      cache: 'no-store',
      headers: post ? { 'Content-Type': 'application/json', 'X-Bench': '1' } : { Accept: 'application/json' },
      body: post ? JSON.stringify(body ?? {}) : undefined,
    });
  } catch {
    throw new Down();
  }
  if (res.status === 401) throw new Unauth();
  if (res.status === 502 || res.status === 503 || res.status === 504) throw new Down(res.status);
  if (!res.ok) {
    const e = new Error('http ' + res.status);
    e.status = res.status;
    throw e;
  }
  try { return await res.json(); } catch { return null; }
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
  if (e instanceof Down) return fg || !S.state ? showOffline(e.status, false) : undefined;
  if (fg || !S.state) showOffline(e.status || -1, true);
}

function showPair(msg = '') {
  if (S.view === 'pair') return;
  S.view = 'pair';
  S.pairMsg = msg;
  S.state = null;
  S.sig = '';
  S.sess = {};
  S.ui = {};
  S.push = { loaded: false, unavailable: false, key: '', on: false, prefs: null, busy: false, msg: '' };
  S.me = null;
  disconnect();
  pill();
  render(true);
}

function showOffline(status, err) {
  if (S.view === 'offline' && S.down.err === err) return;
  S.view = 'offline';
  S.down = { status, err };
  disconnect();
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
  return Promise.all([refresh(fg), r.name === 'session' ? loadSession(r.id) : null]);
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

async function loadSession(id) {
  const had = S.sess[id];
  S.sessAt[id] = Date.now();
  S.sessSig[id] = JSON.stringify(lookup(id));
  if (!had) S.sess[id] = { phase: 'loading', data: null };
  try {
    const data = await api('/api/sessions/' + encodeURIComponent(id));
    if (had && had.phase === 'ok' && JSON.stringify(had.data) === JSON.stringify(data)) return;
    S.sess[id] = { phase: 'ok', data };
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    if (e.status === 404) S.sess[id] = had && had.data ? { ...had, gone: true } : { phase: 'missing', data: null };
    else if (!had || !had.data) S.sess[id] = { phase: 'error', data: null, down: e instanceof Down };
  }
  const r = route();
  if (S.view === 'app' && r.name === 'session' && r.id === id) render();
}

function gotState(st) {
  if (S.view === 'pair') return; // a late reply from before we were signed out
  S.lastOk = Date.now();
  const wasApp = S.view === 'app';
  const sig = JSON.stringify(st, (k, v) => (k === 'updatedAt' ? undefined : v));
  S.state = st;
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
  if (r.name === 'settings' && !S.split) return;
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
  if (S.view === 'app') {
    // Keepalive comments never reach page code, so poll when the stream is quiet.
    if (now - S.lastOk > 30000 && !S.refreshing && now - S.lastTry > 25000) refresh(false);
    pill();
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
      const r = route();
      if (r.name === 'session') loadSession(r.id);
    }
  }
}
function onHidden() {
  stopTicker();
  disconnect();
}

/* ---------- routing ---------- */

function route() {
  const hash = location.hash.slice(1) || '/';
  const m = hash.match(/^\/session\/([0-9a-f-]{36})$/);
  if (m) return { name: 'session', id: m[1] };
  if (hash === '/settings') return { name: 'settings' };
  return { name: 'now' };
}
const routeKey = () => { const r = route(); return r.name + (r.id || ''); };

function enterRoute() {
  const r = route();
  if (r.name === 'session') loadSession(r.id);
  else if (r.name === 'settings') { loadMe(); loadPush(); }
  else if (!S.me) loadMe();
}

addEventListener('hashchange', () => {
  if (!S.split) S.scroll[S.rk] = window.scrollY;
  S.navs++;
  S.rk = routeKey();
  if (S.view === 'app') enterRoute();
  render(true);
  if (!S.split) window.scrollTo(0, S.rk === 'now' ? S.scroll.now || 0 : 0);
});

/* ---------- rendering ---------- */

function render(fresh = false) {
  const r = route();
  if (!fresh && S.view === 'app' && patchSession(r)) return;
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
  root.replaceChildren(...(tree ? [tree] : []));
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
}

// The session screen is already up: refresh the list beside it and the regions that changed.
function patchSession(r) {
  if (r.name !== 'session') return false;
  const sv = root.querySelector('.sessview');
  if (!sv || sv.dataset.sess !== r.id || !!root.querySelector('.split') !== S.split) return false;
  if (S.split) {
    const side = root.querySelector('.side-pane');
    const top = side.scrollTop;
    const active = document.activeElement;
    const key = active && side.contains(active) ? active.dataset.key : '';
    side.querySelector('.pane-in').replaceChildren(...nowContent().filter(Boolean));
    side.scrollTop = top;
    if (key) { const again = side.querySelector(`[data-key="${CSS.escape(key)}"]`); if (again) again.focus({ preventScroll: true }); }
    watchTitle();
  } else {
    const t = root.querySelector('.bar-t');
    if (t) t.textContent = sessionTitle(r.id);
  }
  fillSession(sv, r.id);
  return true;
}

function singleView(r) {
  if (r.name === 'session') return sessionView(r.id, false);
  if (r.name === 'settings') return h('div', null, bar('Settings', backLink('Now'), null), h('main', { class: 'wrap' }, settingsContent()));
  return h('div', null, bar('Now', null, [refreshButton(), settingsLink()]), h('main', { class: 'wrap' }, nowContent()));
}

function splitView(r) {
  const detail = r.name === 'session'
    ? sessionView(r.id, true)
    : h('div', { class: 'detail-col' }, h('div', { class: 'detail-body' },
      h('div', { class: 'detail-in' + (r.name === 'now' ? ' nothing' : '') }, r.name === 'settings' ? settingsContent() : emptyDetail())));
  return h('div', { class: 'split' },
    h('nav', { class: 'pane side-pane', 'aria-label': 'Sessions' },
      bar('Now', null, [refreshButton(), settingsLink()]),
      h('div', { class: 'pane-in' }, nowContent())),
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

function backLink(label) {
  return h('a', {
    class: 'back',
    href: '#/',
    'aria-label': 'Back to ' + label,
    onclick: (e) => {
      if (S.navs > 0) { e.preventDefault(); history.back(); }
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

function workingRow(w) {
  return h('li', null,
    h('a', { class: 'row', href: sessionHref(w.id), 'data-key': 'w:' + w.id, 'aria-current': current(w.id) },
      h('span', { class: 'dot live', 'aria-hidden': 'true' }),
      h('span', { class: 'row-main' },
        h('span', { class: 'title', text: w.title }),
        subLine(w.project, null)),
      h('span', { class: 'side' }, clockEl(w.startedAt)),
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

function nowContent() {
  const st = S.state;
  const needs = st.needsYou || [];
  const failed = st.failed || [];
  const working = st.working || [];
  const recent = st.recent || [];
  return [
    h('h1', { class: 'large', tabindex: '-1', text: 'Now' }),
    st.problem ? h('div', { class: 'banner', role: 'status' }, icon('alert'), h('span', { text: st.problem })) : null,
    section('Needs you', needs.length, needs.length ? list(needs.map(needsRow)) : emptyCard('Nothing needs you')),
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

function inline(s, depth = 0) {
  const out = [];
  const re = /`([^`\n]+)`|\*\*([^*\n]+?)\*\*|\*([^*\s][^*\n]*?)\*|\[([^\]\n]*)\]\(([^)\s]*)\)/g;
  let last = 0;
  let m;
  while ((m = re.exec(s))) {
    if (m.index > last) out.push(txt(s.slice(last, m.index)));
    if (m[1] != null) out.push(h('code', { text: m[1] }));
    else if (m[2] != null) out.push(h('strong', null, depth < 3 ? inline(m[2], depth + 1) : txt(m[2])));
    else if (m[3] != null) out.push(h('em', null, depth < 3 ? inline(m[3], depth + 1) : txt(m[3])));
    else out.push(txt(m[5] && m[5] !== m[4] ? `${m[4]} (${m[5]})` : m[4] || m[5])); // a link is just its words
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

function md(src) {
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

/* ---------- Session: built from regions, so a refresh never disturbs what you are typing ---------- */

const STATE_LABELS = {
  needsInput: 'Needs you',
  working: 'Working',
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
  return 'Bench couldn’t open it (error ' + (o.status || '?') + ').';
}

function paintOpen(id) {
  const b = $('open-btn');
  const m = $('open-msg');
  if (!b || b.dataset.id !== id) return;
  const o = S.open[id];
  b.textContent = openLabel(id);
  b.disabled = !!o && o.phase === 'busy';
  b.className = 'btn ' + (o && o.phase === 'done' ? 'ok' : 'primary');
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

function openBlock(id) {
  const block = h('div', { class: 'act', 'aria-live': 'polite' },
    h('button', { id: 'open-btn', class: 'btn primary', type: 'button', 'data-key': 'open', 'data-id': id, onclick: () => openOnMac(id) }),
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
function statusMark(state) {
  if (state === 'needsInput') return h('span', { class: 'dot', 'aria-hidden': 'true' });
  if (state === 'error' || state === 'failed') return icon('alert', 'sm mark-err');
  if (state === 'working') return h('span', { class: 'dot live', 'aria-hidden': 'true' });
  return h('span', { class: 'dot idle', 'aria-hidden': 'true' });
}

// What the person has typed or chosen on a session, kept across every redraw.
const ui = (id) => (S.ui[id] ||= { draft: '', msg: null, picks: {}, other: {}, otherOn: {}, qTool: '', busy: {}, note: null, noteT: 0, shown: 4, more: {} });

const REGIONS = ['head', 'open', 'unread', 'question', 'plan', 'reply', 'toyou', 'convo', 'times'];

function sessionView(id, inPane) {
  const body = h('div', { class: (inPane ? 'detail-in' : 'wrap') + ' sess-body' }, REGIONS.map((n) => h('div', { 'data-r': n })));
  const sv = inPane
    ? h('div', { class: 'detail-col sessview', 'data-sess': id }, h('div', { class: 'detail-body' }, body))
    : h('div', { class: 'sessview single', 'data-sess': id }, bar(sessionTitle(id), backLink('Now'), refreshButton()), h('main', null, body));
  fillSession(sv, id);
  return sv;
}

// Replace a region's children only when what it shows changed; keep focus and caret.
function setRegion(body, name, sig, build) {
  const el = body.querySelector(`:scope > [data-r="${name}"]`);
  if (!el || el.dataset.sig === sig) return;
  const active = document.activeElement;
  const key = active && el.contains(active) ? active.dataset.key : '';
  const caret = key && active.selectionStart != null ? [active.selectionStart, active.selectionEnd] : null;
  el.dataset.sig = sig;
  el.replaceChildren(...build().filter(Boolean));
  if (key) {
    const again = el.querySelector(`[data-key="${CSS.escape(key)}"]`);
    if (again) {
      again.focus({ preventScroll: true });
      if (caret && again.setSelectionRange) try { again.setSelectionRange(caret[0], caret[1]); } catch { /* not a text field */ }
    }
  }
}

function fillSession(sv, id) {
  const body = sv.querySelector('.sess-body');
  const rec = S.sess[id];
  const d = rec && rec.data;
  const snap = lookup(id);
  const u = ui(id);
  const q = d && d.question;
  if (q && u.qTool !== q.toolId) Object.assign(u, { qTool: q.toolId, picks: {}, other: {}, otherOn: {} });
  const set = (name, sig, build) => setRegion(body, name, JSON.stringify(sig) ?? '', build);
  const none = () => [];

  set('head', [sessionTitle(id), rec && rec.phase, rec && rec.down, rec && rec.gone, d && [d.project, d.state, d.sentence, d.statusLine], snap && [snap.project, snap.snooze]], () => headNodes(id, rec, d, snap));
  set('open', rec && rec.phase === 'missing' ? 0 : 1, () => (rec && rec.phase === 'missing' ? [] : [openBlock(id)]));
  set('unread', d && d.version >= 2 && d.readable === false, () => (d && d.version >= 2 && d.readable === false
    ? [h('p', { class: 'quiet', text: 'Bench can’t show this session’s messages. Open it on your Mac.' })] : []));
  set('question', d && q ? [q, u.picks, u.otherOn, u.busy.question] : 0, () => (d && q ? [questionCard(id, q, u)] : []));
  set('plan', d && d.plan ? [d.plan, d.can && d.can.approve, u.busy.plan] : 0, () => (d && d.plan ? [planCard(id, d, u)] : []));
  set('reply', d && d.reply ? d.reply : 0, () => (d && d.reply && d.reply.text
    ? [section('Latest reply', 0, h('div', { class: 'card reply' }, h('div', { class: 'md' }, md(d.reply.text)), d.reply.at ? h('p', { class: 'foot-t' }, rel(d.reply.at)) : null))] : []));
  set('toyou', d && d.toYou && d.toYou.length ? d.toYou : 0, () => (d && d.toYou && d.toYou.length
    ? [section('Messages to you', 0, h('ul', { class: 'group' }, d.toYou.map((m) => h('li', { class: 'turn' },
      h('div', { class: 'md' }, md(m.text)), m.at ? h('p', { class: 'foot-t' }, rel(m.at)) : null))))] : []));
  set('convo', d && d.turns && d.turns.length ? [d.turns, u.shown, u.more] : 0, () => (d && d.turns && d.turns.length ? [convo(id, d.turns, u)] : []));
  set('times', d ? [d.state, d.startedAt, d.updatedAt] : 0, () => (d ? [timesCard(d)] : []));

  let dock = sv.querySelector('.dock');
  if (d && d.can) {
    if (!dock) { dock = buildDock(id); sv.append(dock); }
    paintDock(id, dock);
  } else if (dock) dock.remove();
  requestAnimationFrame(() => measureClamps(sv));
}

function headNodes(id, rec, d, snap) {
  const heading = h('h1', { class: 'sess', tabindex: '-1', text: sessionTitle(id) });
  if (!d) {
    const note = !rec || rec.phase === 'loading' ? 'Loading…'
      : rec.phase === 'missing' ? 'This session isn’t available any more.'
      : rec.down ? 'Couldn’t reach your Mac.' : 'Couldn’t load this session.';
    const retry = rec && rec.phase === 'error'
      ? h('div', { class: 'act' }, h('button', { class: 'btn', type: 'button', text: 'Try again', onclick: () => { delete S.sess[id]; loadSession(id); render(); } }))
      : null;
    return [heading, snap ? h('p', { class: 'sub tight-sub', text: snap.project }) : null, h('p', { class: 'lede', text: note }), retry];
  }
  const snooze = snap && snap.snooze ? snoozeText(snap.snooze) : '';
  return [
    heading,
    d.project ? h('p', { class: 'sub tight-sub', text: d.project }) : null,
    h('p', { class: 'status' + (d.state === 'needsInput' || d.state === 'error' || d.state === 'failed' ? '' : ' calm') },
      statusMark(d.state), d.sentence || stateLabel(d.state)),
    d.statusLine ? h('p', { class: 'status-line', text: d.statusLine }) : null,
    snooze ? h('p', { class: 'snooze lone', text: snooze }) : null,
    rec.gone ? h('p', { class: 'snooze lone', text: 'This session is no longer on your list.' }) : null,
  ];
}

function timesCard(d) {
  const rows = [];
  const kv = (k, v) => h('div', { class: 'kv' }, h('dt', { text: k }), h('dd', null, v));
  if (d.state === 'working' && d.startedAt) rows.push(kv('Working for', clockEl(d.startedAt)));
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
    const b = el.nextElementSibling;
    if (b && b.dataset.more) b.hidden = el.scrollHeight <= el.clientHeight + 1;
  }
}

function redrawSession(id) {
  const sv = root.querySelector('.sessview');
  if (sv && sv.dataset.sess === id) fillSession(sv, id);
}

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

function buildDock(id) {
  const u = ui(id);
  const ta = h('textarea', {
    id: 'composer', class: 'composer-ta', rows: '1', maxlength: '4000', enterkeyhint: 'send', autocapitalize: 'sentences',
    'aria-label': 'Message to Claude', 'data-key': 'composer',
  });
  const grow = h('div', { class: 'grow' }, ta);
  ta.value = u.draft;
  ta.addEventListener('input', () => { u.draft = ta.value; paintDock(id); });
  ta.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); sendMessage(id); }
  });
  return h('div', { class: 'dock' }, h('div', { class: 'dock-in' },
    h('div', { class: 'dock-note', role: 'status', hidden: true }),
    h('div', { class: 'composer' }, grow, h('button', { class: 'send', type: 'button', 'aria-label': 'Send', onclick: () => sendMessage(id) }, icon('up'))),
    h('p', { class: 'dock-count', hidden: true })));
}

function paintDock(id, dock = root.querySelector('.dock')) {
  const d = S.sess[id] && S.sess[id].data;
  if (!dock || !d || !d.can) return;
  const u = ui(id);
  const can = d.can;
  const ta = dock.querySelector('textarea');
  const note = dock.querySelector('.dock-note');
  const count = dock.querySelector('.dock-count');
  const posting = !!u.busy.message;
  ta.disabled = !can.message;
  ta.readOnly = posting;
  ta.placeholder = can.message ? PLACEHOLDER[can.message] || 'Message Claude' : can.why || 'You can’t message this session right now';
  dock.querySelector('.send').disabled = !can.message || posting || !u.draft.trim();
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

function setNote(id, note, ms = 6000) {
  const u = ui(id);
  clearTimeout(u.noteT);
  u.note = note;
  paintDock(id);
  if (note) u.noteT = setTimeout(() => { u.note = null; paintDock(id); }, ms);
}

function describe(out) {
  const { status, data } = out;
  const result = data && typeof data.result === 'string' ? data.result : '';
  const sentence = data && typeof data.sentence === 'string' ? data.sentence : '';
  if (status === 429) return { ok: false, refetch: false, text: 'Too many actions just now. Try again in a minute.' };
  if (result === 'changed') return { ok: false, refetch: true, text: 'This changed on your Mac. Showing the latest.' };
  if (['approved', 'sent', 'queued', 'resumed'].includes(result) && status < 300) {
    return { ok: true, refetch: true, text: sentence || { approved: 'Approved', sent: 'Sent', queued: 'Queued', resumed: 'Picked up again' }[result] };
  }
  if (result === 'blocked') return { ok: false, refetch: true, text: sentence || 'That isn’t possible right now.' };
  if (status === 403 && !sentence) return { ok: false, refetch: true, text: 'Actions are off in Bench’s Settings.' };
  return { ok: false, refetch: true, open: true, text: sentence || 'Couldn’t do that from here. Open it on your Mac.' };
}

// One path for approve, answer and message: disable, post, say what happened, refetch.
async function doAction(id, kind, path, body) {
  const u = ui(id);
  if (u.busy[kind]) return null;
  u.busy[kind] = true;
  redrawSession(id);
  let result;
  try {
    result = describe(await send(path, body));
  } catch (e) {
    if (e instanceof Unauth) { u.busy[kind] = false; showPair(); return null; }
    result = { ok: false, refetch: false, text: 'Couldn’t reach your Mac. Try again.' };
  }
  u.busy[kind] = false;
  setNote(id, { text: result.text, open: !!result.open }, result.open ? 12000 : result.ok ? 5000 : 9000);
  if (result.refetch) await loadSession(id);
  redrawSession(id);
  return result;
}

async function sendMessage(id) {
  const u = ui(id);
  const text = u.draft.trim();
  const d = S.sess[id] && S.sess[id].data;
  if (!text || u.busy.message || !d || !d.can || !d.can.message) return;
  if (!u.msg || u.msg.text !== text) u.msg = { id: uuid(), text }; // a retry of the same words keeps its id
  const result = await doAction(id, 'message', '/api/sessions/' + id + '/message', { text, id: u.msg.id });
  if (result && result.ok) {
    u.draft = '';
    u.msg = null;
    const ta = root.querySelector('.composer-ta');
    if (ta) ta.value = '';
    paintDock(id);
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
    h('p', { class: 'foot', text: 'Bench' + (version ? ' ' + version : '') + '. A Solanum product. Unofficial, and not affiliated with Anthropic.' }),
  ];
}

/* ---------- Notifications (Web Push, opt in per device) ---------- */

const canPush = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
const DEFAULT_PREFS = { needsYou: true, errors: true, finishes: false, names: false, onlyAway: true };
const PREF_LABELS = [
  ['needsYou', 'When a session needs you'],
  ['errors', 'When a session stops with an error'],
  ['finishes', 'When a session finishes'],
  ['names', 'Show session names'],
  ['onlyAway', 'Only when I’m away from my Mac'],
];

const swReady = () => Promise.race([navigator.serviceWorker.ready, new Promise((r) => setTimeout(r, 3000))]);
const keyBytes = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(s.length / 4) * 4, '=')), (c) => c.charCodeAt(0));
const redrawSettings = () => { if (S.view === 'app' && route().name === 'settings') render(); };

async function loadPush() {
  const p = S.push;
  try {
    const info = await api('/api/push');
    p.key = info.publicKey || '';
    p.prefs = { ...DEFAULT_PREFS, ...(info.prefs || {}) };
    let have = false;
    if (canPush() && Notification.permission === 'granted') {
      try { const reg = await swReady(); have = !!(reg && (await reg.pushManager.getSubscription())); } catch { /* none */ }
    }
    p.on = !!info.subscribed && have;
    p.unavailable = false;
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    if (e.status === 404 || e.status === 403) p.unavailable = true; // an older Bench
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
    const out = await send('/api/push/subscribe', { endpoint: j.endpoint, keys: { p256dh: j.keys.p256dh, auth: j.keys.auth }, prefs: p.prefs || DEFAULT_PREFS });
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
    p.msg = out.status < 300 ? 'Test sent. It should arrive in a moment.' : 'Couldn’t send a test.';
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
  const before = p.prefs || DEFAULT_PREFS;
  const prefs = { ...before, [key]: !before[key] };
  p.prefs = prefs;
  p.msg = '';
  redrawSettings();
  try {
    const out = await send('/api/push/prefs', prefs);
    if (out.status >= 300) throw new Error('refused');
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    p.prefs = before;
    p.msg = 'Couldn’t save that. Try again.';
    redrawSettings();
  }
}

function notifSection() {
  const p = S.push;
  const note = (t) => h('p', { class: 'n-note', text: t });
  let body;
  if (!standalone()) {
    body = [h('div', { class: 'card pad' }, note('Open Bench from your Home Screen to turn on notifications.'))];
  } else if (!canPush()) {
    body = [h('div', { class: 'card pad' }, note('This browser can’t receive notifications.'))];
  } else if (p.unavailable) {
    body = [h('div', { class: 'card pad' }, note('This version of Bench can’t send notifications.'))];
  } else if (Notification.permission === 'denied') {
    body = [h('div', { class: 'card pad' }, note('Notifications are blocked for Bench. To allow them, open the Settings app on your iPhone, choose Notifications, then Bench, and turn on Allow Notifications. Then come back here.'))];
  } else if (!p.on) {
    body = [
      h('div', { class: 'card pad' }, note('Get a notification when a session needs you, even when Bench isn’t open. They are encrypted, so only this device can read them.')),
      h('div', { class: 'act tight' }, h('button', {
        class: 'btn primary', type: 'button', text: p.busy ? 'Turning on…' : 'Turn On Notifications', disabled: p.busy, 'data-key': 'push-on', onclick: () => pushOn(),
      })),
    ];
  } else {
    const prefs = p.prefs || DEFAULT_PREFS;
    body = [
      h('ul', { class: 'group' }, PREF_LABELS.map(([k, label]) => h('li', null, h('button', {
        class: 'row sw', type: 'button', role: 'switch', 'aria-checked': prefs[k] ? 'true' : 'false', 'data-key': 'sw:' + k, onclick: () => setPref(k),
      }, h('span', { class: 'row-main' }, h('span', { class: 'title', text: label })), h('span', { class: 'switch', 'aria-hidden': 'true' }))))),
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
        if (e2 instanceof Unauth) say('Paired, but this page didn’t keep the sign-in. Open Bench from your Home Screen and try again.');
        else fail(e2, true);
        return;
      }
      S.view = 'boot';
      await refresh(true);
      return;
    }
    go.textContent = 'Pair this device';
    go.disabled = code.value.length !== 6;
    if (!res || res.status >= 500) say('Couldn’t reach Bench on your Mac. Check that it’s running, then try again.');
    else if (res.status === 429) say('Too many tries. Make a new code in Bench → Settings → Phone, then try again.');
    else say('That code didn’t work. Check the code on your Mac. It lasts 10 minutes.');
    code.select();
  }

  const inHome = standalone();
  return h('main', { class: 'wrap pair' },
    h('div', { class: 'hero' },
      h('img', { class: 'tile', src: '/icon-180.png', width: '64', height: '64', alt: '' }),
      h('h1', { tabindex: '-1', text: 'Pair this phone' }),
      h('p', { class: 'lede', text: 'Bench shows what needs you in Claude Science and can open a session on your Mac. It all stays on your own Tailscale network.' })),
    h('form', { onsubmit: submit, novalidate: true },
      h('ol', { class: 'group steps' },
        h('li', null,
          h('b', { text: inHome ? 'You’re on the Home Screen ✓' : 'Open this from your Home Screen' }),
          inHome ? null : h('span', { class: 'warn', text: 'You’re in Safari. Tap Share → Add to Home Screen first, then open Bench from your Home Screen.' })),
        h('li', null,
          h('label', { for: 'code', text: 'Enter the 6-digit code' }),
          h('span', { text: 'It’s in Bench → Settings → Phone on your Mac.' }),
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
    h('h1', { tabindex: '-1', text: d.err ? 'Something went wrong' : 'Bench isn’t running on your Mac, or your Mac is asleep' }),
    h('p', { text: d.err ? 'Bench answered with an error (' + d.status + '). Try again in a moment.' : 'Wake your Mac or open Bench, then try again. This page keeps trying on its own.' }),
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
  if (S.view === 'app') render(true);
});
S.rk = routeKey();
startTicker();
start();
