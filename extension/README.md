# extension

Chrome extension: captures what the user looks at or selects, records the spoken intent, and renders the A2UI cards returned by the backend.
Built against [`../docs/API.md`](../docs/API.md) (contract v2, A2UI v0.9.1, `respond(say, cards)`).

WXT + React + TypeScript, Manifest V3.

## Run it

```sh
cd extension
npm install
npm run build        # -> .output/chrome-mv3
npm run dev          # WXT dev mode with reload
```

Load `.output/chrome-mv3` via `chrome://extensions` -> Developer mode -> Load unpacked.

Open the extension popup once and click **Enable microphone** so push-to-talk can use the mic.

The backend URL defaults to `http://localhost:8080` and is set in the popup (Cloud Run later).
The mode switch there picks **Auto** (backend, local mock if it is unreachable), **Backend only** or **Mock**.
The popup also has **Reset demo**, which calls `POST /demo/reset`.

## Using it

- Select text on any page: a small launcher appears next to it. Click it, or press `Alt+Shift+M`, or use the context menu "Ask Micro Intent".
- Hold the orb (or hold `Option`/`Alt`) and speak, release to send. Typing in the input row always works.
- Intent chips: "Am I free?", "How do I get there?", "Add to calendar", "Remind me".
- Every write action shows a "Needs your OK" checkpoint with a preview. Nothing changes until the user confirms.
- Options menu (`...`): Large mode (bigger text and buttons, reads answers aloud), Read answers aloud, Deutsch. Settings sync to `PUT /profile`.

## Architecture

- `entrypoints/content.ts` captures context (selection, gaze target, element under the pointer, page) and hosts the overlay.
  The overlay is an extension iframe (`overlay.html`) inside a closed shadow root.
  The page side draws the glass blur and shadow behind it, sized from shapes the overlay reports.
  Content and overlay talk over a private `MessageChannel`, handed over with a nonce, so page scripts cannot read or fake it.
- `entrypoints/background.ts` proxies every backend call (no CORS or mixed content issues), relays `/intent/stream` SSE events over a runtime port, and falls back to `lib/mock.ts` in Auto mode.
- `entrypoints/offscreen/` owns the microphone and the Gemini Live session.
- `src/ui/OverlayApp.tsx` is the overlay UI.
  It only depends on the `Host` interface in `src/ui/host.ts` (backend, voice, settings, shell), so it can run in another shell (Electron, web page) with a different `Host`.
  The extension implementation is `lib/extension-host.ts`.

## Cards (A2UI)

`src/ui/a2ui/catalog.tsx` is the trusted client catalog `https://micro-intent.app/a2ui/catalog/v1`: `Orb`, `EventCard`, `ConflictCard`, `TrainCard`, `ReminderCard`, `MessageDraftCard`, `ConfirmCard`.
Props follow docs/API.md.
Messages go through `@a2ui/web_core` (`MessageProcessor`) and render with `@a2ui/react`.
Server events (`confirm`, `reject`, `skip`, `keep`) are posted to `/action`; a `confirm` from a card first opens the checkpoint sheet.
`functionCall: openUrl` opens a new tab.
After a successful action the overlay adds a local done card, with the `message_sent.deep_link` when there is one.

Page content is untrusted: it is only sent as context, never rendered as markup.

## Voice

`src/voice/push-to-talk.ts` implements the `VoiceInput` interface from `src/voice/types.ts`.
It streams 16 kHz PCM to Gemini Live (`gemini-3.8-live`, input transcription only) with an ephemeral token from `POST /voice/token`.
There is no API key in the extension.
Without a token (or if Live does not connect within 2.5 s) it falls back to the browser's speech recognition.
The live transcript shows in the panel while the user holds the orb.

## Eye tracking interface

The eye-tracking module only has to say which element the user looks at:

```ts
// In the content script:
import { setGazeTarget } from './lib/capture';
setGazeTarget(element, dwellMs);
```

```js
// From any other world (page script, another extension):
element.dispatchEvent(
  new CustomEvent('micro-intent:gaze', { bubbles: true, composed: true, detail: { dwellMs: 900 } }),
);
```

The launcher then appears next to that element, and the next intent sends it as `context.gaze`.

## Sharp edges

- The overlay document must keep `color-scheme: normal` (same as the iframe element), or Chrome paints the frame opaque.
- The iframe cannot blur the page or draw shadows past its edge, so `content.ts` draws both on page-side `.glass` layers.
- Gemini Live (`gemini-3.8-live`) rejects TEXT-only responses; the session asks for AUDIO and only reads `inputTranscription`.
- Recent Chrome stable ignores `--load-extension`; for automated runs launch Chrome with puppeteer's `enableExtensions` (pipe mode).
