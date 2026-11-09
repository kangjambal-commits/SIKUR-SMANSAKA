const CACHE='sikur-smansaka-pwa-v5';
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
  event.waitUntil((async()=>{
    const keys=await caches.keys();
    await Promise.all(keys.filter(key=>key.startsWith('sikur-smansaka-pwa-')&&key!==CACHE).map(key=>caches.delete(key)));
    await self.clients.claim();
  })());
});
self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET') return;
  if(event.request.mode==='navigate'){
    event.respondWith(fetch(event.request).catch(()=>caches.match(event.request).then(response=>response||caches.match(BASE.href))));
    return;
  }
  event.respondWith(caches.match(event.request).then(response=>response||fetch(event.request)));
});
