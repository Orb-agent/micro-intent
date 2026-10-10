# Orbs Chrome extension

The extension includes the same desktop interface and connects it to the same backend `/ws` service. It provides typed questions, push-to-talk, hands-free voice, spoken replies, screen sharing, and cards in a dedicated Chrome tab.

## Install locally

1. Start the backend as described in [backend/README.md](../backend/README.md). Its desktop UI is served at `http://localhost:8000/`.
2. Open `chrome://extensions`, enable **Developer mode**, and choose **Load unpacked**.
3. Select this `extension` directory.
4. Start the backend; the extension loads `APP_TOKEN` and `BACKEND_URL` from the backend environment automatically.
5. Choose **Open assistant**. Allow microphone and screen-sharing access in the Orbs tab when prompted.
6. The floating orb appears automatically on websites after Chrome grants the extension site access.

Set `BACKEND_URL` in the repo-root `.env` (or `backend/.env`) to the backend's HTTP(S) origin. The local extension bootstraps from `http://localhost:8000`; for a remote deployment, package the extension with that bootstrap origin. The app token is fetched into memory from `/extension-config`, never displayed or saved in extension storage.

Chrome asks for access to websites when the extension is installed because automatic injection requires site access. Select **Click to talk** to tap once to start speaking and again to send, or **Hands-free listening** to tap to start and pause continuous listening. Its animation reflects the assistant state. **Open assistant** remains available for the full text, voice, cards and screen-sharing interface.
