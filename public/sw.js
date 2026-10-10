const CACHE_NAME = 'micro-intent-shell-v6-location';
const APP_SHELL = ['/', '/index.html', '/manifest.webmanifest', '/icons/icon.svg', '/icons/icon-192.png', '/icons/icon-512.png'];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL);

    // The first controlled visit happens after Vite has already fetched these
    // hashed entry files. Fetch them here so an immediate offline launch works.
    const indexResponse = await fetch('/index.html', { cache: 'no-store' });
    if (!indexResponse.ok) throw new Error('Micro Intent app shell could not be fetched.');
    await cache.put('/index.html', indexResponse.clone());
    const html = await indexResponse.text();
    const assetPaths = [...html.matchAll(/(?:src|href)="([^"?#]+\.(?:js|css))"/gi)]
      .map(match => match[1])
      .filter(path => path.startsWith('/assets/'));
    await Promise.all(assetPaths.map(async path => {
      const response = await fetch(path, { cache: 'no-store' });
      if (!response.ok || response.type !== 'basic') throw new Error(`App asset could not be cached: ${path}`);
      await cache.put(path, response);
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(
    keys.filter(key => key.startsWith('micro-intent-shell-') && key !== CACHE_NAME).map(key => caches.delete(key))
  )).then(() => self.clients.claim()));
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return;

  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).catch(() => caches.match('/index.html')));
    return;
  }

  // Cache only same-origin app assets. API calls, OAuth traffic, and query-bearing
  // event/context URLs never enter the cache.
  const appAsset = url.pathname.startsWith('/assets/') || url.pathname.startsWith('/icons/') || url.pathname === '/manifest.webmanifest';
  if (!appAsset || url.search || request.headers.has('Authorization')) return;
  event.respondWith(caches.match(request).then(cached => cached || fetch(request).then(response => {
    if (response.ok && response.type === 'basic') {
      const copy = response.clone();
      caches.open(CACHE_NAME).then(cache => cache.put(request, copy));
    }
    return response;
  })));
});
