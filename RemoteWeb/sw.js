// Bench on your phone: the service worker. It does one job: show a push and open the app on a tap.
// It caches nothing and has no fetch handler, so the app stays network-only.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

// Only a path on this site, never another origin or a protocol-relative url.
function safePath(u) {
  if (typeof u !== 'string' || !u.startsWith('/') || u.startsWith('//') || u.includes('\\')) return '/';
  try {
    const url = new URL(u, self.location.origin);
    return url.origin === self.location.origin ? url.pathname + url.search + url.hash : '/';
  } catch {
    return '/';
  }
}

self.addEventListener('push', (event) => {
  let data = null;
  try { data = event.data ? event.data.json() : null; } catch { data = null; }
  const text = (v, fallback) => (typeof v === 'string' && v.trim() ? v : fallback);
  const info = data && typeof data === 'object' ? data : {};
  // A push must always show something, or the browser shows its own.
  event.waitUntil(self.registration.showNotification(text(info.title, 'Claude Science'), {
    body: text(info.body, 'Something needs you'),
    tag: typeof info.tag === 'string' && info.tag ? info.tag : undefined,
    icon: '/icon-180.png',
    badge: '/icon-180.png',
    data: { url: safePath(info.url) },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = safePath(event.notification.data && event.notification.data.url);
  event.waitUntil((async () => {
    const open = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const mine = open.find((c) => c.url.startsWith(self.location.origin));
    if (mine) {
      await mine.focus();
      mine.postMessage({ type: 'open', url }); // the page moves itself, even if it is not controlled yet
      try { await mine.navigate(url); } catch { /* the message covers it */ }
      return;
    }
    await self.clients.openWindow(url);
  })());
});
