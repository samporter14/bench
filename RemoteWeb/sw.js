// Capsid on your phone: the service worker. It does one job: show a push and open the app on a tap.
// A push may also carry the count for the Home Screen icon. It caches nothing and has no fetch handler, so the app stays network-only.

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

// The count on the Capsid icon (Settings can turn it off: then Capsid leaves `badge` out). iOS has no silent
// pushes, so it changes when a push arrives, and the app corrects it when it opens.
function setBadge(count) {
  if (!Number.isInteger(count) || count < 0 || !('setAppBadge' in self.navigator)) return Promise.resolve();
  try {
    return Promise.resolve(count > 0 ? self.navigator.setAppBadge(count) : self.navigator.clearAppBadge()).catch(() => {});
  } catch {
    return Promise.resolve();
  }
}

self.addEventListener('push', (event) => {
  let data = null;
  try { data = event.data ? event.data.json() : null; } catch { data = null; }
  const text = (v, fallback) => (typeof v === 'string' && v.trim() ? v : fallback);
  const info = data && typeof data === 'object' ? data : {};
  // A push must always show something, or the browser shows its own.
  const shown = self.registration.showNotification(text(info.title, 'Claude Science'), {
    body: text(info.body, 'Something needs you'),
    tag: typeof info.tag === 'string' && info.tag ? info.tag : undefined,
    icon: '/icon-180.png',
    badge: '/icon-180.png',
    data: { url: safePath(info.url) },
  });
  event.waitUntil(Promise.all([shown, setBadge(info.badge)]));
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
