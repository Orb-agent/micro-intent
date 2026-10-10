# Google Calendar setup

Use Google Cloud project `agentic26zrh-2062` (project number `863389256678`) with the hackathon account. The Gemini API key does not authorize access to Calendar. This app needs a **Web application OAuth client ID**, not a client secret.

**Verified on October 10, 2026:** Micro Intent Web has been created with the four local origins below, Calendar API is enabled, and the hackathon account is an OAuth test user. The client ID is configured in the ignored local `.env`. The web app successfully retrieved both real demo conflicts and displayed LIVE GOOGLE CALENDAR. Reconnect when the temporary token expires. The steps below document setup for redeployment or another environment; do not create a duplicate client.

1. Open [Google Cloud credentials](https://console.cloud.google.com/apis/credentials?project=agentic26zrh-2062). If Google presents terms, the account owner must review them.
2. Enable **Google Calendar API** in APIs & Services > Library.
3. Open **Google Auth Platform / OAuth consent screen**. Set the app name to **Micro Intent** and use the hackathon account as the support/contact email.
4. Choose **External**, keep the app in **Testing**, and add `devstar2062@gcplab.me` under test users. If this managed project only permits Internal apps, use Internal for accounts in its organization; outside accounts cannot sign in.
5. Under Data Access, add `https://www.googleapis.com/auth/calendar.events`. This enables the current prototype to read and create events in the primary calendar; the UI asks for confirmation before saving.
6. Under Clients, create a **Web application** called **Micro Intent Web**. Add these **Authorized JavaScript origins** (no path or trailing slash):

   ```text
   http://localhost
   http://localhost:5173
   http://localhost:4173
   http://localhost:3001
   ```

7. Leave redirect URIs empty: this app uses the Google Identity Services popup token flow.
8. Copy only the client ID ending in `.apps.googleusercontent.com`. Add it to the existing `.env` as `GOOGLE_CLIENT_ID=...`, preserving the Gemini key, and restart the local launcher.
9. After hosting, add the exact HTTPS origin returned by Cloud Run to the same client. Set the same client ID as `GOOGLE_CLIENT_ID` on the Cloud Run service.
10. Open Micro Intent > Connections > Connect Google Calendar. Choose the test account and grant Calendar permission. Check the demo event on October 14, 2026: the Gym and Exam preparation demo events should produce two conflicts.

Only the user should approve Google's Calendar consent screen. The app keeps its access token in memory and reconnects when it expires; it does not store a password or refresh token. The Calendar connector in this chat is a separate authorization from the web app.

## Troubleshooting

- `origin_mismatch`: add the exact origin displayed in the browser address bar, including the port.
- `access_denied`: check the test-user list and any organization policy.
- Calendar API disabled: enable the API in the same project as the OAuth client.
- Popup closed/blocked: allow the popup for Micro Intent and press Connect again.
- Session expired: reconnect before checking or saving.

Sources: [Google client setup](https://developers.google.com/identity/oauth2/web/guides/get-google-api-clientid), [Google token model](https://developers.google.com/identity/oauth2/web/guides/use-token-model).
