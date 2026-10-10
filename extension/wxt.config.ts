import { defineConfig } from 'wxt';

export default defineConfig({
  modules: ['@wxt-dev/module-react'],
  manifest: {
    name: 'Micro Intent',
    description: 'Look at something, say what you want, approve the action.',
    permissions: ['storage', 'offscreen', 'contextMenus', 'activeTab'],
    // The backend URL is configurable (localhost in dev, Cloud Run in the demo),
    // so the background worker needs to reach any origin without CORS.
    host_permissions: ['<all_urls>'],
    action: { default_title: 'Micro Intent' },
    commands: {
      'open-overlay': {
        suggested_key: { default: 'Alt+Shift+M', mac: 'Alt+Shift+M' },
        description: 'Ask Micro Intent about what you are looking at',
      },
    },
    web_accessible_resources: [{ resources: ["overlay.html"], matches: ["<all_urls>"] }],
  },
});
