// Everything the overlay needs from its shell. The Chrome extension implements it in
// lib/extension-host.ts; an Electron app or a web page can implement the same interface.
import type { ActionMessage, ActionResponse, ApiResult, IntentRequest, PageContext, StreamEvent, Turn } from '../api/types';
import type { VoiceInput } from '../voice/types';

export interface UiSettings {
  largeMode: boolean;
  readAloud: boolean;
  lang: 'en' | 'de';
}

/** What the user is pointing at, as the shell captured it. */
export interface Target {
  context: PageContext;
  /** Short human label, e.g. "Selection" or "Looking at". */
  source: 'selection' | 'gaze' | 'pointer' | 'page';
  /** One-line preview of the target text. */
  snippet: string;
}

export interface OverlayLayout {
  width: number;
  height: number;
  /** Glass shapes in overlay coordinates, so a shell can blur what is behind them. */
  shapes: { x: number; y: number; w: number; h: number; r: number }[];
}

export interface Host {
  backend: {
    /** `/intent/stream`: reports orb states and the filler line, resolves with the turn. */
    intent(req: IntentRequest, onEvent: (e: StreamEvent) => void): Promise<ApiResult<Turn>>;
    /** `/action`: the human checkpoint. */
    action(msg: ActionMessage): Promise<ApiResult<ActionResponse>>;
  };
  voice: VoiceInput;
  settings: {
    get(): Promise<UiSettings>;
    update(patch: Partial<UiSettings>): Promise<UiSettings>;
    watch(fn: (s: UiSettings) => void): () => void;
  };
  shell: {
    /** Called when the shell wants the overlay for a new target (selection, gaze, shortcut). */
    onOpen(fn: (target: Target) => void): () => void;
    /** The shell hid the overlay (e.g. Escape on the page); drop any running turn. */
    onHide(fn: () => void): () => void;
    /** Push-to-talk key from the page (the overlay may not have focus). */
    onPushToTalk(fn: (down: boolean) => void): () => void;
    close(): void;
    layout(l: OverlayLayout): void;
    /** Moves the overlay by a drag delta. */
    drag(dx: number, dy: number): void;
    openUrl(url: string): void;
    /** Opens the shell's settings (backend URL, microphone permission). */
    openSettings?(): void;
  };
}
