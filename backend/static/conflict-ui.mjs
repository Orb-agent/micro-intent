// The popup consumes the same A2UI v0.9 messages as the iPhone client.
const CATALOG_ID = "https://a2ui.org/specification/v0_9/basic_catalog.json";
const ATTENTION = new Set(["tight", "clash"]);

export function attentionIndices(cards) {
  return cards.flatMap((card, index) =>
    card?.kind === "conflict" && ATTENTION.has(card.verdict) ? [index] : []);
}

export function conflictKey(card) {
  // Wording changes in `note` should not reopen an acknowledged conflict.
  return JSON.stringify([
    card.verdict, card.event?.title, card.event?.start, card.event?.end,
    card.proposal?.title, card.proposal?.start, card.proposal?.place,
  ]);
}

export function selectCardMessages(messages, indices) {
  if (!Array.isArray(messages)) throw new Error("Invalid A2UI messages");
  const create = messages.find((message) => message.createSurface);
  if (create?.version !== "v0.9" || create.createSurface.catalogId !== CATALOG_ID) {
    throw new Error("Unsupported A2UI catalog or version");
  }
  const surfaceId = create.createSurface.surfaceId;
  const update = messages.find((message) => message.updateComponents?.surfaceId === surfaceId);
  const components = update?.updateComponents.components;
  if (!Array.isArray(components) || components.length > 100) throw new Error("Invalid A2UI components");
  const nodes = new Map(components.map((node) => [node.id, node]));
  if (nodes.size !== components.length) throw new Error("Duplicate A2UI component id");
  const root = nodes.get("root");
  if (root?.component !== "Column" || !Array.isArray(root.children)) throw new Error("Invalid A2UI root");
  const selectedIds = indices.map((index) => `c${index}`);
  if (!selectedIds.length || selectedIds.some((id) => !root.children.includes(id))) {
    throw new Error("Missing conflict components");
  }
  const selected = [{ id: "root", component: "Column", children: selectedIds }];
  const visited = new Set();
  function visit(id, cardId, ancestors) {
    if (ancestors.has(id)) throw new Error("Cyclic A2UI component tree");
    if (visited.has(id)) return;
    const node = nodes.get(id);
    if (!node || (id !== cardId && !id.startsWith(`${cardId}-`)) ||
        !["Card", "Column", "Text"].includes(node.component)) {
      throw new Error("Unsupported conflict component");
    }
    visited.add(id);
    selected.push(node);
    const children = node.children ?? (node.child ? [node.child] : []);
    if (!Array.isArray(children) || children.some((child) => typeof child !== "string")) {
      throw new Error("Invalid A2UI child references");
    }
    for (const child of children) visit(child, cardId, new Set([...ancestors, id]));
  }
  for (const id of selectedIds) visit(id, id, new Set());
  return [
    { version: "v0.9", createSurface: { surfaceId, catalogId: CATALOG_ID } },
    { version: "v0.9", updateComponents: { surfaceId, components: selected } },
  ];
}

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

export function createConflictPopup({ popup, content, dismissButton, renderFallback,
  log = () => {}, loadRenderer = loadA2UI }) {
  const dismissed = new Set();
  let cards = [], indices = [], generation = 0, processor;
  const reset = () => {
    generation++;
    processor?.dispose();
    processor = undefined;
    content.replaceChildren();
    popup.hidden = true;
  };
  const dismiss = () => {
    for (const index of indices) dismissed.add(conflictKey(cards[index]));
    reset();
  };
  dismissButton.addEventListener("click", dismiss);
  popup.addEventListener("keydown", (event) => {
    if (event.key === "Escape") { dismiss(); event.stopPropagation(); }
  });
  return {
    setReply(nextCards) {
      reset();
      cards = nextCards;
      indices = attentionIndices(cards).filter((index) => !dismissed.has(conflictKey(cards[index])));
      if (!indices.length) return;
      renderFallback(indices.map((index) => cards[index]));
      content.dataset.renderer = "fallback";
      popup.hidden = false;
    },
    async receiveMessages(messages) {
      if (popup.hidden) return false;
      const expectedGeneration = generation;
      try {
        const selected = selectCardMessages(messages, indices);
        const { MessageProcessor, Catalog, basicCatalog } = await loadRenderer();
        if (generation !== expectedGeneration || popup.hidden) return false;
        // Alias the existing Swift catalog URI without changing the wire contract.
        // Only the three passive components our server generates are registered.
        const catalog = new Catalog(CATALOG_ID, "0.9",
          ["Card", "Column", "Text"].map((name) => basicCatalog.components.get(name)), []);
        processor?.dispose();
        processor = new MessageProcessor([catalog]);
        processor.processMessages(selected);
        const surface = content.ownerDocument.createElement("a2ui-surface");
        surface.surface = processor.model.getSurface(selected[0].createSurface.surfaceId);
        content.replaceChildren(surface);
        content.dataset.renderer = "a2ui";
        return true;
      } catch (error) {
        if (generation === expectedGeneration) log("Conflict UI fallback:", error.message);
        return false; // The escaped native card remains usable, including offline.
      }
    },
    dismiss,
  };
}
