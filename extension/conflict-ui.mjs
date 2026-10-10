import { basicCatalog } from "@a2ui/lit/v0_9";
import { Catalog, MessageProcessor } from "@a2ui/web_core/v0_9";
import { createConflictPopup as createPopup } from "../backend/static/conflict-core.mjs";
export { attentionIndices } from "../backend/static/conflict-core.mjs";
export function createConflictPopup(options) {
  return createPopup({ ...options, loadRenderer: async () => ({ basicCatalog, Catalog, MessageProcessor }) });
}
