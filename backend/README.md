# Backend

FastAPI server for the voice agent: `/ws` for the app, `POST /screenshot` for the Shortcut, Gradium voice, Gemini vision. Interfaces: [docs/contracts.md](../docs/contracts.md).

## Run it

Keys go in `backend/.env` or the repo-root `.env` (see `backend/.env.example`). Set `BACKEND_URL` to the backend's HTTP(S) origin; `APP_TOKEN` is loaded automatically by the desktop UI and Chrome extension through `/extension-config` and is never displayed in their settings.

```bash
cd backend
uv run uvicorn app:app --port 8000
```

The agent is WP3's `agent.py` when it exists, else the prototype `dev_agent.py`. Set `MOCK_AGENT=1` for the fixed demo reply.

## Desktop and Chrome

The Orbs desktop client at `/` supports typed questions, push-to-talk, hands-free voice, spoken replies, screen sharing, and cards. It loads its runtime configuration directly from the backend:

```bash
open -a "Google Chrome" "http://localhost:8000/"
```

1. Click the orb once to allow the microphone.
2. Click **Share screen** and pick a screen or window. A frame goes with each question, and the server reads it with Gemini.
3. Hold the orb or Space while you talk. Click or press again to interrupt the beaver. You can also type a question and select **Send**.
4. Select **Hands-free** in the menu to talk without holding the orb. Talking over the beaver interrupts it. Use headphones to prevent feedback.

To use the Chrome toolbar extension, load the repository's `extension/` directory from `chrome://extensions` with Developer mode on, then choose **Open assistant**. The extension reads `APP_TOKEN` and `BACKEND_URL` through `/extension-config`; no token or server URL needs to be entered in Chrome.

## Checks

```bash
uv run pytest -q
uv run python fake_app.py --text "Can I make it?"   # stands in for the app
uv run python vision.py fixtures/screen.png
```
