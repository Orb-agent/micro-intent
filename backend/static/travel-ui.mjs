// Uses the existing reply.cards contract; no extra model-generated URLs are accepted.
export function travelPlan(cards, question = "", now = Date.now()) {
  if (cards.some(c => c.kind === "conflict")) return null;
  const event = cards.find(c => c.kind === "event" && c.location?.trim() && Date.parse(c.start) > now);
  const deadline = event ? Date.parse(event.start) : Infinity;
  const train = cards.find(c => c.kind === "train" && c.to?.trim()
    && Date.parse(c.departure) > now && Date.parse(c.arrival) >= Date.parse(c.departure)
    && Date.parse(c.arrival) + Math.max(0, c.delay_min || 0) * 60000 <= deadline);
  // A calendar listing alone should not interrupt the user with a travel popup.
  const attending = /\b(attend|make it|can i go|want to go|asistir|llegar|puedo ir|quiero ir|ir al evento)\b/i.test(question);
  if (!train && (!event || !attending || cards.some(c => c.kind === "train"))) return null;
  const origin = train?.from?.trim() || "Winterthur";
  const destination = event?.location.trim() || train.to.trim();
  const url = new URL("https://www.google.com/maps/dir/");
  url.search = new URLSearchParams({ api: "1", origin, destination, travelmode: "transit" });
  if (url.href.length > 2048) return null;
  return { origin, destination, title: event?.title || "Suggested connection",
    start: event?.start || null, train: train || null, url: url.href };
}
