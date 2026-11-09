const CACHE='sikur-smansaka-pwa-v4';
const BASE=new URL('./',self.registration.scope);
const ASSETS=[
  BASE.href,
  new URL('manifest.webmanifest',BASE).href,
  new URL('icons/icon-192.png',BASE).href,
  new URL('icons/icon-512.png',BASE).href
];
self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS)));
  self.skipWaiting();
});
self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))));
  self.clients.claim();
});
self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET') return;
  if(event.request.mode==='navigate'){
    event.respondWith(fetch(event.request).catch(()=>caches.match(BASE.href)));
    return;
  }
  event.respondWith(caches.match(event.request).then(response=>response||fetch(event.request)));
});
