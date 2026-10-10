# Deploy Micro Intent on Google Cloud Run

Cloud Run serves this app's production frontend and API from one HTTPS origin. A phone can open and install that URL without running the laptop. The repository includes a multi-stage Dockerfile; credentials are supplied at runtime and never baked into the image.

## Before deployment

**Verified on October 10, 2026:** the hackathon account can configure OAuth and enable Calendar API, but Cloud Run shows that its Admin API is disabled and this account cannot enable it. Ask the project administrator to enable the required services and allow deployment, or use another hosting account. No Cloud Run service has been created.

- Project: `agentic26zrh-2062` (number `863389256678`).
- The account needs deployment permissions, enabled billing/credits, Cloud Run, Cloud Build and Artifact Registry APIs. Hackathon organizations can restrict public services or OAuth; ask the organizer if a policy blocks deployment.
- Use Google Cloud CLI on your computer, or Cloud Shell with a sanitized source checkout. Do not upload `.env`, `.runtime`, or the nested `micro-intent` checkout. The included `.gcloudignore` and `.dockerignore` exclude local secrets and runtime files.
- Complete [Calendar OAuth setup](OAUTH-SETUP.md). The Google Calendar connector in the chat does not authorize the deployed app.

## Deploy the service

First verify the local build:

```powershell
npm ci
npm test
npm run build
```

Deploy from the repository root using the included Dockerfile:

```powershell
gcloud run deploy micro-intent --source . --project agentic26zrh-2062 --region europe-west6 --port 8080 --min-instances 0 --max-instances 1 --memory 512Mi --no-allow-unauthenticated
```

This initially creates an IAM-protected service for review. Browser OAuth and a shareable mobile demo require allowing visitors to reach the web app; review that access change before making the service public. Public reachability of the app does not itself grant access to a visitor's Calendar: each visitor still authorizes Google in the app. Limit Gemini quota and monitor usage because a public planning endpoint can consume model requests. Instance limits are not a spending cap.

In the service's **Edit & deploy new revision** screen, configure:

| Variable | Value |
| --- | --- |
| `NODE_ENV` | `production` |
| `HOST` | `0.0.0.0` |
| `GOOGLE_CLIENT_ID` | Web application's OAuth client ID |
| `APP_ORIGIN` | Exact HTTPS origin returned by Cloud Run |
| `GEMINI_MODEL` | `gemini-3.5-flash-lite` |
| `GEMINI_API_KEY` | Reference to a Secret Manager secret |

Grant the runtime service account access to that one secret, not broad access to all secrets. Enter the existing Gemini key in Secret Manager through its secure console; do not put it in source, a Docker build argument, shell command history, or a screenshot.

Add the service's exact HTTPS origin to the OAuth client's Authorized JavaScript origins, then deploy the new revision. The app must be accessible before testing the OAuth popup. Google Cloud may require an administrator to enable billing or allow public invocation; no such change is made by the local build.

## Verify on desktop and mobile

1. Open `/api/status`: it should report both `googleConfigured` and `modelConfigured` as true.
2. Open the homepage and connect the Calendar test account. Confirm the plan says **LIVE GOOGLE CALENDAR**.
3. Check October 14, 2026, 18:30–20:30 Europe/Zurich. The demo Gym and Exam preparation events overlap by 15 minutes each.
4. Test a reviewed save in Calendar and confirm it appears only once when retried. Registration on Luma remains separate.
5. On a phone, open the same HTTPS URL and use the browser's install/Add to Home Screen action. Camera and microphone prompts must be accepted on the actual device.
6. In the extension's popup, configure the deployed app and API origin and approve access to that domain. Use the PWA on mobile; desktop extensions do not run in mobile Chrome.
7. Follow [the device checklist](DEVICE-CHECK.md) for gaze, voice, and fallback input. The offline cache supports the app shell only; live integrations still need the network.

## Alternatives and current status

If this temporary Google project does not allow Cloud Run, the same Docker image can run on another Node/Docker host such as Render. No cloud service is provisioned by merely adding these files. Deployment, billing entitlement, OAuth consent, device audio/camera, and actual PWA installation need verification against the target account/device.

References: [Cloud Run Node deployment](https://docs.cloud.google.com/run/docs/quickstarts/build-and-deploy/deploy-nodejs-service), [Cloud Run Secret Manager configuration](https://docs.cloud.google.com/run/docs/configuring/services/secrets), [Render web services](https://render.com/docs/web-services).
