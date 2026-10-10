// Offscreen document: owns the microphone and the Gemini Live session for push-to-talk.
// It runs on the extension origin, so one microphone grant covers every site and no page sees audio.
import type { ApiResult, VoiceTokenResponse } from '@/src/api/types';
import { PushToTalk } from '@/src/voice/push-to-talk';
import type { ToBackground, ToOffscreen, VoiceBroadcast } from '@/lib/messages';

let owner = '';
let lang = 'en';

const ptt = new PushToTalk({
  workletUrl: browser.runtime.getURL('/pcm-worklet.js'),
  emit: (event) => {
    const msg = { type: 'mi:voice-event', owner, ...event } as VoiceBroadcast;
    browser.runtime.sendMessage(msg).catch(() => {});
  },
  getToken: async () => {
    const msg: ToBackground = { type: 'mi:api', call: { op: 'voice-token', body: { locale: lang } } };
    const res = (await browser.runtime.sendMessage(msg)) as ApiResult<VoiceTokenResponse> | undefined;
    return res?.ok && !res.mocked ? res.data : undefined;
  },
});

browser.runtime.onMessage.addListener((raw) => {
  const msg = raw as ToOffscreen;
  if (msg?.target !== 'offscreen') return false;
  if (msg.action === 'start') {
    owner = msg.owner;
    lang = msg.lang ?? 'en';
    void ptt.start(lang);
  } else if (msg.owner === owner) {
    if (msg.action === 'stop') void ptt.stop();
    else ptt.cancel();
  }
  return false;
});
