# Micro Intent

Micro Intent turns an event into a plan you can review: it checks calendar conflicts, prepares route links, and asks for confirmation before adding an event. Without OAuth, it runs in demo mode and never writes to Google Calendar.

## Requirements and development

You need Node.js and npm. From the project folder, run:

```powershell
npm install
npm run dev
```

Vite serves the web app at `http://localhost:5173/` and proxies `/api` to the backend at `http://localhost:3001/`. To build for production:

```powershell
npm run build
npm run preview
```

`npm run preview` serves the app at `http://localhost:4173/`. Start the backend separately in another terminal with `npm run dev:backend`. To use Calendar from Preview, also add `http://localhost:4173` as an authorized JavaScript origin for the OAuth client.

On Windows, start both processes hidden with `powershell -ExecutionPolicy Bypass -File .\scripts\start-micro-intent.ps1 -OpenApp`. The launcher checks whether the app is already running, avoids starting a duplicate, and waits up to 15 seconds for the web app and API to respond. The web app requires port 5173; the API uses port 3001. Free those ports if another app is using them. The launcher records its process under `.runtime/`; stop it with `powershell -ExecutionPolicy Bypass -File .\scripts\stop-micro-intent.ps1`. To create a desktop `.lnk` shortcut that starts the server and opens the app, run `powershell -ExecutionPolicy Bypass -File .\scripts\install-shortcut.ps1`.

## Connect Google Calendar

Follow the project-specific [OAuth setup guide](docs/OAUTH-SETUP.md). For a phone-accessible HTTPS deployment, use the [Google Cloud Run guide](docs/DEPLOYMENT.md).

1. In Google Cloud Console, create or select a project and enable **Google Calendar API**.
2. Configure the OAuth consent screen. For an external app in testing, add your account as a test user.
3. Create a **Web application** OAuth client ID and add this authorized JavaScript origin: `http://localhost:5173`. Google Identity Services uses a popup flow and does not require a redirect URI.
4. If you do not already have a `.env` file, copy `.env.example` to `.env`. If one already exists, preserve its contents and add or update only `GOOGLE_CLIENT_ID` with the client ID. Restart `npm run dev`.
5. In Micro Intent, open **Connections and preferences** and connect Calendar. The requested permission is `https://www.googleapis.com/auth/calendar.events`.

The integration reads from and creates events in the connected account's primary calendar; it does not let you choose another calendar. The OAuth token lives temporarily in the browser tab, is sent to the backend only when checking or adding an event, and is discarded when the tab closes or the session expires.

## Install as an app

In desktop Chrome, serve the production build or use localhost, then choose **Install Micro Intent** from the browser menu when the option appears. The service worker registers only in production builds. During installation, it caches the app shell and static site assets so the interface can open offline. It does not cache API responses, OAuth tokens, or context URLs. Calendar, route, and backend actions require a network connection.

To install on a phone, publish the web app at an HTTPS origin accessible from that phone, and make the API reachable from the same origin (for example, through an HTTPS proxy from `/api` to the backend). Set `APP_ORIGIN` in `.env` to the exact HTTPS web app origin, including the hostname, such as `https://micro.example.com`, so the backend allows that origin. On a phone, `localhost` refers to the phone itself, not the computer running this project. Chrome for mobile does not support this desktop extension; use the PWA instead.

## Scope and limitations

- The Chrome extension for Luma event pages is installed from `extension/` and works only in desktop Chrome. It selects context with hover and touch. Experimental gaze estimation belongs to the web app and is not shared with the extension.
- Voice input dictates a short intent to the browser. The plan can be read aloud in English on demand; continuous conversational voice is not implemented.
- The cards take visual inspiration from A2UI, but this app does not implement or claim conformance with the A2UI protocol.
- The optional small model summarizes facts returned by the planner. If it is not configured or fails, Micro Intent uses a deterministic summary.
- Maps, SBB, and flight results are links for continuing a search. The app does not query real-time availability, prices, or schedules from those services.
- The app shell works offline, but actions that need the backend require a network connection. Without `GOOGLE_CLIENT_ID`, calendar checks use demo data and do not save changes.
