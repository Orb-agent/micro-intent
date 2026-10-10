# Micro Intent for Chrome

Development extension for event pages on `lu.ma` and `luma.com`. It reads public event details from the page, lets you fill in missing information, and asks your configured planner API for a plan. The extension never creates or edits calendar events.

## Install in Chrome

1. Start the Micro Intent app and its local API. The defaults are app `http://localhost:5173` and planner API `http://localhost:3001`.
2. Open `chrome://extensions`.
3. Turn on **Developer mode**.
4. Select **Load unpacked** and choose this `extension` folder.
5. Open the toolbar popup, confirm the app and API URLs, and select **Save URLs and grant API access**. This grants the API host permission explicitly.
6. Open an event page on `lu.ma` or `luma.com`. Click the green orb in the lower-right corner to edit the details and request a plan.

For a visual fixture without installing the extension, run `npm run dev` and open `http://localhost:5173/extension/preview.html`. The fixture is explicitly demo-only and uses a local Chrome API stub; it does not access an account or calendar.

The Chrome toolbar button works on any tab. Use it to enable or disable the orb on Luma pages, or open the app. The setting also applies to Luma pages that are already open.

To configure a deployment, enter the app and API origin URLs in the popup and select **Save URLs and grant API access**. HTTPS is required for non-local hosts; plain HTTP is accepted only for `localhost` and `127.0.0.1`. Saving requests an optional permission for the selected API host and removes a previously granted API host when you switch. The app URL is used to open the web app with the extracted event context.

The panel's results and links come from the configured `/api/plan` endpoint. If the API is unavailable, the panel reports the error instead of substituting sample results. The extension does not pass a Google OAuth token, so its planner response is demo mode. For live Google Calendar conflicts or to add an event, open the app and connect Google Calendar there; the extension itself never writes to a calendar.

Voice input uses the Web Speech API in English (`en-US`) when the browser supports it. The extension reports when voice input is unavailable or fails. The Chrome extension does not run in Chrome for mobile; use the Micro Intent PWA on mobile.
