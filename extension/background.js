const DEFAULT_API_URL = 'http://localhost:3001';
const ALLOWED_PAGE_HOSTS = new Set(['lu.ma', 'luma.com', 'www.lu.ma', 'www.luma.com']);

function normalizeApiUrl(value) {
  let url;
  try { url = new URL(value); } catch (_) { return null; }
  const localHosts = new Set(['localhost', '127.0.0.1']);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && localHosts.has(url.hostname))) return null;
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/') return null;
  return url.origin;
}

function apiCandidates(baseUrl) {
  const primary = new URL(baseUrl);
  const candidates = [primary.origin];
  if (primary.protocol === 'http:' && (primary.hostname === 'localhost' || primary.hostname === '127.0.0.1')) {
    const fallback = new URL(primary.origin);
    fallback.hostname = primary.hostname === 'localhost' ? '127.0.0.1' : 'localhost';
    if (!candidates.includes(fallback.origin)) candidates.push(fallback.origin);
  }
  return candidates;
}

function validEvent(event) {
  if (!event || typeof event !== 'object' || Array.isArray(event)) return false;
  const requiredValid = ['title', 'start', 'end', 'location', 'url'].every(key =>
    typeof event[key] === 'string' && event[key].length <= (key === 'url' ? 2048 : 1000)
  );
  if (!requiredValid) return false;
  if (event.image === undefined || event.image === '') return true;
  if (typeof event.image !== 'string' || event.image.length > 2048) return false;
  try { return new URL(event.image).protocol === 'https:'; } catch (_) { return false; }
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== 'MICRO_INTENT_PLAN') return false;
  let senderUrl;
  try { senderUrl = new URL(sender.url); } catch (_) {
    sendResponse({ ok: false, error: 'The request must come from a Luma event page.' });
    return false;
  }
  if (senderUrl.protocol !== 'https:' || !ALLOWED_PAGE_HOSTS.has(senderUrl.hostname)) {
    sendResponse({ ok: false, error: 'The request must come from a Luma event page.' });
    return false;
  }
  const payload = message.payload;
  if (!payload || typeof payload.query !== 'string' || payload.query.length > 2000 ||
      typeof payload.origin !== 'string' || payload.origin.length > 300 ||
      payload.pageOrigin !== senderUrl.origin || !validEvent(payload.event)) {
    sendResponse({ ok: false, error: 'The event details or request were invalid.' });
    return false;
  }

  (async () => {
    const settings = await chrome.storage.sync.get({ microIntentApiUrl: DEFAULT_API_URL });
    const configuredApiUrl = normalizeApiUrl(settings.microIntentApiUrl || DEFAULT_API_URL);
    if (!configuredApiUrl) {
      sendResponse({ ok: false, error: 'The saved planner API URL is invalid. Update it in the extension popup.' });
      return;
    }
    const candidates = apiCandidates(configuredApiUrl);
    const grantedCandidates = [];
    for (const origin of candidates) {
      const permission = await chrome.permissions.contains({ origins: [`${origin}/*`] });
      if (permission) grantedCandidates.push(origin);
    }
    if (!grantedCandidates.length) {
      sendResponse({ ok: false, error: 'Planner API access is not granted. Save the API URL in the extension popup to grant access.' });
      return;
    }

    let lastError;
    for (const origin of grantedCandidates) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 20000);
      try {
        const response = await fetch(`${origin}/api/plan`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ query: payload.query, event: payload.event, origin: payload.origin }),
          signal: controller.signal
        });
        if (!response.ok) {
          let errorMessage = `Planner returned HTTP ${response.status}.`;
          try {
            const body = await response.json();
            if (typeof body?.error === 'string' && body.error.length <= 500) errorMessage = body.error;
          } catch (_) { /* Keep the HTTP status if the server did not return JSON. */ }
          sendResponse({ ok: false, error: errorMessage });
          return;
        }
        const data = await response.json();
        if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('Planner returned an invalid response.');
        sendResponse({ ok: true, data });
        return;
      } catch (error) {
        lastError = error;
      } finally {
        clearTimeout(timeout);
      }
    }
    sendResponse({
      ok: false,
      error: lastError?.name === 'AbortError'
        ? 'The planner request timed out.'
        : `Could not connect to the planner API at ${configuredApiUrl}.`
    });
  })().catch(error => {
    sendResponse({ ok: false, error: error?.message || 'The planner request failed.' });
  });
  return true;
});
