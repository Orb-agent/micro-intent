// One interface for push-to-talk voice input, so Gemini Live, Gradium or the browser's
// speech engine can be swapped without touching the overlay.

export type VoiceEngine = 'gemini-live' | 'web-speech' | 'gradium';

export type VoiceEvent =
  | { event: 'started'; engine: VoiceEngine }
  | { event: 'level'; level: number }
  | { event: 'transcript'; text: string }
  | { event: 'final'; text: string }
  | { event: 'error'; message: string };

export interface VoiceInput {
  /** Starts listening (push-to-talk pressed). Events arrive through `subscribe`. */
  start(lang: string): Promise<void>;
  /** Push-to-talk released: finish the transcript and emit `final`. */
  stop(): Promise<void>;
  /** Drop the turn without a `final`. */
  cancel(): Promise<void>;
  subscribe(listener: (e: VoiceEvent) => void): () => void;
}
