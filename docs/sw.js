const CACHE = 'selector-v4';
const SHELL = ['./', './index.html', './styles.css', './app.js', './data.json', './config.js', './manifest.webmanifest', './icon-192.png', './icon-512.png', './fonts/Anton-Regular.ttf'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (url.origin !== location.origin) return;                       // Apple Music and fonts go straight to the network
  if (url.pathname.endsWith('data.json')) { e.respondWith(caches.match(e.request).then(r => r || fetch(e.request))); return; }
  e.respondWith(fetch(e.request).then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r; }).catch(() => caches.match(e.request)));
});
