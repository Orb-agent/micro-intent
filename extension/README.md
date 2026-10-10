# Orbs Chrome extension

The extension includes the same desktop interface and connects it to the same backend `/ws` service. It provides typed questions, push-to-talk, hands-free voice, spoken replies, screen sharing, and cards in a dedicated Chrome tab.

## Install locally

1. Start the backend as described in [backend/README.md](../backend/README.md). Its desktop UI is served at `http://localhost:8000/`.
2. Open `chrome://extensions`, enable **Developer mode**, and choose **Load unpacked**.
3. Select this `extension` directory.
4. Open the Orbs toolbar popup, enter the backend URL and `APP_TOKEN` from `backend/.env`, then choose **Save and allow this server**.
5. Choose **Open assistant**. Allow microphone and screen-sharing access in the Orbs tab when prompted.
6. On a website where you want the floating orb, open the Orbs toolbar popup and choose **Add floating orb to this site**. Grant access to that site when Chrome asks.

For a deployed backend, use its HTTPS origin. The popup requests host access only for the origin entered. The app token is stored in Chrome's local extension storage and is passed to the desktop page in the URL fragment; the desktop client removes the fragment after reading it.

The floating orb stays at the bottom-right of enabled sites. Select **Click to talk** to tap once to start speaking and again to send, or **Hands-free listening** to tap to start and pause continuous listening. Its animation reflects the assistant state. Site access is requested one origin at a time. **Open assistant** remains available for the full text, voice, cards and screen-sharing interface.
