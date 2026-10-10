// The Chrome extension's implementation of the overlay Host (src/ui/host.ts). Runs inside the
// overlay iframe: talks to the content script over a private MessageChannel and to the background
// worker over runtime messaging.
import type { ActionResponse, ApiResult, IntentRequest, StreamEvent, Turn } from '../src/api/types';
import type { Host, Target, UiSettings } from '../src/ui/host';
import type { VoiceEvent, VoiceInput } from '../src/voice/types';
import type { FromFrame, PortHandoff, ToFrame } from './frame-protocol';
import { STREAM_PORT, type ApiCall, type StreamPortMessage, type ToBackground, type VoiceBroadcast } from './messages';
import { getSettings, updateSettings, watchSettings } from './settings';

async function api<T>(call: ApiCall): Promise<ApiResult<T>> {
  try {
    const msg: ToBackground = { type: 'mi:api', call };
    const res = (await browser.runtime.sendMessage(msg)) as ApiResult<T> | undefined;
    return res ?? { ok: false, error: 'The extension background did not answer.' };
  } catch (err) {
    return { ok: false, error: (err as Error).message };
  }
}

/** `/intent/stream` over a runtime port; the worker forwards the server-sent events. */
function intentStream(req: IntentRequest, onEvent: (e: StreamEvent) => void): Promise<ApiResult<Turn>> {
  return new Promise((resolve) => {
    const port = browser.runtime.connect({ name: STREAM_PORT });
    let turn: Turn | undefined;
    let settled = false;
    const finish = (r: ApiResult<Turn>) => {
      if (settled) return;
      settled = true;
      port.disconnect();
      resolve(r);
    };
    port.onMessage.addListener((raw: unknown) => {
      const msg = raw as StreamPortMessage;
      if (msg.kind === 'event') {
        if (msg.event.event === 'turn') turn = msg.event.data;
        else onEvent(msg.event);
      } else if (msg.kind === 'done') {
        finish(turn ? { ok: true, data: turn, mocked: msg.mocked } : { ok: false, error: 'The backend sent no answer.' });
      } else finish({ ok: false, error: msg.error });
    });
    port.onDisconnect.addListener(() => finish({ ok: false, error: 'The extension background stopped.' }));
    port.postMessage(req);
  });
}

function createVoice(): VoiceInput {
  const owner = crypto.randomUUID();
  const listeners = new Set<(e: VoiceEvent) => void>();
  browser.runtime.onMessage.addListener((raw: unknown) => {
    const msg = raw as VoiceBroadcast;
    if (msg?.type !== 'mi:voice-event' || msg.owner !== owner) return;
    const { type: _t, owner: _o, ...event } = msg;
    listeners.forEach((fn) => fn(event as VoiceEvent));
  });
  const send = async (action: 'start' | 'stop' | 'cancel', lang?: string) => {
    const msg: ToBackground = { type: 'mi:voice', action, owner, lang };
    const res = (await browser.runtime.sendMessage(msg)) as { ok: boolean; error?: string } | undefined;
    if (res && !res.ok) throw new Error(res.error ?? 'Voice is unavailable.');
  };
  return {
    start: (lang) => send('start', lang),
    stop: () => send('stop'),
    cancel: () => send('cancel').catch(() => {}),
    subscribe: (fn) => {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
  };
}

function createFrameChannel() {
  const nonce = location.hash.slice(1);
  let port: MessagePort | undefined;
  const openers = new Set<(t: Target) => void>();
  const hiders = new Set<() => void>();
  const ptt = new Set<(down: boolean) => void>();
  const pending: FromFrame[] = [];

  const post = (msg: FromFrame) => (port ? port.postMessage(msg) : pending.push(msg));

  window.addEventListener('message', (e: MessageEvent<PortHandoff>) => {
    if (port || e.data?.mi !== 'port' || !nonce || e.data.nonce !== nonce || !e.ports[0]) return;
    port = e.ports[0];
    port.onmessage = (ev: MessageEvent<ToFrame>) => {
      const msg = ev.data;
      if (msg.mi === 'open') openers.forEach((fn) => fn(msg.target));
      else if (msg.mi === 'hidden') hiders.forEach((fn) => fn());
      else if (msg.mi === 'ptt') ptt.forEach((fn) => fn(msg.down));
    };
    port.postMessage({ mi: 'ready' } satisfies FromFrame);
    pending.splice(0).forEach((m) => port!.postMessage(m));
  });

  const sub = <T,>(set: Set<T>, fn: T) => {
    set.add(fn);
    return () => void set.delete(fn);
  };

  return {
    post,
    onOpen: (fn: (t: Target) => void) => sub(openers, fn),
    onHide: (fn: () => void) => sub(hiders, fn),
    onPushToTalk: (fn: (down: boolean) => void) => sub(ptt, fn),
  };
}

export function createExtensionHost(): Host {
  const frame = createFrameChannel();
  const pickUi = (s: UiSettings): UiSettings => ({ largeMode: s.largeMode, readAloud: s.readAloud, lang: s.lang });
  return {
    backend: {
      intent: intentStream,
      action: (body) => api<ActionResponse>({ op: 'action', body }),
    },
    voice: createVoice(),
    settings: {
      get: async () => pickUi(await getSettings()),
      update: async (patch) => {
        const next = await updateSettings(patch);
        // The profile switch lives in the backend profile too, so cards come back in large mode.
        if (patch.largeMode !== undefined || patch.lang !== undefined) {
          void api({ op: 'profile', body: { large_mode: next.largeMode, locale: next.lang } });
        }
        return pickUi(next);
      },
      watch: (fn) => watchSettings((s) => fn(pickUi(s))),
    },
    shell: {
      onOpen: frame.onOpen,
      onHide: frame.onHide,
      onPushToTalk: frame.onPushToTalk,
      close: () => frame.post({ mi: 'close' }),
      layout: (layout) => frame.post({ mi: 'layout', layout }),
      drag: (dx, dy) => frame.post({ mi: 'drag', dx, dy }),
      openUrl: (url) => void browser.tabs.create({ url }),
      openSettings: () => void browser.runtime.openOptionsPage?.(),
    },
  };
}
