const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../services/docs_auth.js'), 'utf8');

function setup(clientId = 'test-client') {
  const elements = {};
  const state = {authorized: null, callbacks: [], timers: []};
  const context = vm.createContext({
    googleAuthConfig: {clientId},
    document: {getElementById(id) {
      return elements[id] ??= {addEventListener(event, callback) {this[event] = callback;}};
    }},
    window: {location: {origin: 'http://localhost:8000'}},
    ui: {
      authSelectors: {authorized() {return {get() {return state.authorized;}};}},
      authActions: {logout() {state.authorized = null;}},
      preauthorizeApiKey(scheme, token) {state.authorized = {scheme, token};},
    },
    google: {accounts: {oauth2: {
      initTokenClient(config) {
        state.callbacks.push(config);
        return {requestAccessToken() {}};
      },
      hasGrantedAllScopes(response, scope) {return response.scope === scope;},
    }}},
    setTimeout(callback) {state.timers.push(callback); return state.timers.length;},
    clearTimeout() {},
  });
  vm.runInContext(script, context);
  context.googleIdentityReady();
  return {elements, state};
}

test('Google grant authorizes Swagger; expiry clears access', () => {
  const {elements, state} = setup();
  elements['connect-gmail'].click();
  const config = state.callbacks[0];
  assert.equal(config.scope, 'https://www.googleapis.com/auth/gmail.readonly');
  config.callback({access_token: 'fake-token', scope: config.scope, expires_in: 3600});
  assert.deepEqual(state.authorized, {scheme: 'GoogleAccessToken', token: 'fake-token'});
  state.timers[0]();
  assert.equal(state.authorized, null);
  assert.match(elements['google-status'].textContent, /expired/);
});

test('missing client ID disables connection', () => {
  const {elements} = setup('');
  assert.equal(elements['connect-gmail'].disabled, true);
  assert.match(elements['google-status'].textContent, /not configured/);
});

test('denied scope never authorizes Swagger', () => {
  const {elements, state} = setup();
  elements['connect-gmail'].click();
  state.callbacks[0].callback({access_token: 'fake-token', scope: '', expires_in: 3600});
  assert.equal(state.authorized, null);
  assert.match(elements['google-status'].textContent, /not granted/);
});

test('disconnect invalidates pending Google callbacks', () => {
  const {elements, state} = setup();
  elements['connect-calendar'].click();
  const config = state.callbacks[0];
  elements['disconnect-google'].click();
  config.callback({access_token: 'fake-token', scope: config.scope, expires_in: 3600});
  assert.equal(state.authorized, null);
});

test('closed popup gives a retry message', () => {
  const {elements, state} = setup();
  elements['connect-gmail'].click();
  state.callbacks[0].error_callback({type: 'popup_closed'});
  assert.equal(state.authorized, null);
  assert.match(elements['google-status'].textContent, /closed or blocked/);
});
