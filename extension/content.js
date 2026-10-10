(() => {
  if (window.__microIntentLoaded) return;
  window.__microIntentLoaded = true;

  const DEFAULT_APP_URL = 'http://localhost:5173';
  const ROOT_ID = 'micro-intent-extension-root';
  let host;
  let shadow;
  let panel;
  let orb;
  let enabled = true;
  let contextEnabled = true;
  let originMode = 'empty';
  let recognition;
  let eventData;
  let appUrl = DEFAULT_APP_URL;
  let lastHoveredTitle = '';
  let eventRevision = 0;

  const clean = value => typeof value === 'string' ? value.trim().slice(0, 1000) : '';
  const make = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };

  function walkJsonLd(value, events, depth = 0) {
    if (!value || depth > 32 || events.length >= 100) return;
    if (Array.isArray(value)) return value.forEach(item => walkJsonLd(item, events, depth + 1));
    if (typeof value !== 'object') return;
    const types = Array.isArray(value['@type']) ? value['@type'] : [value['@type']];
    if (events.length < 100 && types.some(type => typeof type === 'string' && /event/i.test(type))) events.push(value);
    Object.values(value).forEach(item => {
      if (item && typeof item === 'object') walkJsonLd(item, events, depth + 1);
    });
  }

  function formatLocation(place) {
    if (typeof place === 'string') {
      const seen = new Set();
      return clean(place).split(',').map(part => clean(part)).filter(part => {
        const key = part.toLocaleLowerCase('en-GB').replace(/\s+/g, ' ');
        if (!key || seen.has(key)) return false;
        seen.add(key);
        return true;
      }).join(', ');
    }
    if (!place || typeof place !== 'object') return '';
    const address = place.address;
    const parts = [
      place.name,
      typeof address === 'string' ? address : address?.streetAddress,
      typeof address === 'object' ? address?.addressLocality : '',
      typeof address === 'object' ? address?.addressRegion : '',
      typeof address === 'object' ? address?.postalCode : '',
      typeof address === 'object' ? address?.addressCountry : ''
    ];
    const seen = new Set();
    return parts.map(clean).filter(part => {
      const key = part.toLocaleLowerCase('en-GB').replace(/\s+/g, ' ');
      if (!key || seen.has(key)) return false;
      seen.add(key);
      return true;
    }).join(', ');
  }

  function secureImageUrl(value) {
    const raw = typeof value === 'string' ? value : value?.url || value?.contentUrl;
    if (typeof raw !== 'string' || raw.length > 2048) return '';
    try {
      const imageUrl = new URL(raw, location.href);
      return imageUrl.protocol === 'https:' ? imageUrl.href : '';
    } catch (_) { return ''; }
  }

  function extractImage(source) {
    const images = Array.isArray(source.image) ? source.image : [source.image];
    for (const image of images) {
      const safe = secureImageUrl(image);
      if (safe) return safe;
    }
    return secureImageUrl(document.querySelector('meta[property="og:image"]')?.content);
  }

  function extractEvent() {
    const candidates = [];
    document.querySelectorAll('script[type="application/ld+json"]').forEach(script => {
      try { walkJsonLd(JSON.parse(script.textContent), candidates); } catch (_) { /* Ignore malformed page metadata. */ }
    });
    const source = candidates[0] || {};
    const jsonLocation = formatLocation(source.location);
    const titleNode = document.querySelector('h1') || document.querySelector('[data-testid*="event-title"]');
    const times = [...document.querySelectorAll('time[datetime], [data-testid*="event-time"] time')];
    const locationNode = document.querySelector('[data-testid*="location"]') ||
      document.querySelector('[itemprop="location"]') || document.querySelector('address') ||
      document.querySelector('[class*="location"]');
    return {
      title: clean(source.name) || clean(titleNode?.textContent),
      start: clean(source.startDate) || clean(times[0]?.getAttribute('datetime')),
      end: clean(source.endDate) || clean(times[1]?.getAttribute('datetime')),
      location: clean(jsonLocation) || clean(locationNode?.textContent),
      url: clean(source.url) || location.href,
      image: extractImage(source)
    };
  }

  function formatTime(value) {
    const date = new Date(value);
    if (!value || !Number.isFinite(date.getTime())) return '';
    return new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Europe/Zurich', hour: '2-digit', minute: '2-digit'
    }).format(date);
  }

  function formatWhen(start, end) {
    const date = new Date(start);
    if (!start || !Number.isFinite(date.getTime())) return '';
    const day = new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Europe/Zurich', weekday: 'short', day: 'numeric', month: 'short'
    }).format(date);
    const startTime = formatTime(start);
    const endDate = new Date(end);
    const endTime = Number.isFinite(endDate.getTime()) ? formatTime(end) : '';
    return endTime ? `${day} · ${startTime}–${endTime} · Zurich time` : `${day} · ${startTime} · Zurich time`;
  }

  function showApp() {
    const current = readEventFields();
    const query = new URLSearchParams({ event: JSON.stringify(current) });
    window.open(`${appUrl}/?${query.toString()}`, '_blank', 'noopener');
  }

  function readEventFields() {
    if (!panel) return eventData;
    const byName = name => panel.querySelector(`[name="${name}"]`);
    return {
      title: clean(byName('title')?.value),
      start: clean(byName('start')?.value),
      end: clean(byName('end')?.value),
      location: clean(byName('location')?.value),
      url: eventData?.url || location.href,
      image: eventData?.image || ''
    };
  }

  function isTransportIntent(query) {
    return /\b(route|directions|travel|transit|transport|train|rail|flight|fly|journey|commute|bus|tram|subway|metro|departure|depart|arrive|leave|get there|how do i get|how to get|way to)\b|como llegar|cómo llegar|como voy|cómo voy|transporte|autobus|autobús|tren|vuelo|viaje|ruta|desplaz|llegar|salir|salgo|cuando salir|cuándo salir/i.test(query);
  }

  function currentPosition() {
    return new Promise((resolve, reject) => {
      if (!navigator.geolocation) {
        reject(new Error('Location is unavailable in this browser. Enter a starting point manually.'));
        return;
      }
      navigator.geolocation.getCurrentPosition(position => {
        const latitude = Number(position.coords.latitude);
        const longitude = Number(position.coords.longitude);
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
          reject(new Error('Your location could not be determined. Enter a starting point manually.'));
          return;
        }
        resolve(`${latitude.toFixed(6)},${longitude.toFixed(6)}`);
      }, error => {
        const message = error?.code === 1
          ? 'Location permission was denied. Enter a starting point manually or allow location access in browser settings.'
          : error?.code === 3
            ? 'Location lookup timed out. Enter a starting point manually and try again.'
            : 'Your location is unavailable. Enter a starting point manually and try again.';
        reject(new Error(message));
      }, { enableHighAccuracy: false, timeout: 12000, maximumAge: 30000 });
    });
  }

  async function chooseCurrentLocation(originInput, status) {
    originMode = 'current';
    originInput.value = 'Current location';
    updateEventView();
    const requestedRevision = eventRevision;
    status.textContent = 'Requesting your current location…';
    try {
      await currentPosition();
      status.textContent = requestedRevision === eventRevision
        ? 'Current location ready. It refreshes when you plan a route.'
        : 'Starting point changed. Your manual entry was kept.';
    } catch (error) {
      if (requestedRevision !== eventRevision) {
        status.textContent = 'Starting point changed. Your manual entry was kept.';
        return;
      }
      originMode = 'empty';
      originInput.value = '';
      updateEventView();
      status.textContent = error.message;
    }
  }

  function clearPlanResults() {
    const calendarStatus = panel.querySelector('[data-role="calendar-status"]');
    const calendarDetail = panel.querySelector('[data-role="calendar-detail"]');
    const mode = panel.querySelector('[data-role="mode"]');
    calendarStatus.dataset.planned = '';
    calendarDetail.textContent = '';
    calendarStatus.textContent = 'Add event details to check your calendar';
    mode.textContent = 'Demo calendar';
    mode.classList.remove('live');
    panel.querySelector('[data-role="status"]').textContent = '';
    const links = panel.querySelector('[data-role="route-links"]');
    links.replaceChildren(make('span', 'card-detail', 'Route links appear after planning.'));
  }

  function updateEventView() {
    if (!panel) return;
    eventRevision += 1;
    const current = readEventFields();
    panel.querySelector('[data-role="event-title"]').textContent = current.title ? `For ${current.title}` : 'For this event';
    panel.querySelector('[data-role="when"]').textContent = formatWhen(current.start, current.end) || 'Date and time not found';
    panel.querySelector('[data-role="destination"]').textContent = current.location || 'Add an event location';
    const originValue = panel.querySelector('[name="origin"]').value.trim();
    panel.querySelector('[data-role="origin"]').textContent = originMode === 'current' ? 'Current location' : originValue || 'Add a starting point';
    const arrival = current.start ? `Arrive by ${formatWhen(current.start)} · check live departures with SBB or Maps.` : 'Check live departures with SBB or Maps before you leave.';
    panel.querySelector('[data-role="arrival-note"]').textContent = arrival;
    clearPlanResults();
    const calendarStatus = panel.querySelector('[data-role="calendar-status"]');
    if (!calendarStatus.dataset.planned) {
      calendarStatus.textContent = current.title && current.start
        ? 'Ask Lumi to check your calendar'
        : 'Add event details to check your calendar';
    }
  }

  function setPanelOpen(open) {
    panel.hidden = !open;
    orb.setAttribute('aria-expanded', String(open));
    if (open) panel.querySelector('[name="query"]').focus();
  }

  function makeBeaver() {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 100 110');
    svg.setAttribute('aria-hidden', 'true');
    const add = (tag, attributes) => {
      const shape = document.createElementNS('http://www.w3.org/2000/svg', tag);
      Object.entries(attributes).forEach(([name, value]) => shape.setAttribute(name, value));
      svg.append(shape);
    };
    add('ellipse', { cx: 81, cy: 86, rx: 14, ry: 22, fill: '#74573e', transform: 'rotate(30 81 86)' });
    add('path', { d: 'm74 76 15 16m-18-5 13 14m-6-28-8 26', stroke: '#4f402e', 'stroke-width': 2 });
    add('ellipse', { cx: 47, cy: 74, rx: 30, ry: 31, fill: '#ac7648' });
    add('circle', { cx: 22, cy: 29, r: 12, fill: '#98643f' });
    add('circle', { cx: 69, cy: 29, r: 12, fill: '#98643f' });
    add('ellipse', { cx: 46, cy: 45, rx: 33, ry: 29, fill: '#b98452' });
    add('ellipse', { cx: 46, cy: 66, rx: 21, ry: 25, fill: '#e5bc83' });
    add('circle', { cx: 33, cy: 41, r: 4, fill: '#202c25' });
    add('circle', { cx: 60, cy: 41, r: 4, fill: '#202c25' });
    add('ellipse', { cx: 46, cy: 53, rx: 7, ry: 5, fill: '#483323' });
    add('path', { d: 'M40 61h12v11H40z', fill: '#fff9e9' });
    return svg;
  }

  function makeCardIcon(emoji) {
    const icon = make('span', 'card-icon', emoji);
    icon.setAttribute('aria-hidden', 'true');
    return icon;
  }

  function addStyles() {
    const style = make('style');
    style.textContent = `
      :host { all:initial;color:#18251d;font:13px/1.4 Inter,system-ui,-apple-system,"Segoe UI",sans-serif; }
      * { box-sizing:border-box; }
      button,input,summary { font:inherit; }
      .widget { position:fixed;z-index:2147483647;right:16px;bottom:14px;display:flex;flex-direction:column;align-items:flex-end;gap:9px; }
      .panel { width:min(320px,calc(100vw - 24px));max-height:calc(100vh - 102px);max-height:calc(100dvh - 102px);overflow:auto;background:#fff;border:1px solid #b9dfc4;border-radius:17px;box-shadow:0 12px 40px #14291d2b;padding:13px; }
      .panel[hidden] { display:none; }
      .topline { display:flex;align-items:center;justify-content:space-between;margin:0 0 7px; }
      .brand { display:flex;align-items:center;gap:7px;color:#17633e;font-size:12px;font-weight:750;letter-spacing:.02em; }
      .brand-mark { display:grid;place-items:center;width:22px;height:22px;border-radius:50%;background:#e4f5e8;font-size:14px; }
      .close { border:0;background:transparent;color:#718075;cursor:pointer;font-size:18px;line-height:1;padding:3px 5px; }
      h2 { margin:0;color:#203127;font-size:17px;line-height:1.25;letter-spacing:-.025em; }
      .event-title { display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;overflow:hidden;overflow-wrap:anywhere; }
      .when { margin:4px 0 10px;color:#68766b;font-size:11px; }
      .card { display:flex;gap:9px;margin-top:8px;padding:10px;border:1px solid #e2e8e0;border-radius:13px;background:#f7faf4; }
      .journey-card { border-color:#e8e1f1;background:#faf8fd; }
      .card-icon { display:grid;place-items:center;flex:0 0 30px;width:30px;height:30px;border-radius:9px;background:#eaf2e7;font-size:14px;color:#6e8a69; }
      .journey-card .card-icon { background:#f0eafa;color:#8b7ba5; }
      .card-main { min-width:0;flex:1; }
      .card-heading { display:flex;align-items:center;gap:6px;color:#55705d;font-size:9px;font-weight:800;letter-spacing:.09em;text-transform:uppercase; }
      .badge { margin-left:auto;padding:2px 6px;border-radius:99px;background:#fff1d7;color:#80520d;font-size:8px;letter-spacing:.04em;white-space:nowrap; }
      .badge.live { background:#e4f5e8;color:#19633e; }
      .card-title { display:block;margin-top:4px;color:#26352b;font-size:12px;font-weight:700;line-height:1.3;overflow-wrap:anywhere; }
      .card-detail { display:block;margin-top:3px;color:#718075;font-size:10px;line-height:1.35;overflow-wrap:anywhere; }
      .journey { display:grid;grid-template-columns:minmax(0,1fr) 14px minmax(0,1fr);align-items:start;gap:5px;margin-top:7px; }
      .journey-place { font-size:10px;font-weight:650;line-height:1.35;overflow-wrap:anywhere; }
      .arrow { color:#5e9c70;text-align:center; }
      .arrival-note { display:block;margin-top:6px;color:#817690;font-size:9px;line-height:1.4; }
      .location-button { display:block;margin-top:7px;padding:5px 8px;border:1px solid #e5def0;border-radius:7px;background:#fff;color:#695786;font-size:10px;font-weight:650;cursor:pointer; }
      .location-button:disabled { opacity:.6;cursor:wait; }
      .privacy-note { display:block;margin-top:4px;color:#8b8495;font-size:8px;line-height:1.35; }
      .route-links { display:flex;gap:10px;margin-top:8px; }
      .route-link { color:#176b47;font-size:11px;font-weight:600;text-decoration:none; }
      button.route-link { display:block;width:100%;margin-top:9px;padding:8px;border:0;border-radius:6px;background:#e5eee2;cursor:pointer;text-align:center; }
      .route-link:hover { text-decoration:underline; }
      details { margin-top:9px;border-top:1px solid #edf1ed;padding-top:7px; }
      summary { color:#637269;cursor:pointer;font-size:10px;font-weight:650; }
      .fields { display:grid;grid-template-columns:1fr 1fr;gap:6px 8px;margin-top:6px; }
      .field { min-width:0; }
      .field.wide { grid-column:1/-1; }
      label { display:block;margin-bottom:2px;color:#657368;font-size:9px;font-weight:700; }
      .fields input { width:100%;min-width:0;border:1px solid #dce7dd;border-radius:7px;background:#fff;padding:6px 7px;color:#253329;font-size:10px; }
      .ask { display:flex;gap:6px;margin-top:9px; }
      .ask input { min-width:0;flex:1;border:1px solid #dce7dd;border-radius:9px;padding:8px 9px;color:#253329;font-size:11px; }
      .send { flex:0 0 auto;width:34px;border:0;border-radius:9px;background:#187149;color:white;font-size:16px;cursor:pointer; }
      .send:disabled { opacity:.5;cursor:wait; }
      .status { min-height:0;margin:6px 0 0;color:#68766b;font-size:10px; }
      .status:empty { display:none; }
      .footer { margin:8px 1px 0;color:#8a958c;font-size:9px;text-align:center; }
      .dock-row { display:flex;align-items:flex-end;gap:8px; }
      .dock { display:flex;align-items:center;gap:3px;padding:4px;border:1px solid #e9e8ee;border-radius:999px;background:#fff;box-shadow:0 3px 8px #3333330d;margin-bottom:5px; }
      .dock button { display:flex;align-items:center;justify-content:center;gap:4px;min-width:32px;height:31px;padding:0 8px;border:0;border-radius:999px;background:transparent;color:#516457;font-size:10px;font-weight:650;cursor:pointer; }
      .dock button:hover,.dock button:focus-visible { background:#eaf5ec;outline:none; }
      .launcher { position:relative;display:grid;place-items:center;width:49px;height:59px;padding:0;border:0;background:transparent;cursor:pointer; }
      .launcher svg { width:100%;height:100%;filter:drop-shadow(0 3px 1px #5d46311a); }
      .launcher span { position:absolute;right:0;top:0;color:#95ad75;font-size:17px; }
      .launcher:hover { filter:brightness(.98); }
      .dock .divider { width:1px;height:18px;margin:0 1px;background:#e2e9e3; }
      @media(max-width:400px) { .widget { right:10px;bottom:10px; } .panel { width:calc(100vw - 20px); } }
      @media(prefers-reduced-motion:no-preference) { .panel { animation:mi-enter .14s ease-out; } @keyframes mi-enter { from { opacity:.7;transform:translateY(5px); } to { opacity:1;transform:none; } } }
    `;
    shadow.append(style);
  }

  function buildPanel() {
    host = document.createElement('div');
    host.id = ROOT_ID;
    shadow = host.attachShadow({ mode: 'open' });
    addStyles();

    const widget = make('div', 'widget');
    panel = make('section', 'panel');
    panel.hidden = true;
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Lumi event suggestions');

    const top = make('div', 'topline');
    const brand = make('div', 'brand');
    brand.append(make('span', 'brand-mark', '✦'), document.createTextNode('Lumi suggestions'));
    const close = make('button', 'close', '×');
    close.type = 'button';
    close.setAttribute('aria-label', 'Close suggestions');
    close.addEventListener('click', () => setPanelOpen(false));
    top.append(brand, close);

    const title = make('h2', 'event-title');
    title.dataset.role = 'event-title';
    const when = make('p', 'when');
    when.dataset.role = 'when';
    panel.append(top, title, when);

    const calendarCard = make('div', 'card');
    calendarCard.append(makeCardIcon('▦'));
    const calendarMain = make('div', 'card-main');
    const calendarHeading = make('div', 'card-heading', 'Calendar');
    const modeBadge = make('span', 'badge', 'Demo calendar');
    modeBadge.dataset.role = 'mode';
    calendarHeading.append(modeBadge);
    const calendarStatus = make('strong', 'card-title', 'Add event details to check your calendar');
    calendarStatus.dataset.role = 'calendar-status';
    const calendarDetail = make('span', 'card-detail');
    calendarDetail.dataset.role = 'calendar-detail';
    const review = make('button', 'route-link', 'Review in app');
    review.type = 'button';
    review.addEventListener('click', showApp);
    calendarMain.append(calendarHeading, calendarStatus, calendarDetail, review);
    calendarCard.append(calendarMain);

    const routeCard = make('div', 'card journey-card');
    routeCard.append(makeCardIcon('↗'));
    const routeMain = make('div', 'card-main');
    const routeHeading = make('div', 'card-heading', 'Journey');
    const routeLabel = make('span', 'badge live', 'SBB');
    routeHeading.append(routeLabel);
    const journey = make('div', 'journey');
    const origin = make('span', 'journey-place');
    origin.dataset.role = 'origin';
    const arrow = make('span', 'arrow', '→');
    arrow.setAttribute('aria-hidden', 'true');
    const destination = make('span', 'journey-place');
    destination.dataset.role = 'destination';
    journey.append(origin, arrow, destination);
    const routeLinks = make('div', 'route-links');
    routeLinks.dataset.role = 'route-links';
    const arrivalNote = make('span', 'arrival-note');
    arrivalNote.dataset.role = 'arrival-note';
    const useLocation = make('button', 'location-button', 'Use current location');
    useLocation.type = 'button';
    const privacyNote = make('span', 'privacy-note', 'The planner uses your location to prepare this route; Maps receives it if you open the link.');
    routeMain.append(routeHeading, journey, arrivalNote, useLocation, privacyNote, routeLinks);
    routeCard.append(routeMain);

    const edit = make('details', 'edit');
    edit.append(make('summary', '', 'Edit event details'));
    const fields = make('div', 'fields');
    let originInput;
    const fieldDefinitions = [
      ['title', 'Event title', 'wide'], ['start', 'Start date and time', ''],
      ['end', 'End date and time', ''], ['location', 'Event location', 'wide'],
      ['origin', 'Starting point', 'wide']
    ];
    fieldDefinitions.forEach(([name, label, extra]) => {
      const wrapper = make('div', `field ${extra}`.trim());
      const fieldLabel = make('label', '', label);
      fieldLabel.htmlFor = `mi-${name}`;
      const input = make('input');
      input.id = `mi-${name}`;
      input.name = name;
      input.type = 'text';
      if (name === 'origin') originInput = input;
      if (name === 'start' || name === 'end') input.placeholder = 'ISO date/time';
      if (name === 'origin') input.placeholder = 'Optional';
      input.addEventListener('input', () => {
        if (name === 'origin') originMode = input.value.trim() ? 'manual' : 'empty';
        updateEventView();
      });
      wrapper.append(fieldLabel, input);
      fields.append(wrapper);
    });
    edit.append(fields);

    const ask = make('div', 'ask');
    const query = make('input');
    query.name = 'query';
    query.setAttribute('aria-label', 'Planning request');
    query.placeholder = 'Ask Lumi about this event…';
    query.value = 'Am I free, and how do I get there?';
    const send = make('button', 'send', '↑');
    send.type = 'button';
    send.setAttribute('aria-label', 'Plan around this event');
    send.addEventListener('click', () => plan(query.value.trim() || 'Plan around this event', send));
    query.addEventListener('keydown', event => { if (event.key === 'Enter') send.click(); });
    ask.append(query, send);
    const status = make('p', 'status');
    status.setAttribute('role', 'status');
    status.dataset.role = 'status';
    useLocation.addEventListener('click', async () => {
      useLocation.disabled = true;
      await chooseCurrentLocation(originInput, status);
      useLocation.disabled = false;
    });
    const footer = make('p', 'footer', 'Review actions in the app · nothing is added here');
    panel.append(calendarCard, routeCard, edit, ask, status, footer);

    const dock = make('div', 'dock');
    dock.setAttribute('role', 'toolbar');
    dock.setAttribute('aria-label', 'Micro Intent tools');
    orb = make('button', 'launcher', '');
    orb.append(makeBeaver(), make('span', '', '✧'));
    orb.type = 'button';
    orb.title = 'Open Lumi suggestions';
    orb.setAttribute('aria-label', 'Open Lumi suggestions');
    orb.setAttribute('aria-expanded', 'false');
    orb.addEventListener('click', () => setPanelOpen(panel.hidden));
    const divider = make('span', 'divider');
    divider.setAttribute('aria-hidden', 'true');
    const voice = make('button', '', 'Voice');
    voice.type = 'button';
    voice.addEventListener('click', () => { setPanelOpen(true); startVoice(query, send, status); });
    const context = make('button', '', 'Context');
    context.type = 'button';
    context.setAttribute('aria-pressed', 'true');
    context.title = 'Use pointer hover and touch to select event titles.';
    context.addEventListener('click', () => {
      contextEnabled = !contextEnabled;
      context.setAttribute('aria-pressed', String(contextEnabled));
      status.textContent = contextEnabled ? 'Title context follows pointer and touch.' : 'Title context selection is paused.';
      setPanelOpen(true);
    });
    const settings = make('button', '', 'Settings');
    settings.type = 'button';
    settings.addEventListener('click', () => window.open(chrome.runtime.getURL('popup.html'), '_blank', 'noopener'));
    dock.append(voice, divider, context, settings);
    const dockRow = make('div', 'dock-row');
    dockRow.append(dock, orb);
    widget.append(panel, dockRow);
    shadow.append(widget);
    document.documentElement.append(host);

    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && !panel.hidden) {
        setPanelOpen(false);
        orb.focus();
      }
    });

    const values = { title: eventData.title, start: eventData.start, end: eventData.end, location: eventData.location, origin: '' };
    Object.entries(values).forEach(([name, value]) => { panel.querySelector(`[name="${name}"]`).value = value; });
    updateEventView();
  }

  function createLink(label, url) {
    if (!url) return null;
    try {
      const parsed = new URL(url);
      if (!['http:', 'https:'].includes(parsed.protocol)) return null;
      const link = make('a', 'route-link', label);
      link.href = parsed.href;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      return link;
    } catch (_) { return null; }
  }

  function renderPlan(data) {
    const mode = panel.querySelector('[data-role="mode"]');
    mode.textContent = data.mode === 'google' ? 'Google Calendar' : data.mode === 'demo' ? 'Demo · simulated' : 'Calendar status';
    mode.classList.toggle('live', data.mode === 'google');

    const calendarStatus = panel.querySelector('[data-role="calendar-status"]');
    const calendarDetail = panel.querySelector('[data-role="calendar-detail"]');
    calendarStatus.dataset.planned = 'true';
    const conflicts = Array.isArray(data.conflicts) ? data.conflicts : null;
    if (!conflicts) {
      calendarStatus.textContent = 'Calendar status unavailable';
      calendarDetail.textContent = '';
    } else if (!conflicts.length) {
      calendarStatus.textContent = data.mode === 'demo' ? 'No simulated conflicts' : 'No conflicts found';
      calendarDetail.textContent = data.mode === 'demo' ? 'Connect Google Calendar in the app for live results.' : '';
    } else {
      const first = conflicts[0];
      calendarStatus.textContent = data.mode === 'demo'
        ? `${conflicts.length} possible conflict${conflicts.length === 1 ? '' : 's'} · demo`
        : `${conflicts.length} calendar conflict${conflicts.length === 1 ? '' : 's'}`;
      const title = clean(first.title);
      const when = formatWhen(first.start, first.end);
      calendarDetail.textContent = [title, when].filter(Boolean).join(' · ');
    }

    const links = panel.querySelector('[data-role="route-links"]');
    links.replaceChildren();
    const sbb = createLink('Open SBB route', data.routes?.sbbUrl);
    const maps = createLink('Maps', data.routes?.mapsUrl);
    if (sbb) links.append(sbb);
    if (maps) links.append(maps);
    if (!sbb && !maps) links.append(make('span', 'card-detail', 'Route links appear after planning.'));
  }

  async function plan(query, button) {
    const status = panel.querySelector('[data-role="status"]');
    const originInput = panel.querySelector('[name="origin"]');
    button.disabled = true;
    status.textContent = 'Checking your plan…';
    eventData = readEventFields();
    updateEventView();
    const requestedRevision = eventRevision;
    try {
      const typedOrigin = clean(originInput.value).slice(0, 300);
      const travelIntent = isTransportIntent(query);
      let requestOrigin = originMode === 'manual' ? typedOrigin : '';
      if (travelIntent && (originMode === 'current' || !typedOrigin)) {
        status.textContent = 'Getting your current location…';
        try {
          requestOrigin = await currentPosition();
        } catch (error) {
          if (requestedRevision === eventRevision) {
            originMode = 'empty';
            originInput.value = '';
            updateEventView();
            status.textContent = error.message;
          } else {
            status.textContent = 'Event details changed. Plan again to refresh these results.';
          }
          return;
        }
        if (requestedRevision !== eventRevision) {
          status.textContent = 'Event details changed. Plan again to refresh these results.';
          return;
        }
        originMode = 'current';
        originInput.value = 'Current location';
        panel.querySelector('[data-role="origin"]').textContent = 'Current location';
      }
      const response = await chrome.runtime.sendMessage({
        type: 'MICRO_INTENT_PLAN',
        payload: { query, event: eventData, origin: requestOrigin, pageOrigin: location.origin }
      });
      if (requestedRevision !== eventRevision) {
        status.textContent = 'Event details changed. Plan again to refresh these results.';
        return;
      }
      if (!response?.ok) throw new Error(response?.error || 'Planner request failed.');
      renderPlan(response.data);
      status.textContent = '';
    } catch (error) {
      if (requestedRevision === eventRevision) {
        status.textContent = `${error.message || 'Could not reach the planner API.'} Check the app and API URLs and grant API access in the extension popup.`;
      }
    } finally {
      button.disabled = false;
    }
  }

  function startVoice(queryInput, submit, status) {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
      status.textContent = 'Voice input is unavailable in this browser. Type your request instead.';
      return;
    }
    try {
      recognition?.abort();
      recognition = new SpeechRecognition();
      recognition.lang = 'en-US';
      recognition.interimResults = false;
      recognition.onstart = () => { status.textContent = 'Listening…'; };
      recognition.onerror = event => { status.textContent = `Voice input failed (${event.error}). Type your request instead.`; };
      recognition.onresult = event => {
        queryInput.value = event.results?.[0]?.[0]?.transcript || '';
        if (queryInput.value) submit.click();
      };
      recognition.onend = () => { if (status.textContent === 'Listening…') status.textContent = ''; };
      recognition.start();
    } catch (error) {
      status.textContent = `Voice input could not start: ${error.message || 'permission unavailable'}. Type your request instead.`;
    }
  }

  function setEnabled(value) {
    enabled = Boolean(value);
    if (host) host.hidden = !enabled;
  }

  function watchContext() {
    document.addEventListener('pointerover', event => {
      if (!enabled || !contextEnabled) return;
      const target = event.target?.closest?.('h1,[data-testid*="event-title"]');
      if (!target || host.contains(target)) return;
      const value = clean(target.textContent);
      if (value && value !== lastHoveredTitle && value.length < 240) {
        lastHoveredTitle = value;
        panel.querySelector('[name="title"]').value = value;
        updateEventView();
      }
    }, { passive: true });
    document.addEventListener('touchstart', event => {
      if (!enabled || !contextEnabled) return;
      const target = event.target?.closest?.('h1,[data-testid*="event-title"]');
      const value = clean(target?.textContent);
      if (value && value.length < 240) {
        panel.querySelector('[name="title"]').value = value;
        updateEventView();
      }
    }, { passive: true });
  }

  chrome.storage.sync.get({ microIntentEnabled: true, microIntentAppUrl: DEFAULT_APP_URL }, settings => {
    setEnabled(settings.microIntentEnabled);
    appUrl = settings.microIntentAppUrl || DEFAULT_APP_URL;
  });
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'sync') return;
    if (changes.microIntentEnabled) setEnabled(changes.microIntentEnabled.newValue);
    if (changes.microIntentAppUrl) appUrl = changes.microIntentAppUrl.newValue || DEFAULT_APP_URL;
  });
  eventData = extractEvent();
  if (document.documentElement) {
    buildPanel();
    watchContext();
  }
})();
