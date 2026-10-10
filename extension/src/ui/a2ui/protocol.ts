// A2UI v0.9 message types (https://a2ui.org) and our catalog id.
export type { A2uiMessage } from '@a2ui/web_core/v0_9';

/** The trusted client catalog. The agent may only use components listed in src/ui/a2ui/catalog.tsx. */
export const CATALOG_ID = 'https://micro-intent.app/a2ui/catalog/v1';
export const A2UI_VERSION = 'v0.9.1';

/** An A2UI action prop: a server event, or a local function call such as openUrl. */
export interface A2uiAction {
  event?: { name: string; context?: Record<string, unknown> };
  functionCall?: { call: string; args?: Record<string, unknown> };
  /** Our catalog adds a button label and, for writes, a human-readable preview. */
  label?: string;
  preview?: string;
}
