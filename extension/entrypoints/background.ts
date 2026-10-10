import { callBackend, streamIntent } from '@/lib/backend';
import { STREAM_PORT, type StreamPortMessage, type ToBackground, type ToContent, type ToOffscreen } from '@/lib/messages';
import type { IntentRequest } from '@/src/api/types';

const OFFSCREEN_PATH = '/offscreen.html';
let creatingOffscreen: Promise<void> | undefined;

async function hasOffscreen(): Promise<boolean> {
  const contexts = await browser.runtime.getContexts({ contextTypes: [browser.runtime.ContextType.OFFSCREEN_DOCUMENT] });
  return contexts.length > 0;
}

async function ensureOffscreen() {
  if (await hasOffscreen()) return;
  creatingOffscreen ??= browser.offscreen
    .createDocument({
      url: OFFSCREEN_PATH,
      reasons: [browser.offscreen.Reason.USER_MEDIA],
      justification: 'Push-to-talk microphone capture for voice intents',
    })
    .finally(() => (creatingOffscreen = undefined));
  await creatingOffscreen;
}

async function openOverlay(tabId: number | undefined) {
  if (tabId === undefined) return;
  try {
    await browser.tabs.sendMessage(tabId, { type: 'mi:open' } satisfies ToContent);
  } catch {
    // Tab opened before the extension loaded, or a chrome:// page without content scripts.
    console.warn('[micro-intent] no content script in tab', tabId);
  }
}

export default defineBackground(() => {
  browser.runtime.onInstalled.addListener(() => {
    browser.contextMenus.create({ id: 'micro-intent-ask', title: 'Ask Micro Intent', contexts: ['selection', 'page', 'link'] });
  });

  browser.contextMenus.onClicked.addListener((info, tab) => {
    if (info.menuItemId === 'micro-intent-ask') void openOverlay(tab?.id);
  });

  browser.commands.onCommand.addListener(async (command, tab) => {
    if (command !== 'open-overlay') return;
    const target = tab ?? (await browser.tabs.query({ active: true, currentWindow: true }))[0];
    void openOverlay(target?.id);
  });

  // `/intent/stream`: one port per turn, events relayed as they arrive.
  browser.runtime.onConnect.addListener((port) => {
    if (port.name !== STREAM_PORT) return;
    let open = true;
    port.onDisconnect.addListener(() => (open = false));
    const post = (m: StreamPortMessage) => open && port.postMessage(m);
    port.onMessage.addListener((req: unknown) => {
      streamIntent(req as IntentRequest, (event) => post({ kind: 'event', event })).then(
        ({ mocked }) => post({ kind: 'done', mocked }),
        (err: Error) => post({ kind: 'error', error: err.message }),
      );
    });
  });

  browser.runtime.onMessage.addListener((raw, _sender, sendResponse) => {
    const msg = raw as ToBackground;
    switch (msg?.type) {
      case 'mi:api':
        callBackend(msg.call).then(sendResponse);
        return true;
      case 'mi:voice': {
        const forward: ToOffscreen = { target: 'offscreen', action: msg.action, owner: msg.owner, lang: msg.lang };
        // Only a start may create the voice document; stop and cancel without one are no-ops.
        const ready = msg.action === 'start' ? ensureOffscreen().then(() => true) : hasOffscreen();
        ready
          .then((exists) => (exists ? browser.runtime.sendMessage(forward) : undefined))
          .then(
            () => sendResponse({ ok: true }),
            (err: Error) => sendResponse({ ok: false, error: `Voice is unavailable: ${err.message}` }),
          );
        return true;
      }
      case 'mi:open-active-tab':
        browser.tabs.query({ active: true, currentWindow: true }).then(([tab]) => openOverlay(tab?.id));
        return false;
    }
    return false;
  });
});
