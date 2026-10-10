const DEFAULT_APP_URL = 'http://localhost:5173';
const DEFAULT_API_URL = 'http://localhost:3001';
const toggle = document.getElementById('enabled');
const pageState = document.getElementById('page-state');
const pageDetail = document.getElementById('page-detail');
const appUrlInput = document.getElementById('app-url');
const apiUrlInput = document.getElementById('api-url');
const message = document.getElementById('message');
let appUrl = DEFAULT_APP_URL;
let apiUrl = DEFAULT_API_URL;

function parseBaseUrl(value, label) {
  let url;
  try { url = new URL(value.trim()); } catch (_) { throw new Error(`${label} must be a valid URL.`); }
  const localHosts = new Set(['localhost', '127.0.0.1']);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && localHosts.has(url.hostname))) {
    throw new Error(`${label} must use HTTPS. HTTP is allowed only for localhost.`);
  }
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/') {
    throw new Error(`${label} must be an origin URL without a path, query, or credentials.`);
  }
  return url.origin;
}

function permissionOrigins(value) {
  const url = new URL(value);
  const origins = [`${url.origin}/*`];
  if (url.protocol === 'http:' && (url.hostname === 'localhost' || url.hostname === '127.0.0.1')) {
    const fallbackHost = url.hostname === 'localhost' ? '127.0.0.1' : 'localhost';
    origins.push(`http://${fallbackHost}${url.port ? `:${url.port}` : ''}/*`);
  }
  return origins;
}

function showPageState(tabUrl) {
  try {
    const url = new URL(tabUrl || '');
    const isLuma = url.protocol === 'https:' && ['lu.ma', 'luma.com', 'www.lu.ma', 'www.luma.com'].includes(url.hostname);
    pageState.textContent = isLuma ? 'Luma page detected' : 'Available from any tab';
    pageDetail.textContent = isLuma ? 'The orb appears in the lower-right corner.' : 'The popup opens the app. The orb appears on Luma pages.';
  } catch (_) {
    pageState.textContent = 'Browser page';
    pageDetail.textContent = 'Open Luma to use the event orb.';
  }
}

chrome.storage.sync.get({
  microIntentEnabled: true,
  microIntentAppUrl: DEFAULT_APP_URL,
  microIntentApiUrl: DEFAULT_API_URL
}, settings => {
  toggle.checked = Boolean(settings.microIntentEnabled);
  appUrl = settings.microIntentAppUrl || DEFAULT_APP_URL;
  apiUrl = settings.microIntentApiUrl || DEFAULT_API_URL;
  appUrlInput.value = appUrl;
  apiUrlInput.value = apiUrl;
});

chrome.tabs.query({ active: true, currentWindow: true }, tabs => showPageState(tabs[0]?.url));

toggle.addEventListener('change', () => {
  chrome.storage.sync.set({ microIntentEnabled: toggle.checked }, () => {
    message.textContent = toggle.checked ? 'Orb enabled.' : 'Orb disabled.';
  });
});

document.getElementById('save-settings').addEventListener('click', async () => {
  const button = document.getElementById('save-settings');
  button.disabled = true;
  message.textContent = 'Validating URLs and requesting API access…';
  try {
    const nextAppUrl = parseBaseUrl(appUrlInput.value, 'App URL');
    const nextApiUrl = parseBaseUrl(apiUrlInput.value, 'Planner API URL');
    const oldOrigins = permissionOrigins(apiUrl);
    const nextOrigins = permissionOrigins(nextApiUrl);
    const granted = await chrome.permissions.request({ origins: nextOrigins });
    if (!granted) throw new Error('API host access was not granted. The URLs were not changed.');

    await chrome.storage.sync.set({ microIntentAppUrl: nextAppUrl, microIntentApiUrl: nextApiUrl });
    const removeOrigins = oldOrigins.filter(origin => !nextOrigins.includes(origin));
    if (removeOrigins.length) await chrome.permissions.remove({ origins: removeOrigins });
    appUrl = nextAppUrl;
    apiUrl = nextApiUrl;
    message.textContent = 'Settings saved. API access is limited to the selected host.';
  } catch (error) {
    message.textContent = error.message || 'Could not save these settings.';
  } finally {
    button.disabled = false;
  }
});

document.getElementById('open-app').addEventListener('click', () => {
  chrome.tabs.create({ url: appUrl });
  window.close();
});
