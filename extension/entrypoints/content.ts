// Content script: captures what the user means, shows the selection launcher and the target
// highlight, and hosts the overlay in an extension iframe (A2UI needs custom elements, which
// content scripts lack, and the iframe keeps the page from reading or clicking the overlay).
import {
  captureElement,
  capturePage,
  captureSelection,
  currentGazeTarget,
  listenForGazeEvents,
  onGazeTarget,
  type Target,
} from '@/lib/capture';
import type { FromFrame, PortHandoff, ToFrame } from '@/lib/frame-protocol';
import type { ToContent } from '@/lib/messages';
import type { OverlayLayout } from '@/src/ui/host';

const GAP = 10;
const MARGIN = 12;
/** Frame size before the overlay reports its real layout. */
const INITIAL = { width: 564, height: 330 };

const CSS = `
:host { all: initial; }
.layer { position: fixed; inset: 0; pointer-events: none; z-index: 2147483647; }
.frame { position: fixed; border: 0; background: transparent; color-scheme: normal; pointer-events: auto;
  opacity: 0; visibility: hidden; transition: opacity .16s ease, visibility 0s linear .16s; }
.frame.on { opacity: 1; visibility: visible; transition: opacity .16s ease; }
.glass { position: fixed; pointer-events: none; backdrop-filter: blur(22px) saturate(165%);
  -webkit-backdrop-filter: blur(22px) saturate(165%); box-shadow: 0 22px 56px rgba(0,0,0,.34), 0 4px 14px rgba(0,0,0,.18);
  opacity: 0; transition: opacity .16s ease; }
.glass.on { opacity: 1; }
.hl { position: fixed; border-radius: 10px; pointer-events: none; opacity: 0;
  box-shadow: 0 0 0 2px rgba(64,120,255,.85), 0 0 0 7px rgba(64,120,255,.18), 0 8px 30px rgba(64,120,255,.25);
  transition: opacity .2s ease; }
.hl.on { opacity: 1; }
.launch { position: fixed; width: 34px; height: 34px; padding: 0; border-radius: 999px; cursor: pointer;
  pointer-events: auto; display: grid; place-items: center; color: #fff;
  background: radial-gradient(circle at 50% 35%, #2c2f38, #121318 75%);
  border: 1px solid rgba(255,255,255,.18); box-shadow: 0 6px 20px rgba(0,0,0,.35);
  transform: scale(.6); opacity: 0; transition: transform .18s cubic-bezier(.2,1.4,.4,1), opacity .15s ease; }
.launch:not(.on) { pointer-events: none; visibility: hidden; transition: transform .18s, opacity .15s, visibility 0s .18s; }
.launch.on { transform: scale(1); opacity: 1; }
.launch:hover { background: radial-gradient(circle at 50% 35%, #2a4dbb, #0f1e52 80%); }
.launch svg { width: 18px; height: 18px; }
`;

const EYE = `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M2.5 12c2.3-4.2 5.6-6.3 9.5-6.3s7.2 2.1 9.5 6.3c-2.3 4.2-5.6 6.3-9.5 6.3S4.8 16.2 2.5 12Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><circle cx="12" cy="12" r="3.2" fill="currentColor"/></svg>`;

