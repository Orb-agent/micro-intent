# Backend

FastAPI server for the voice agent: `/ws` for the app, `POST /screenshot` for the Shortcut, Gradium voice, Gemini vision. Interfaces: [docs/contracts.md](../docs/contracts.md).

## Run it

Keys go in `backend/.env` or the repo-root `.env` (see `.env.example`): `APP_TOKEN`, `GEMINI_API_KEY`, `GRADIUM_API_KEY`.

```bash
cd backend
uv run uvicorn app:app --port 8000
```

The agent is WP3's `agent.py` when it exists, else the prototype `dev_agent.py`. Set `MOCK_AGENT=1` for the fixed demo reply.

## Try it on a Mac

Open the prototype client in desktop Chrome, with your token in the URL fragment (it's stored, then removed from the address bar):

```bash
open -a "Google Chrome" "http://localhost:8000/#token=$(grep '^APP_TOKEN=' .env | cut -d= -f2-)"
```

1. Click the orb once to allow the mic.
2. Click **Share screen** and pick a screen or window. A frame goes with each question, and the server reads it with Gemini.
3. Hold the orb or Space while you talk. Click or press again to interrupt the beaver.
4. **Hands-free** in the menu: just talk; talking over the beaver interrupts it. Use headphones, or it hears itself.

## Checks

```bash
uv run pytest -q
uv run python fake_app.py --text "Can I make it?"   # stands in for the app
uv run python vision.py fixtures/screen.png
```
