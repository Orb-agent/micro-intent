# Orbs Chrome extension

The extension includes the same desktop interface and connects it to the same backend `/ws` service. It provides typed questions, push-to-talk, hands-free voice, spoken replies, screen sharing, and cards in a dedicated Chrome tab.

## Install locally

1. Start the backend as described in [backend/README.md](../backend/README.md). Its desktop UI is served at `http://localhost:8000/`.
2. Open `chrome://extensions`, enable **Developer mode**, and choose **Load unpacked**.
3. From this directory, run `npm ci` and `npm run build`. Select the resulting `extension/dist` directory. A2UI is bundled locally because Manifest V3 prohibits remotely hosted scripts.
4. Start the backend; the extension loads `APP_TOKEN` and `BACKEND_URL` from the backend environment automatically.
5. Choose **Open assistant**. Allow microphone and screen-sharing access in the Orbs tab when prompted.
6. The floating orb appears automatically on websites after Chrome grants the extension site access.

## Generated UI on other tabs

When an agent reply contains a calendar `clash` or `tight` card, the floating orb expands to show a small A2UI notice above it on the active website, including `lu.ma` and `luma.com`. Replies from either the full extension assistant or the backend web assistant are routed to that website. Switching to another website keeps the current warning available; dismissing it closes it across tabs and prevents the same warning from reopening until the plan changes. Ordinary replies keep the orb compact. This reacts to agent replies; it does not read Luma pages automatically.

After updating, rebuild the package, reload Orbs at `chrome://extensions`, and reload the Luma tab so Chrome injects the new content script. Chrome internal pages and pages without extension site access do not support the overlay. The Codex in-app preview does not install Chrome extensions.

Card data is sent directly between extension contexts and stays inside a cross-origin extension iframe. The parent website receives only the expanded/collapsed layout signal. Only the configured backend root and the extension client may publish notices; arbitrary website messages are ignored.

Checks: `npm test` runs fixture routing, dismissal and origin-validation tests; `npm run build` produces the unpacked Chrome package without external JavaScript imports.

Set `BACKEND_URL` in the repo-root `.env` (or `backend/.env`) to the backend's HTTP(S) origin. The local extension bootstraps from `http://localhost:8000`; for a remote deployment, package the extension with that bootstrap origin. The app token is fetched into memory from `/extension-config`, never displayed or saved in extension storage.

Chrome asks for access to websites when the extension is installed because automatic injection requires site access. Select **Click to talk** to tap once to start speaking and again to send, or **Hands-free listening** to tap to start and pause continuous listening. Its animation reflects the assistant state. **Open assistant** remains available for the full text, voice, cards and screen-sharing interface.
