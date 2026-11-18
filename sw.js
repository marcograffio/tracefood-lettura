// Service Worker TracciaFood
// Bumpare CACHE_NAME ad ogni rilascio per forzare l'aggiornamento della cache.
const CACHE_NAME = 'tracciafood-v26';
const ASSETS = [
  './',
  './index.html',
  './admin.html',
  './app.js',
  './config.js',
  './state.js',
  './auth.js',
  './style.css',
  './supabase-config.js',
  './manifest.json',
  './icon.svg',
  './icon-192.png',
  './icon-512.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME)
      .then((c) => c.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const { request } = e;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const isNavigation = request.mode === 'navigate';
  const isStaticAsset = [
    '.html',
    '.css',
    '.js',
    '.json',
    '.svg',
    '.png',
    '.ico'
  ].some((ext) => url.pathname.endsWith(ext));

  if (isNavigation) {
    e.respondWith(
      fetch(request)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put(request, copy));
          return res;
        })
        .catch(() => caches.match(request).then((r) => r || caches.match('./index.html')))
    );
    return;
  }

  if (!isStaticAsset) return;

  e.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request).then((res) => {
        const copy = res.clone();
        caches.open(CACHE_NAME).then((c) => c.put(request, copy));
        return res;
      });
    })
  );
});
