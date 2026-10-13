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
};

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
  phone: '<rect x="5" y="2" width="14" height="20" rx="3"/><line x1="12" y1="18" x2="12.01" y2="18"/>',
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
  if (!had) S.sess[id] = { phase: 'loading', data: null };
  try {
    const data = await api('/api/sessions/' + encodeURIComponent(id));
    if (had && had.phase === 'ok' && JSON.stringify(had.data) === JSON.stringify(data)) return;
    S.sess[id] = { phase: 'ok', data };
  } catch (e) {
    if (e instanceof Unauth) return showPair();
    if (e.status === 404) S.sess[id] = { phase: 'missing', data: null };
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
  if (r.name === 'settings') return;
  render();
  if (r.name === 'session') loadSession(r.id);
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
    if (S.view === 'app') connect();
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
  else if (r.name === 'settings') loadMe();
  else if (!S.me) loadMe();
}

addEventListener('hashchange', () => {
  S.scroll[S.rk] = window.scrollY;
  S.navs++;
  S.rk = routeKey();
  if (S.view === 'app') enterRoute();
  render(true);
  window.scrollTo(0, S.rk === 'now' ? S.scroll.now || 0 : 0);
});

/* ---------- rendering ---------- */

function render(fresh = false) {
  const r = route();
  const active = document.activeElement;
  const keep = !fresh && active && active.dataset ? active.dataset.key : '';
  let tree = null;
  if (S.view === 'pair') tree = pairView();
  else if (S.view === 'offline') tree = offlineView();
  else if (S.view === 'app') tree = r.name === 'session' ? sessionView(r.id) : r.name === 'settings' ? settingsView() : nowView();
  root.replaceChildren(...(tree ? [tree] : []));
  watchTitle();
  if (keep) {
    const again = root.querySelector(`[data-key="${CSS.escape(keep)}"]`);
    if (again) again.focus({ preventScroll: true });
  } else if (fresh) {
    const t = root.querySelector('h1');
    if (t) t.focus({ preventScroll: true });
  }
}

let titleWatcher;
function watchTitle() {
  if (titleWatcher) titleWatcher.disconnect();
  const t = root.querySelector('h1.large');
  const bar = root.querySelector('.bar');
  if (!t || !bar || !('IntersectionObserver' in window)) return;
  titleWatcher = new IntersectionObserver(([e]) => bar.classList.toggle('scrolled', !e.isIntersecting), { rootMargin: '-56px 0px 0px 0px' });
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

const settingsLink = () => h('a', { class: 'icon-btn', href: '#/settings', 'aria-label': 'Settings' }, icon('gear'));

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

function needsRow(n) {
  const z = snoozeText(n.snooze);
  return h('li', null,
    h('a', { class: 'row', href: sessionHref(n.id), 'data-key': 'n:' + n.id },
      h('span', { class: 'row-main' },
        h('span', { class: 'reason', text: n.sentence || 'Needs you' }),
        h('span', { class: 'title', text: n.title }),
        subLine(n.project, rel(n.since)),
        z ? h('span', { class: 'snooze', text: z }) : null),
      icon('chev', 'sm chev')));
}

function failedRow(f) {
  return h('li', null,
    h('a', { class: 'row', href: sessionHref(f.id), 'data-key': 'f:' + f.id },
      h('span', { class: 'dot err', 'aria-hidden': 'true' }),
      h('span', { class: 'row-main' },
        h('span', { class: 'title', text: f.title }),
        subLine(f.project, rel(f.since))),
      icon('chev', 'sm chev')));
}

function workingRow(w) {
  return h('li', null,
    h('a', { class: 'row', href: sessionHref(w.id), 'data-key': 'w:' + w.id },
      h('span', { class: 'dot live', 'aria-hidden': 'true' }),
      h('span', { class: 'row-main' },
        h('span', { class: 'title', text: w.title }),
        subLine(w.project, null)),
      h('span', { class: 'side' }, clockEl(w.startedAt)),
      icon('chev', 'sm chev')));
}

function recentRow(r) {
  return h('li', null,
    h('a', { class: 'row', href: sessionHref(r.id), 'data-key': 'r:' + r.id + r.at },
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
        h('span', { class: 'u-pct', text: pct + '%' })),
      h('progress', { max: '100', value: String(pct), class: pct >= 90 ? 'hot' : null, 'aria-label': (l.name || 'Usage') + ' used' }),
      pace ? h('div', { class: 'u-pace', text: pace }) : null);
  })));
}

function nowView() {
  const st = S.state;
  const needs = st.needsYou || [];
  const failed = st.failed || [];
  const working = st.working || [];
  const recent = st.recent || [];
  const main = h('main', { class: 'wrap' },
    h('h1', { class: 'large', tabindex: '-1', text: 'Now' }),
    st.problem ? h('div', { class: 'banner', role: 'status' }, icon('alert'), h('span', { text: st.problem })) : null,
    section('Needs you', needs.length, needs.length ? list(needs.map(needsRow)) : emptyCard('Nothing needs you')),
    failed.length ? section('Stopped with an error', failed.length, list(failed.map(failedRow)), 'err') : null,
    section('Working', 0, working.length ? list(working.map(workingRow)) : emptyCard('Nothing working right now')),
    recent.length ? section('Recent', 0, list(recent.map(recentRow))) : null,
    usageSection(st.usage));
  return h('div', null, bar('Now', null, [refreshButton(), settingsLink()]), main);
}

/* ---------- Session ---------- */

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

