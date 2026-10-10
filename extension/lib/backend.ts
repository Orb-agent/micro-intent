// Backend client per docs/API.md. Runs in the background worker only, so page CSP, CORS and
// mixed-content rules never apply.
import type { ApiResult, IntentRequest, StreamEvent, Turn } from '../src/api/types';
import type { ApiCall } from './messages';
import { mockAction, mockIntent } from './mock';
import { getSettings } from './settings';

const TIMEOUT_MS = 45_000;

class NetworkError extends Error {}

async function request(base: string, method: 'GET' | 'POST' | 'PUT', path: string, body?: unknown) {
  const url = base.replace(/\/+$/, '') + path;
  let res: Response;
  try {
    res = await fetch(url, {
      method,
      headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (err) {
    throw new NetworkError(`Backend unreachable at ${base} (${(err as Error).message})`);
  }
  const text = await res.text();
  let data: unknown;
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { detail: text };
  }
  // /action answers 404 with a status body for unknown ids; pass that through.
  if (!res.ok && !(res.status === 404 && path === '/action')) {
    const detail = (data as { detail?: unknown }).detail;
    throw new Error(`Backend ${res.status}: ${typeof detail === 'string' ? detail : res.statusText}`);
  }
  return data;
}

function live(base: string, call: ApiCall): Promise<unknown> {
  switch (call.op) {
    case 'intent':
      return request(base, 'POST', '/intent', call.body);
    case 'action':
      return request(base, 'POST', '/action', call.body);
    case 'voice-token':
      return request(base, 'POST', '/voice/token', call.body);
    case 'profile':
      return request(base, 'PUT', '/profile', call.body);
    case 'health':
      return request(base, 'GET', '/health');
    case 'demo-reset':
      return request(base, 'POST', '/demo/reset', {});
  }
}

async function mock(call: ApiCall): Promise<unknown> {
  switch (call.op) {
    case 'intent':
      return mockIntent(call.body);
    case 'action':
      return mockAction(call.body);
    case 'voice-token':
      throw new Error('No Gemini Live token from the mock backend');
    case 'profile':
      return call.body;
    case 'health':
      return { ok: true, mock: true };
    case 'demo-reset':
      return { ok: true };
  }
}

export async function callBackend(call: ApiCall): Promise<ApiResult<unknown>> {
  const settings = await getSettings();
  try {
    if (settings.backendMode === 'mock') return { ok: true, data: await mock(call), mocked: true };
    try {
      return { ok: true, data: await live(settings.backendUrl, call), mocked: false };
    } catch (err) {
      if (settings.backendMode === 'auto' && err instanceof NetworkError) {
        console.warn('[micro-intent] falling back to mock:', err.message);
        return { ok: true, data: await mock(call), mocked: true };
      }
      throw err;
    }
  } catch (err) {
    return { ok: false, error: (err as Error).message };
  }
}

// ---- /intent/stream ------------------------------------------------------------------------

function parseSse(block: string): StreamEvent | undefined {
  let event = 'message';
  const data: string[] = [];
  for (const line of block.split('\n')) {
    if (line.startsWith('event:')) event = line.slice(6).trim();
    else if (line.startsWith('data:')) data.push(line.slice(5).trimStart());
  }
  if (!data.length) return undefined;
  try {
    return { event, data: JSON.parse(data.join('\n')) } as StreamEvent;
  } catch {
    return undefined;
  }
}

async function streamLive(base: string, req: IntentRequest, emit: (e: StreamEvent) => void): Promise<void> {
  const url = `${base.replace(/\/+$/, '')}/intent/stream`;
  let res: Response;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream' },
      body: JSON.stringify(req),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (err) {
    throw new NetworkError(`Backend unreachable at ${base} (${(err as Error).message})`);
  }
  if (res.status === 404) {
    // Older backend without streaming: one plain turn.
    emit({ event: 'turn', data: (await request(base, 'POST', '/intent', req)) as Turn });
    return;
  }
  if (!res.ok || !res.body) throw new Error(`Backend ${res.status}: ${res.statusText}`);
  const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
  let buf = '';
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += value.replace(/\r\n/g, '\n');
    let i: number;
    while ((i = buf.indexOf('\n\n')) >= 0) {
      const e = parseSse(buf.slice(0, i));
      buf = buf.slice(i + 2);
      if (e) emit(e);
    }
  }
  const tail = parseSse(buf);
  if (tail) emit(tail);
}

async function streamMock(req: IntentRequest, emit: (e: StreamEvent) => void) {
  emit({ event: 'orb', data: { state: 'thinking' } });
  emit({ event: 'filler', data: { say: 'Checking your calendar and trains…' } });
  emit({ event: 'orb', data: { state: 'searching' } });
  emit({ event: 'turn', data: await mockIntent(req) });
}

/** Streams one intent turn. Resolves with whether the mock answered. */
export async function streamIntent(req: IntentRequest, emit: (e: StreamEvent) => void): Promise<{ mocked: boolean }> {
  const settings = await getSettings();
  if (settings.backendMode === 'mock') {
    await streamMock(req, emit);
    return { mocked: true };
  }
  try {
    await streamLive(settings.backendUrl, req, emit);
    return { mocked: false };
  } catch (err) {
    if (settings.backendMode === 'auto' && err instanceof NetworkError) {
      console.warn('[micro-intent] falling back to mock:', err.message);
      await streamMock(req, emit);
      return { mocked: true };
    }
    throw err;
  }
}
