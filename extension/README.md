# Orbs Chrome extension

The extension includes the same desktop interface and connects it to the same backend `/ws` service. It provides typed questions, push-to-talk, hands-free voice, spoken replies, screen sharing, and cards in a dedicated Chrome tab.

## Install locally

1. Start the backend as described in [backend/README.md](../backend/README.md). Its desktop UI is served at `http://localhost:8000/`.
2. Open `chrome://extensions`, enable **Developer mode**, and choose **Load unpacked**.
3. Select this `extension` directory.
4. Open the Orbs toolbar popup, enter the backend URL and `APP_TOKEN` from `backend/.env`, then choose **Save and allow this server**.
5. Choose **Open assistant**. Allow microphone and screen-sharing access in the Orbs tab when prompted.

For a deployed backend, use its HTTPS origin. The popup requests host access only for the origin entered. The app token is stored in Chrome's local extension storage and is passed to the desktop page in the URL fragment; the desktop client removes the fragment after reading it.

The extension uses its toolbar popup for server settings and opens a full assistant tab. The tab keeps microphone capture and audio playback active while you work in other tabs.