function sessionView(id) {
  const rec = S.sess[id];
  const d = rec && rec.data;
  const snap = lookup(id);
  const title = (d && d.title) || (snap && snap.title) || 'Session';
  const head = bar(title, backLink('Now'), refreshButton());
  const heading = h('h1', { class: 'large tight' + (title.length > 26 ? ' long' : ''), tabindex: '-1', text: title });

  if (!d) {
    const note = !rec || rec.phase === 'loading' ? 'Loading…'
      : rec.phase === 'missing' ? 'This session isn’t available any more.'
      : rec.down ? 'Couldn’t reach your Mac.' : 'Couldn’t load this session.';
    const gone = rec && rec.phase === 'missing';
    const retry = rec && rec.phase === 'error'
      ? h('div', { class: 'act' }, h('button', { class: 'btn', type: 'button', text: 'Try again', onclick: () => { delete S.sess[id]; loadSession(id); render(); } }))
      : null;
    return h('div', null, head, h('main', { class: 'wrap' },
      heading,
      snap ? h('p', { class: 'sub tight-sub', text: snap.project }) : null,
      h('p', { class: 'lede', text: note }), retry, gone ? null : openBlock(id)));
  }

  const bad = d.state === 'error' || d.state === 'failed';
  const snooze = snap && snap.snooze ? snoozeText(snap.snooze) : '';
  const status = d.sentence || stateLabel(d.state);
  const times = [];
  const kv = (k, v) => h('div', { class: 'kv' }, h('dt', { text: k }), h('dd', null, v));
  if (d.state === 'working' && d.startedAt) times.push(kv('Working for', clockEl(d.startedAt)));
  if (d.startedAt) times.push(kv('Started', [when(d.startedAt), ' ', h('span', { class: 'sub' }, '(', rel(d.startedAt), ')')]));
  if (d.updatedAt) times.push(kv('Updated', rel(d.updatedAt)));


  const plan = d.plan;
  const steps = plan && Array.isArray(plan.steps) ? plan.steps : [];
  const planCard = plan ? section('Plan', 0, h('div', { class: 'card plan' },
    plan.summary ? h('p', { text: plan.summary }) : null,
    steps.length ? h('ol', null, steps.map((s) => h('li', { text: typeof s === 'string' ? s : (s && (s.text || s.title)) || '' }))) : null,
    plan.feasibility ? h('p', { class: 'feas', text: 'Feasibility: ' + plan.feasibility }) : null)) : null;

  const tree = h('div', null, head, h('main', { class: 'wrap' },
    heading,
    d.project ? h('p', { class: 'sub tight-sub', text: d.project }) : null,
    h('p', { class: 'status' + (bad ? ' err' : d.state === 'needsInput' ? '' : ' calm'), text: status }),
    snooze ? h('p', { class: 'snooze lone', text: snooze }) : null,
    openBlock(id),
    times.length ? h('dl', { class: 'group sec' }, times) : null,
    planCard));
  return tree;
}

/* ---------- Settings ---------- */

function settingsView() {
  const me = S.me;
  const version = (me && me.bench) || (S.state && S.state.bench) || '';
  const msg = h('p', { id: 'unpair-msg', class: 'msg bad', role: 'alert', hidden: true });
  const row = (k, v) => h('div', { class: 'kv' }, h('dt', { text: k }), h('dd', { text: v }));
  const main = h('main', { class: 'wrap' },
    h('h1', { class: 'large', tabindex: '-1', text: 'Settings' }),
    h('dl', { class: 'group sec' }, row('This device', (me && me.device) || '…'), version ? row('Bench', version) : null),
    h('div', { class: 'act' },
      h('button', {
        class: 'btn danger',
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
    h('p', { class: 'foot', text: 'Only people on your Tailscale network can reach this page, and only a paired device can see your sessions.' }));
  return h('div', null, bar('Settings', backLink('Now'), null), main);
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
  history.replaceState(null, '', location.pathname);
  S.rk = 'now';
  showPair();
}

function confirmSheet({ title, message, confirm, run }) {
  const before = document.activeElement;
  const cancel = h('button', { class: 'btn plain', type: 'button', text: 'Cancel', onclick: close });
  const scrim = h('div', { class: 'scrim', onclick: (e) => { if (e.target === scrim) close(); } },
    h('div', { class: 'sheet', role: 'alertdialog', 'aria-modal': 'true', 'aria-labelledby': 'sheet-t', 'aria-describedby': 'sheet-d' },
      h('div', { class: 'box' },
        h('h2', { id: 'sheet-t', text: title }),
        h('p', { id: 'sheet-d', text: message }),
        h('button', { class: 'btn danger', type: 'button', text: confirm, onclick: () => { close(); run(); } })),
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
      icon('phone', 'big'),
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

addEventListener('touchstart', (e) => {
  const ok = S.view === 'app' && window.scrollY <= 0 && e.touches.length === 1 && !document.querySelector('.scrim');
  pullFrom = ok ? e.touches[0].clientY : -1;
}, { passive: true });
addEventListener('touchmove', (e) => {
  if (pullFrom < 0) return;
  if (window.scrollY > 0) { pullFrom = -1; setPull(0); return; }
  const dy = e.touches[0].clientY - pullFrom;
  setPull(dy > 90 ? 2 : dy > 24 ? 1 : 0);
}, { passive: true });
addEventListener('touchend', async () => {
  const go = pullStage === 2;
  pullFrom = -1;
  if (go) {
    pullEl.textContent = 'Refreshing…';
    await refreshAll(true);
  }
  setPull(0);
}, { passive: true });
addEventListener('touchcancel', () => { pullFrom = -1; setPull(0); }, { passive: true });

/* ---------- go ---------- */

document.addEventListener('visibilitychange', () => (document.hidden ? onHidden() : onVisible()));
addEventListener('pageshow', (e) => { if (e.persisted) onVisible(); });
addEventListener('online', onVisible);
S.rk = routeKey();
startTicker();
start();
