import { createConflictPopup as createPopup } from "./conflict-core.mjs";
export { attentionIndices, conflictKey, selectCardMessages } from "./conflict-core.mjs";

let rendererPromise;
async function loadA2UI() {
  // Pinned official libraries; fetched only when a conflict needs a surface.
  rendererPromise ??= Promise.all([
    import("https://esm.sh/@a2ui/lit@0.13.0/v0_9?deps=@a2ui/web_core@0.13.0"),
    import("https://esm.sh/@a2ui/web_core@0.13.0/v0_9"),
  ]).then(([lit, core]) => ({ basicCatalog: lit.basicCatalog,
    MessageProcessor: core.MessageProcessor, Catalog: core.Catalog })).catch((error) => {
    rendererPromise = undefined;
    throw error;
  });
  return rendererPromise;
}

export function createConflictPopup(options) {
  return createPopup({ ...options, loadRenderer: options.loadRenderer ?? loadA2UI });
}
