// Access tokens live only in Swagger's in-memory authorization state.
const googleStatus = document.getElementById("google-status");
const gmailButton = document.getElementById("connect-gmail");
const calendarButton = document.getElementById("connect-calendar");
const readScopes = {
  gmail: "https://www.googleapis.com/auth/gmail.readonly",
  calendar: "https://www.googleapis.com/auth/calendar.readonly",
};
let expiryTimer;
let authorizationGeneration = 0;
document.getElementById("google-origin").textContent = window.location.origin;
gmailButton.disabled = calendarButton.disabled = true;

function clearGoogleAuthorization(message) {
  authorizationGeneration += 1;
  clearTimeout(expiryTimer);
  if (ui.authSelectors.authorized()?.get("GoogleAccessToken")) {
    ui.authActions.logout(["GoogleAccessToken"]);
  }
  googleStatus.textContent = message;
}

function googleIdentityFailed() {
  googleStatus.textContent = "Google sign-in could not load. Check your connection or browser blocking settings and reload.";
}

function googleIdentityReady() {
  if (!googleAuthConfig.clientId) {
    googleStatus.textContent = "Google sign-in is not configured. Set GOOGLE_CLIENT_ID in backend/.env or the project .env, then restart the backend.";
    return;
  }
  gmailButton.disabled = calendarButton.disabled = false;
  googleStatus.textContent = "Choose Connect Gmail or Connect Calendar to authorize requests.";
}

function connectGoogle(service) {
  clearGoogleAuthorization("Waiting for Google authorization…");
  const generation = authorizationGeneration;
  const client = google.accounts.oauth2.initTokenClient({
    client_id: googleAuthConfig.clientId,
    scope: readScopes[service],
    include_granted_scopes: true,
    callback: (response) => {
      if (generation !== authorizationGeneration) return;
      if (response.error || !response.access_token) {
        googleStatus.textContent = "Google authorization was not completed. Try connecting again and allow access.";
        return;
      }
      if (!google.accounts.oauth2.hasGrantedAllScopes(response, readScopes[service])) {
        googleStatus.textContent = "The requested permission was not granted. Connect again and allow read access.";
        return;
      }
      ui.preauthorizeApiKey("GoogleAccessToken", response.access_token);
      googleStatus.textContent = `Connected to ${service === "gmail" ? "Gmail" : "Calendar"}. You can now execute its endpoint below.`;
      const lifetime = Number(response.expires_in);
      expiryTimer = setTimeout(() => {
        clearGoogleAuthorization("Google access expired. Connect again to continue.");
      }, Math.max(0, (Number.isFinite(lifetime) ? lifetime - 30 : 3300) * 1000));
    },
    error_callback: () => {
      if (generation !== authorizationGeneration) return;
      googleStatus.textContent = "Google sign-in was closed or blocked. Allow popups, verify the authorized origin in Google Cloud, and try again.";
    },
  });
  client.requestAccessToken({prompt: "select_account"});
}

gmailButton.addEventListener("click", () => connectGoogle("gmail"));
calendarButton.addEventListener("click", () => connectGoogle("calendar"));
document.getElementById("disconnect-google").addEventListener("click", () => {
  clearGoogleAuthorization("Disconnected from these API docs.");
});
