const CACHE = 'sikur-smansaka-pwa-v1';
const APP_SHELL = [
  '/SIKUR-SMANSAKA/',
  '/SIKUR-SMANSAKA/index.html',
  '/SIKUR-SMANSAKA/pantau/',
  '/SIKUR-SMANSAKA/pantau/index.html',
  '/SIKUR-SMANSAKA/manifest.webmanifest',
  '/SIKUR-SMANSAKA/icon-192.png',
  '/SIKUR-SMANSAKA/icon-512.png'
];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))));
  self.clients.claim();
});
self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  if (req.mode === 'navigate') {
    event.respondWith(fetch(req).catch(() => caches.match(req).then(r => r || caches.match('/SIKUR-SMANSAKA/'))));
    return;
  }
  event.respondWith(caches.match(req).then(cached => cached || fetch(req).then(resp => {
    if (resp && resp.ok) caches.open(CACHE).then(cache => cache.put(req, resp.clone()));
    return resp;
  })));
});
