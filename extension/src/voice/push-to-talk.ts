// Push-to-talk speech input: microphone -> Gemini Live input transcription, with the browser's
// speech engine as fallback. Shell-agnostic: runs in the extension's offscreen document today,
// and as-is in an Electron renderer or a web page.
import { GoogleGenAI, Modality, type Session } from '@google/genai';
import type { VoiceTokenResponse } from '../api/types';
import type { VoiceEvent } from './types';

const DEFAULT_LIVE_MODEL = 'gemini-3.8-live';
const PCM_MIME = 'audio/pcm;rate=16000';
/** How long to wait for trailing transcription after the user lets go. */
const FINAL_QUIET_MS = 700;
const FINAL_MAX_MS = 3000;
/** Use the fallback engine if Gemini Live is not connected by then. */
const CONNECT_BUDGET_MS = 2500;

export interface PushToTalkOptions {
  /** Short-lived Gemini Live token from the backend; undefined when unavailable. */
  getToken: () => Promise<VoiceTokenResponse | undefined>;
  /** URL of public/pcm-worklet.js. */
  workletUrl: string;
  emit: (e: VoiceEvent) => void;
}

interface SpeechRecognitionLike {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  onresult: ((e: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void) | null;
  onerror: ((e: { error: string }) => void) | null;
  onend: (() => void) | null;
  start(): void;
  stop(): void;
  abort(): void;
}

interface Turn {
  stream: MediaStream;
  audio: AudioContext;
  session?: Session;
  sessionReady: Promise<Session | undefined>;
  recognition?: SpeechRecognitionLike;
  buffered: string[];
  transcript: string;
  lastTranscriptAt: number;
  finished: boolean;
  closed: boolean;
}

function toBase64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf);
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}

export class PushToTalk {
  private turn?: Turn;
  /** Set when the user lets go before the microphone finished starting. */
  private stopRequested = false;

  constructor(private readonly opts: PushToTalkOptions) {}

