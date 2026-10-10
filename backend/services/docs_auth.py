"""Google Identity Services authorization for the interactive API docs."""
import json
import os
from pathlib import Path

from fastapi.openapi.docs import get_swagger_ui_html
from fastapi.responses import HTMLResponse


def google_docs_html() -> HTMLResponse:
    page = get_swagger_ui_html(
        openapi_url="/openapi.json",
        title="Lumi API — Connect Google Workspace",
        swagger_ui_parameters={"persistAuthorization": False},
    ).body.decode()
    config = json.dumps({"clientId": os.getenv("GOOGLE_CLIENT_ID", "")}).replace("<", "\\u003c")
    script = Path(__file__).with_name("docs_auth.js").read_text(encoding="utf-8")
    banner = """
    <section style="padding:20px 4%;font-family:system-ui;background:#eef5ff" aria-label="Google connection">
      <h2>Connect Google Workspace</h2>
      <p>Connect the service you want to test, choose your Google account, and allow access.
      Then use Try it out below. Access lasts until the token expires or this page is reloaded.</p>
      <button type="button" id="connect-gmail">Connect Gmail</button>
      <button type="button" id="connect-calendar">Connect Calendar</button>
      <button type="button" id="disconnect-google">Disconnect</button>
      <p id="google-status" role="status" aria-live="polite">Loading Google sign-in…</p>
      <details><summary>Google connection setup</summary>
        <p>In the Google Cloud web OAuth client, add this page's origin
        (<code id="google-origin"></code>) to Authorized JavaScript origins.
        Enable the Gmail API and, for calendar access, the Google Calendar API.
        If the consent screen is in Testing, add your Google account as a test user.</p>
        <p>These buttons request read access only. Sending email or changing calendar events
        requires a token with additional permissions via Authorize.</p>
      </details>
    </section>
    """
    page = page.replace('<div id="swagger-ui">', banner + '<div id="swagger-ui">')
    page = page.replace(
        "</body>",
        f"<script>const googleAuthConfig = {config};\n{script}</script>"
        '<script src="https://accounts.google.com/gsi/client" async defer '
        'onload="googleIdentityReady()" onerror="googleIdentityFailed()"></script></body>',
    )
    return HTMLResponse(page, headers={"Cache-Control": "no-store", "Referrer-Policy": "strict-origin-when-cross-origin"})
