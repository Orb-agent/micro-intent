// Captures what the user means: highlighted text, the element they look at, or the element
// under the pointer, in the docs/API.md `context` shape.
import type { ElementInfo, PageContext } from '../src/api/types';
import type { Target as UiTarget } from '../src/ui/host';

const MAX_ELEMENT_TEXT = 2000;
const MAX_PAGE_TEXT = 8000;
const BLOCK_TAGS = new Set(['P', 'LI', 'ARTICLE', 'SECTION', 'TD', 'BLOCKQUOTE', 'DIV', 'H1', 'H2', 'H3', 'FIGURE', 'MAIN', 'HEADER']);
const KEEP_ATTRS = ['aria-label', 'title', 'datetime', 'href', 'alt'];

export interface Target extends UiTarget {
  /** Viewport rect the overlay anchors to. */
  rect: DOMRect;
  element?: Element;
}

function clean(text: string | null | undefined, max = MAX_ELEMENT_TEXT): string {
  return (text ?? '').replace(/\s+/g, ' ').trim().slice(0, max);
}

function visibleText(el: Element): string {
  return clean((el as HTMLElement).innerText ?? el.textContent);
}

/** The nearest block-level ancestor, so a selected word comes with its sentence. */
function blockOf(node: Node | null): Element | undefined {
  let el: Element | null = node instanceof Element ? node : (node?.parentElement ?? null);
  while (el && el !== document.body) {
    if (BLOCK_TAGS.has(el.tagName) && visibleText(el).length > 20) return el;
    el = el.parentElement;
  }
  return undefined;
}

function selectorOf(el: Element): string {
  const parts: string[] = [];
  let cur: Element | null = el;
  while (cur && cur !== document.body && parts.length < 4) {
    if (cur.id) {
      parts.unshift(`#${CSS.escape(cur.id)}`);
      break;
    }
    const cls = [...cur.classList].slice(0, 2).map((c) => `.${CSS.escape(c)}`).join('');
    parts.unshift(cur.tagName.toLowerCase() + cls);
    cur = cur.parentElement;
  }
  return parts.join(' > ');
}

function elementInfo(el: Element): ElementInfo {
  const attributes: Record<string, string> = {};
  for (const name of KEEP_ATTRS) {
    const v = el.getAttribute(name);
    if (v) attributes[name] = v.slice(0, 300);
  }
  // Machine-readable times help the agent more than the visible text does.
  const time = el.matches('time[datetime]') ? el : el.querySelector('time[datetime]');
  if (time && !attributes.datetime) attributes.datetime = time.getAttribute('datetime')!;
  return { tag: el.tagName.toLowerCase(), text: visibleText(el), selector: selectorOf(el), attributes };
}

function pageText(): string {
  const main = document.querySelector('main, article, [role=main]') ?? document.body;
  return clean((main as HTMLElement).innerText, MAX_PAGE_TEXT);
}

function base(): Pick<PageContext, 'url' | 'title' | 'page_text'> {
  return { url: location.href, title: document.title, page_text: pageText() };
}

function snippetOf(text: string | undefined): string {
  return clean(text, 80);
}

/** Current text selection, or undefined when nothing meaningful is selected. */
export function captureSelection(): Target | undefined {
  const sel = window.getSelection();
  const text = clean(sel?.toString());
  if (!sel || sel.rangeCount === 0 || text.length < 2) return undefined;
  const range = sel.getRangeAt(0);
  const block = blockOf(range.commonAncestorContainer);
  return {
    context: { ...base(), selection: { text, element: block ? elementInfo(block) : undefined } },
    source: 'selection',
    snippet: snippetOf(text),
    rect: range.getBoundingClientRect(),
    element: block,
  };
}

/** Context for one element: the one the eye tracker reports, or the one under the pointer. */
export function captureElement(el: Element, source: 'gaze' | 'pointer', dwellMs?: number): Target {
  const target = blockOf(el) ?? el;
  const info = elementInfo(target);
  const rect = target.getBoundingClientRect();
  const context: PageContext =
    source === 'gaze'
      ? {
          ...base(),
          gaze: { ...info, x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2), dwell_ms: dwellMs },
        }
      : { ...base(), selection: { element: info } };
  return { context, source, snippet: snippetOf(info.text), rect, element: target };
}

/** Whole-page fallback when nothing is selected or looked at. */
export function capturePage(): Target {
  return {
    context: base(),
    source: 'page',
    snippet: snippetOf(document.title),
    rect: new DOMRect(window.innerWidth / 2 - 1, 72, 2, 2),
  };
}

// ---- Eye-tracking interface -------------------------------------------------------------------
// An eye-tracking module hands over the element the user looks at in one of two ways:
//   1. In the content script: `setGazeTarget(element, dwellMs)`.
//   2. From any world (page script, another extension):
//      element.dispatchEvent(new CustomEvent('micro-intent:gaze', { bubbles: true, composed: true, detail: { dwellMs } }))
// The selection launcher then appears next to that element, and opening the overlay uses its
// text as `context.gaze`.

type GazeListener = (target: Target) => void;
const gazeListeners = new Set<GazeListener>();
let gaze: { el: Element; dwellMs?: number } | undefined;

export function setGazeTarget(el: Element | null, dwellMs?: number) {
  gaze = el ? { el, dwellMs } : undefined;
  if (el) {
    const t = captureElement(el, 'gaze', dwellMs);
    gazeListeners.forEach((fn) => fn(t));
  }
}

export function currentGazeTarget(): Target | undefined {
  return gaze?.el.isConnected ? captureElement(gaze.el, 'gaze', gaze.dwellMs) : undefined;
}

export function onGazeTarget(fn: GazeListener): () => void {
  gazeListeners.add(fn);
  return () => gazeListeners.delete(fn);
}

export function listenForGazeEvents() {
  document.addEventListener('micro-intent:gaze', (e) => {
    const el = e.composedPath()[0];
    const dwellMs = (e as CustomEvent<{ dwellMs?: number } | null>).detail?.dwellMs;
    if (el instanceof Element) setGazeTarget(el, dwellMs);
  });
}