export default defineContentScript({
  matches: ['<all_urls>'],
  runAt: 'document_idle',
  main() {
    if (window.top !== window) return;
    listenForGazeEvents();

    const hostEl = document.createElement('micro-intent-overlay');
    const shadow = hostEl.attachShadow({ mode: 'closed' });
    shadow.innerHTML = `<style>${CSS}</style><div class="layer"><div class="hl"></div><button class="launch" type="button" aria-label="Ask Micro Intent" title="Ask Micro Intent (⌥⇧M)">${EYE}</button></div>`;
    const layer = shadow.querySelector<HTMLDivElement>('.layer')!;
    const hl = shadow.querySelector<HTMLDivElement>('.hl')!;
    const launch = shadow.querySelector<HTMLButtonElement>('.launch')!;
    document.documentElement.append(hostEl);

    let frame: HTMLIFrameElement | undefined;
    let port: MessagePort | undefined;
    let ready = false;
    let queued: ToFrame[] = [];
    let open = false;
    let target: Target | undefined;
    let launcherTarget: Target | undefined;
    let layout: OverlayLayout = { ...INITIAL, shapes: [] };
    /** Frame anchor: either a top edge, or a bottom edge when the overlay sits above the target. */
    let anchor = { left: MARGIN, top: MARGIN as number | undefined, bottom: undefined as number | undefined };
    const glass: HTMLDivElement[] = [];
    const pointer = { x: -1, y: -1 };

    const send = (msg: ToFrame) => {
      if (port && ready) port.postMessage(msg);
      else queued.push(msg);
    };

    function frameTop(): number {
      const top = anchor.top ?? (anchor.bottom ?? 0) - layout.height;
      return Math.max(MARGIN, Math.min(top, window.innerHeight - 80));
    }

    function render() {
      if (!frame) return;
      const top = frameTop();
      frame.style.left = `${anchor.left}px`;
      frame.style.top = `${top}px`;
      frame.style.width = `${layout.width}px`;
      frame.style.height = `${layout.height}px`;
      frame.classList.toggle('on', open);
      layout.shapes.forEach((s, i) => {
        let g = glass[i];
        if (!g) {
          g = document.createElement('div');
          g.className = 'glass';
          layer.insertBefore(g, frame!);
          glass[i] = g;
        }
        Object.assign(g.style, {
          left: `${anchor.left + s.x}px`,
          top: `${top + s.y}px`,
          width: `${s.w}px`,
          height: `${s.h}px`,
          borderRadius: `${s.r}px`,
        });
        g.classList.toggle('on', open);
      });
      glass.slice(layout.shapes.length).forEach((g) => g.classList.remove('on'));
      if (!open) glass.forEach((g) => g.classList.remove('on'));
    }

    function renderHighlight() {
      const r = target?.element?.isConnected ? target.element.getBoundingClientRect() : target?.rect;
      const show = open && target && target.source !== 'page' && r;
      hl.classList.toggle('on', !!show);
      if (show && r) {
        Object.assign(hl.style, {
          left: `${r.left - 6}px`,
          top: `${r.top - 4}px`,
          width: `${r.width + 12}px`,
          height: `${r.height + 8}px`,
        });
      }
    }

    function ensureFrame() {
      if (frame) return;
      const nonce = crypto.randomUUID();
      frame = document.createElement('iframe');
      frame.className = 'frame';
      frame.title = 'Micro Intent';
      frame.allow = '';
      frame.src = `${browser.runtime.getURL('/overlay.html')}#${nonce}`;
      layer.append(frame);
      frame.addEventListener('load', () => {
        const channel = new MessageChannel();
        port = channel.port1;
        port.onmessage = (e: MessageEvent<FromFrame>) => onFrame(e.data);
        const handoff: PortHandoff = { mi: 'port', nonce };
        frame!.contentWindow!.postMessage(handoff, new URL(frame!.src).origin, [channel.port2]);
      });
    }

    function onFrame(msg: FromFrame) {
      switch (msg.mi) {
        case 'ready':
          ready = true;
          queued.forEach((m) => port!.postMessage(m));
          queued = [];
          break;
        case 'layout':
          layout = msg.layout;
          render();
          break;
        case 'drag':
          anchor.left = Math.max(0, Math.min(anchor.left + msg.dx, window.innerWidth - 120));
          if (anchor.top !== undefined) anchor.top += msg.dy;
          else anchor.bottom = (anchor.bottom ?? 0) + msg.dy;
          hl.classList.remove('on');
          render();
          break;
        case 'close':
          close();
          break;
      }
    }

    function place(rect: DOMRect) {
      const vw = window.innerWidth;
      const vh = window.innerHeight;
      const width = layout.width || INITIAL.width;
      const left = Math.min(Math.max(MARGIN, rect.left + rect.width / 2 - width / 2), vw - width - MARGIN);
      const below = vh - rect.bottom;
      if (below > 420 || below > rect.top) anchor = { left, top: Math.min(rect.bottom + GAP, vh - 160), bottom: undefined };
      else anchor = { left, top: undefined, bottom: Math.max(rect.top - GAP, 160) };
    }

    function openAt(t: Target) {
      ensureFrame();
      target = t;
      open = true;
      setLauncher(undefined);
      place(t.rect);
      const { rect: _r, element: _e, ...plain } = t;
      send({ mi: 'open', target: plain });
      render();
      renderHighlight();
    }

    function close() {
      if (open) send({ mi: 'hidden' });
      open = false;
      target = undefined;
      render();
      renderHighlight();
    }

    function setLauncher(t: Target | undefined) {
      launcherTarget = open ? undefined : t;
      launch.classList.toggle('on', !!launcherTarget);
      if (launcherTarget) {
        const r = launcherTarget.rect;
        launch.style.left = `${Math.min(r.right + 6, window.innerWidth - 44)}px`;
        launch.style.top = `${Math.max(8, r.top - 40)}px`;
      }
    }

    /** What the user means right now: selection, then gaze, then the element under the pointer. */
    function resolveTarget(): Target {
      const sel = captureSelection();
      if (sel) return sel;
      const gaze = currentGazeTarget();
      if (gaze) return gaze;
      const el = pointer.x >= 0 ? document.elementFromPoint(pointer.x, pointer.y) : null;
      if (el && el !== hostEl && el !== document.body && el !== document.documentElement) {
        return captureElement(el, 'pointer');
      }
      return capturePage();
    }

    launch.addEventListener('mousedown', (e) => e.preventDefault());
    launch.addEventListener('click', () => launcherTarget && openAt(launcherTarget));

    browser.runtime.onMessage.addListener((raw: unknown) => {
      if ((raw as ToContent).type === 'mi:open') openAt(resolveTarget());
    });

    onGazeTarget((t) => setLauncher(t));

    document.addEventListener('pointermove', (e) => ((pointer.x = e.clientX), (pointer.y = e.clientY)), {
      passive: true,
    });

    let selTimer: number | undefined;
    const onSelect = (e: Event) => {
      if (e.composedPath().includes(hostEl)) return;
      window.clearTimeout(selTimer);
      selTimer = window.setTimeout(() => setLauncher(captureSelection()), 160);
    };
    document.addEventListener('mouseup', onSelect);
    document.addEventListener('keyup', onSelect);

    window.addEventListener('scroll', () => renderHighlight(), { passive: true, capture: true });
    window.addEventListener('resize', () => render());

    // Hold Option/Alt on the page to talk while the overlay is open; Escape closes it.
    let holdTimer: number | undefined;
    let holding = false;
    window.addEventListener(
      'keydown',
      (e) => {
        if (!open) return;
        if (e.key === 'Escape') close();
        else if (e.key === 'Alt' && !e.repeat && !e.shiftKey && !e.metaKey && !e.ctrlKey) {
          holdTimer = window.setTimeout(() => {
            holding = true;
            send({ mi: 'ptt', down: true });
          }, 220);
        } else window.clearTimeout(holdTimer);
      },
      true,
    );
    window.addEventListener(
      'keyup',
      (e) => {
        if (e.key !== 'Alt') return;
        window.clearTimeout(holdTimer);
        if (holding) {
          holding = false;
          send({ mi: 'ptt', down: false });
        }
      },
      true,
    );
  },
});
