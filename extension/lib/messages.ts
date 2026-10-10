// Runtime messages between the overlay frame, background worker and offscreen voice document.
import type { ActionMessage, IntentRequest, Profile, StreamEvent } from '../src/api/types';
import type { VoiceEvent } from '../src/voice/types';

export type ApiCall =
  | { op: 'intent'; body: IntentRequest }
  | { op: 'action'; body: ActionMessage }
  | { op: 'voice-token'; body: { locale?: string } }
  | { op: 'profile'; body: Partial<Profile> }
  | { op: 'health' }
  | { op: 'demo-reset' };

/** To the background worker. `owner` identifies the overlay frame that runs the voice turn. */
export type ToBackground =
  | { type: 'mi:api'; call: ApiCall }
  | { type: 'mi:voice'; action: 'start' | 'stop' | 'cancel'; owner: string; lang?: string }
  | { type: 'mi:open-active-tab' };

export type ToOffscreen = {
  target: 'offscreen';
  action: 'start' | 'stop' | 'cancel';
  owner: string;
  lang?: string;
};

/** Offscreen -> every extension page; overlays keep only their own `owner`. */
export type VoiceBroadcast = { type: 'mi:voice-event'; owner: string } & VoiceEvent;

/** Background -> content script. */
export type ToContent = { type: 'mi:open' };

/** Port name for `/intent/stream`: the frame posts the request, the worker posts events back. */
export const STREAM_PORT = 'mi:intent-stream';

export type StreamPortMessage =
  | { kind: 'event'; event: StreamEvent }
  | { kind: 'done'; mocked: boolean }
  | { kind: 'error'; error: string };
