# Product demo video

`orb-agent-demo.mp4` is the 2:27 submission demo for the {Tech: Europe} Agentic AI Hack Zurich.
It opens with a LangEase-style kinetic intro ("Every agent today needs a prompt. Ours needs a glance."), then walks through Look, Ask, Answer, Confirm, Family, Desktop and Under the hood, and closes on the Orbs wordmark (the dash-ring mark from `backend/static/index.html`).

The source is a HyperFrames project in `video/`.
Edit `video/index.html`, preview with `npx hyperframes preview`, and render with `npx hyperframes render -o ../orb-agent-demo.mp4` from `video/`.

| Asset | Source |
| --- | --- |
| `video/assets/video/app-live-final.mp4` | Live iOS app recording against the real backend, trimmed; a mask hides the second card, which showed a wrong morning train |
| `video/assets/video/desktop-install.mp4`, `desktop-demo.mp4` | `plugin_install.mp4` and `demo-desktop` from the team Drive folder, trimmed and sped up |
| `video/assets/video/architecture.mp4` | `orbs-architecture-34s.mp4` from the captain, at 1.5x |
| `video/assets/screen-chat.png` | `backend/fixtures/screen.png`, the screenshot the agent reads |
| `video/assets/audio/vo-narrator.mp3` | ElevenLabs v3 narration (voice George) |
| `video/assets/audio/vo-user-train.wav` | Gemini 2.5 Pro TTS, the user's question |
| `video/assets/audio/music.mp3`, `sfx-*.mp3` | ElevenLabs Music v2 and SFX v2 |
| `video/assets/senior.png` | Nano Banana Pro still |
| `video/assets/fonts/` | Inter 4.1 (SIL OFL) |

The confirmation and family scenes show the product direction from the pitch; the app clip is the part that runs live today.
