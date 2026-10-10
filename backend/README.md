# Backend

FastAPI server for the voice agent: `/ws` for the app, `POST /screenshot` for the Shortcut, Gradium voice, Gemini vision. Interfaces: [docs/contracts.md](../docs/contracts.md).

## Run it

Keys go in `backend/.env` or the repo-root `.env` (see `.env.example`): `APP_TOKEN`, `GEMINI_API_KEY`, `GRADIUM_API_KEY`.

```bash
cd backend
uv run uvicorn app:app --port 8000
```

The agent is WP3's `agent.py` when it exists, else the prototype `dev_agent.py`. Set `MOCK_AGENT=1` for the fixed demo reply.

## Desktop and Chrome

The Orbs desktop client at `/` supports typed questions, push-to-talk, hands-free voice, spoken replies, screen sharing, and cards. Launch it in desktop Chrome with the token in the URL fragment (the client stores it locally, then removes it from the address bar):

```bash
open -a "Google Chrome" "http://localhost:8000/#token=$(grep '^APP_TOKEN=' .env | cut -d= -f2-)"
```

1. Click the orb once to allow the microphone.
2. Click **Share screen** and pick a screen or window. A frame goes with each question, and the server reads it with Gemini.
3. Hold the orb or Space while you talk. Click or press again to interrupt the beaver. You can also type a question and select **Send**.
4. Select **Hands-free** in the menu to talk without holding the orb. Talking over the beaver interrupts it. Use headphones to prevent feedback.

To use the Chrome toolbar extension, load the repository's `extension/` directory from `chrome://extensions` with Developer mode on. Enter the backend origin and `APP_TOKEN` in the popup, grant access to that server, and select **Open assistant**. The extension opens this same desktop UI in a tab, so voice and text use the same client and `/ws` session.

## Checks

```bash
uv run pytest -q
uv run python fake_app.py --text "Can I make it?"   # stands in for the app
uv run python vision.py fixtures/screen.png
```