  async start(lang: string) {
    this.cancel();
    this.stopRequested = false;
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, channelCount: 1 },
      });
    } catch (err) {
      this.opts.emit({
        event: 'error',
        message: `Microphone not allowed (${(err as Error).name}). Open the Micro Intent popup and enable the microphone.`,
      });
      return;
    }

    const audio = new AudioContext({ sampleRate: 16000 });
    await audio.audioWorklet.addModule(this.opts.workletUrl);
    const worklet = new AudioWorkletNode(audio, 'pcm-worklet');
    audio.createMediaStreamSource(stream).connect(worklet);

    const t: Turn = {
      stream,
      audio,
      sessionReady: Promise.resolve(undefined),
      buffered: [],
      transcript: '',
      lastTranscriptAt: Date.now(),
      finished: false,
      closed: false,
    };
    this.turn = t;

    let lastLevelAt = 0;
    worklet.port.onmessage = (e: MessageEvent<{ pcm: ArrayBuffer; peak: number }>) => {
      if (t.closed) return;
      const now = Date.now();
      if (now - lastLevelAt > 60) {
        lastLevelAt = now;
        this.opts.emit({ event: 'level', level: Math.min(1, e.data.peak * 1.6) });
      }
      if (t.recognition) return;
      const data = toBase64(e.data.pcm);
      if (t.session) t.session.sendRealtimeInput({ audio: { data, mimeType: PCM_MIME } });
      else t.buffered.push(data);
    };

    t.sessionReady = this.connectLive(t, lang).catch((err: Error) => {
      console.warn('[micro-intent] Gemini Live connect failed', err);
      return undefined;
    });

    if (this.stopRequested) {
      void this.stop();
      return;
    }

    const session = await Promise.race([
      t.sessionReady,
      new Promise<'slow'>((r) => setTimeout(() => r('slow'), CONNECT_BUDGET_MS)),
    ]);
    if (t.closed) return;
    if (session) this.opts.emit({ event: 'started', engine: 'gemini-live' });
    else if (this.startWebSpeech(t, lang)) this.opts.emit({ event: 'started', engine: 'web-speech' });
    else {
      this.opts.emit({ event: 'error', message: 'Voice is unavailable right now. Type your request instead.' });
      this.cancel();
    }
  }

  async stop() {
    const t = this.turn;
    if (!t) {
      this.stopRequested = true;
      return;
    }
    if (t.closed) return;
    this.release(t);
    if (t.recognition) t.recognition.stop();
    else (await t.sessionReady)?.sendRealtimeInput({ activityEnd: {} });
    t.lastTranscriptAt = Date.now();
    if (t.session || t.recognition) await this.waitForFinal(t);
    if (this.turn !== t) return;
    t.closed = true;
    t.session?.close();
    this.turn = undefined;
    this.opts.emit({ event: 'final', text: t.transcript.trim() });
  }

  cancel() {
    this.stopRequested = true;
    const t = this.turn;
    if (!t) return;
    t.closed = true;
    this.release(t);
    t.recognition?.abort();
    t.sessionReady.then((s) => s?.close()).catch(() => {});
    this.turn = undefined;
  }

  private async connectLive(t: Turn, lang: string): Promise<Session | undefined> {
    const token = await this.opts.getToken();
    if (!token?.token || t.closed) return undefined;
    const ai = new GoogleGenAI({ apiKey: token.token, httpOptions: { apiVersion: token.api_version ?? 'v1alpha' } });
    const session = await ai.live.connect({
      model: token.model || DEFAULT_LIVE_MODEL,
      config: {
        responseModalities: [Modality.TEXT],
        inputAudioTranscription: {},
        realtimeInputConfig: { automaticActivityDetection: { disabled: true } },
        systemInstruction: `Only transcribe what the user says (language: ${lang}). Do not reply.`,
      },
      callbacks: {
        onmessage: (msg) => {
          const tr = msg.serverContent?.inputTranscription;
          if (!tr || t.closed) return;
          if (tr.text) {
            t.transcript += tr.text;
            t.lastTranscriptAt = Date.now();
            this.opts.emit({ event: 'transcript', text: t.transcript.trim() });
          }
          if (tr.finished) t.finished = true;
        },
        onerror: (e) => console.warn('[micro-intent] Gemini Live error', e),
      },
    });
    if (t.closed) {
      session.close();
      return undefined;
    }
    session.sendRealtimeInput({ activityStart: {} });
    for (const data of t.buffered) session.sendRealtimeInput({ audio: { data, mimeType: PCM_MIME } });
    t.buffered = [];
    t.session = session;
    return session;
  }

  private startWebSpeech(t: Turn, lang: string): boolean {
    const Ctor = (globalThis as unknown as { webkitSpeechRecognition?: new () => SpeechRecognitionLike })
      .webkitSpeechRecognition;
    if (!Ctor) return false;
    const rec = new Ctor();
    rec.lang = lang === 'de' ? 'de-CH' : 'en-GB';
    rec.continuous = true;
    rec.interimResults = true;
    rec.onresult = (e) => {
      let text = '';
      for (let i = 0; i < e.results.length; i++) text += e.results[i]?.[0]?.transcript ?? '';
      t.transcript = text;
      t.lastTranscriptAt = Date.now();
      this.opts.emit({ event: 'transcript', text: text.trim() });
    };
    rec.onerror = (e) => console.warn('[micro-intent] web speech error', e.error);
    rec.onend = () => {
      t.finished = true;
    };
    try {
      rec.start();
    } catch {
      return false;
    }
    t.recognition = rec;
    return true;
  }

  private release(t: Turn) {
    t.stream.getTracks().forEach((track) => track.stop());
    t.audio.close().catch(() => {});
  }

  private async waitForFinal(t: Turn) {
    const started = Date.now();
    while (Date.now() - started < FINAL_MAX_MS) {
      if (t.finished) return;
      if (t.transcript && Date.now() - t.lastTranscriptAt > FINAL_QUIET_MS) return;
      await new Promise((r) => setTimeout(r, 80));
    }
  }
}
