// Wire types from docs/API.md: every turn is `respond(say, cards)` with A2UI v0.9.1 cards.
import type { A2uiMessage } from '../ui/a2ui/protocol';

export interface ElementInfo {
  tag?: string;
  text?: string;
  selector?: string;
  attributes?: Record<string, string>;
}

export interface GazeInfo extends ElementInfo {
  x?: number;
  y?: number;
  dwell_ms?: number;
}

export interface PageContext {
  url: string;
  title: string;
  selection?: { text?: string; element?: ElementInfo };
  gaze?: GazeInfo;
  page_text?: string;
}

export interface IntentRequest {
  intent: string;
  context: PageContext;
  locale?: 'en' | 'de';
  now?: string;
}

/** One agent turn, from `/intent`, `/intent/stream` or `/action`. */
export interface Turn {
  turn_id: string;
  say: string;
  source: 'agent' | 'fallback';
  cards: A2uiMessage[];
}

/** `/intent/stream` server-sent events. */
export type StreamEvent =
  | { event: 'orb'; data: { state: 'thinking' | 'searching' } }
  | { event: 'filler'; data: { say: string } }
  | { event: 'turn'; data: Turn };

/** A2UI v0.9.1 client-to-server action message, the body of `POST /action`. */
export interface ActionMessage {
  version: 'v0.9.1';
  action: {
    name: string;
    surfaceId: string;
    sourceComponentId: string;
    timestamp: string;
    context: Record<string, unknown>;
  };
}

export interface ActionResponse extends Turn {
  action_id: string;
  status: 'done' | 'rejected' | 'failed' | 'already_done' | 'not_found';
  message?: string;
  result?: { message_sent?: { deep_link?: string }; [key: string]: unknown };
}

export interface VoiceTokenResponse {
  provider?: string;
  token: string;
  model: string;
  api_version?: string;
  expires_at?: string;
  new_session_expires_at?: string;
}

export interface Profile {
  name?: string;
  home?: string;
  large_mode?: boolean;
  locale?: 'en' | 'de';
  [key: string]: unknown;
}

/** Envelope the shell returns to the UI. `mocked` is true when the local mock answered. */
export type ApiResult<T> = { ok: true; data: T; mocked: boolean } | { ok: false; error: string };
