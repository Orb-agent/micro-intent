import {
  BellRing,
  CalendarCheck,
  CalendarPlus,
  ChevronDown,
  ChevronUp,
  Ellipsis,
  Eye,
  Globe,
  MousePointer2,
  Play,
  TextCursor,
  TrainFront,
  TriangleAlert,
} from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import {
  Fragment,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
} from 'react';
import type { ActionPayload, ComponentContext } from '@a2ui/web_core/v0_9';
import { CardEnvContext, type CardEnv, type RunOptions } from './a2ui/catalog';
import { A2UI_VERSION, type A2uiAction } from './a2ui/protocol';
import { doneSurface, Surfaces, useA2ui } from './a2ui/Surfaces';
import { ConfirmSheet } from './ConfirmSheet';
import type { Host, Target, UiSettings } from './host';
import { Orb, type OrbState } from './Orb';
import { speak, stopSpeaking } from './speech';

const CHIPS: { label: string; icon: ReactNode }[] = [
  { label: 'Am I free?', icon: <CalendarCheck /> },
  { label: 'How do I get there?', icon: <TrainFront /> },
  { label: 'Add to calendar', icon: <CalendarPlus /> },
  { label: 'Remind me', icon: <BellRing /> },
];

const SOURCE_META: Record<Target['source'], { label: string; icon: ReactNode }> = {
  selection: { label: 'Selection', icon: <TextCursor /> },
  gaze: { label: 'Looking at', icon: <Eye /> },
  pointer: { label: 'Pointing at', icon: <MousePointer2 /> },
  page: { label: 'This page', icon: <Globe /> },
};

/** After this long without an answer the orb switches to "searching" with a filler line. */
const SEARCHING_AFTER_MS = 1200;

interface Checkpoint {
  title: string;
  preview?: string;
  run: () => void;
}

function nowIso(): string {
  const d = new Date();
  const off = -d.getTimezoneOffset();
  const pad = (n: number) => String(Math.floor(Math.abs(n))).padStart(2, '0');
  const local = new Date(d.getTime() + off * 60_000).toISOString().slice(0, 19);
  return `${local}${off >= 0 ? '+' : '-'}${pad(off / 60)}:${pad(off % 60)}`;
}

export function OverlayApp({ host }: { host: Host }) {
  const [settings, setSettings] = useState<UiSettings>({ largeMode: false, readAloud: false, lang: 'en' });
  const large = settings.largeMode;
  const readAloud = large || settings.readAloud;

  const [target, setTarget] = useState<Target>();
  const [collapsed, setCollapsed] = useState(false);
  const [phase, setPhase] = useState<OrbState>('idle');
  const [level, setLevel] = useState(0);
  const [transcript, setTranscript] = useState('');
  const [intent, setIntent] = useState<string>();
  const [say, setSay] = useState('');
  const [filler, setFiller] = useState('');
  const [badge, setBadge] = useState<string>();
  const [confirm, setConfirm] = useState<Checkpoint>();
  const [actionBusy, setActionBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [draft, setDraft] = useState('');
  const [menuOpen, setMenuOpen] = useState(false);
  const [maxHeight, setMaxHeight] = useState<number>();

  const turnRef = useRef(0);
  const phaseRef = useRef<OrbState>('idle');
  phaseRef.current = phase;
  const settingsRef = useRef(settings);
  settingsRef.current = settings;
  const targetRef = useRef<Target | undefined>(undefined);
  targetRef.current = target;
  const stopTimer = useRef<number | undefined>(undefined);
  const rootRef = useRef<HTMLDivElement>(null);
  const pillRef = useRef<HTMLDivElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    void host.settings.get().then(setSettings);
    return host.settings.watch(setSettings);
  }, [host]);

  // ---- Layout reporting: the shell sizes its frame and glass to these shapes ------------------

  const reportLayout = useCallback(() => {
    const root = rootRef.current;
    if (!root) return;
    const r = root.getBoundingClientRect();
    const shapes = [pillRef.current, panelRef.current]
      .filter((el): el is HTMLDivElement => !!el)
      .map((el) => {
        const b = el.getBoundingClientRect();
        return { x: b.left, y: b.top, w: b.width, h: b.height, r: parseFloat(getComputedStyle(el).borderTopLeftRadius) };
      });
    host.shell.layout({ width: Math.ceil(r.right), height: Math.ceil(r.bottom), shapes });
  }, [host]);

  useLayoutEffect(() => {
    const ro = new ResizeObserver(reportLayout);
    [rootRef.current, pillRef.current, panelRef.current].forEach((el) => el && ro.observe(el));
    reportLayout();
    return () => ro.disconnect();
  });

  // ---- Turns ----------------------------------------------------------------------------------

  const speakLine = useCallback(async (text: string, turn: number, endPhase: OrbState) => {
    const s = settingsRef.current;
    if ((s.largeMode || s.readAloud) && text) {
      setPhase('speaking');
      await speak(text, s.lang, s.largeMode);
    }
    if (turnRef.current === turn) setPhase(endPhase);
  }, []);

  const onError = useCallback((msg: string) => setError(msg), []);

  /** A server action from a card (A2UI `action` message): the human checkpoint goes through here. */
  const sendAction = useCallback(
    async (payload: ActionPayload) => {
      const turn = ++turnRef.current;
      stopSpeaking();
      setConfirm(undefined);
      setActionBusy(true);
      setError(undefined);
      setPhase('thinking');
      const res = await host.backend.action({
        version: A2UI_VERSION,
        action: {
          name: payload.name,
          surfaceId: payload.surfaceId,
          sourceComponentId: payload.sourceComponentId,
          timestamp: payload.timestamp,
          context: payload.context,
        },
      });
      if (turnRef.current !== turn) return;
      setActionBusy(false);
      if (!res.ok) {
        setError(res.error);
        setPhase('idle');
        return;
      }
      const r = res.data;
      a2ui.process(r.cards ?? []);
      if (r.status === 'done') {
        const link = r.result?.message_sent?.deep_link;
        a2ui.process(
          doneSurface(`done_${r.action_id}`, r.message ?? r.say, undefined, link ? { label: 'Open to send', url: link } : undefined),
        );
        setSay(r.say);
        setPhase('done');
        await speakLine(r.say, turn, 'done');
        window.setTimeout(() => {
          if (turnRef.current === turn) setPhase('idle');
        }, 2600);
        return;
      }
      if (r.status === 'failed' || r.status === 'not_found') {
        setError(r.status === 'not_found' ? 'That action expired. Ask again.' : (r.message ?? 'That did not work.'));
        setPhase('idle');
        return;
      }
      setSay(r.say || r.message || '');
      await speakLine(r.say, turn, 'idle');
    },
    [host, speakLine],
  );

  const a2ui = useA2ui(
    (payload) => void sendAction(payload),
    onError,
  );

  const submit = useCallback(
    async (text: string) => {
      const trimmed = text.trim();
      if (!trimmed) return;
      const turn = ++turnRef.current;
      stopSpeaking();
      a2ui.reset();
      setIntent(trimmed);
      setDraft('');
      setTranscript('');
      setSay('');
      setFiller('');
      setBadge(undefined);
      setConfirm(undefined);
      setError(undefined);
      setPhase('thinking');
      const t = targetRef.current;
      const res = await host.backend.intent(
        {
          intent: trimmed,
          context: t?.context ?? { url: '', title: '' },
          locale: settingsRef.current.lang,
          now: nowIso(),
        },
        (e) => {
          if (turnRef.current !== turn) return;
          if (e.event === 'orb') setPhase(e.data.state);
          else if (e.event === 'filler') setFiller(e.data.say);
        },
      );
      if (turnRef.current !== turn) return;
      setFiller('');
      if (!res.ok) {
        setError(res.error);
        setPhase('idle');
        return;
      }
      a2ui.process(res.data.cards ?? []);
      setSay(res.data.say);
      setBadge(res.mocked ? 'Mock backend' : res.data.source === 'fallback' ? 'Fallback' : undefined);
      await speakLine(res.data.say, turn, 'idle');
    },
    [host, speakLine, a2ui],
  );

  /** Runs a card button: local functions here, server events through the processor. */
  const run = useCallback(
    (action: A2uiAction | undefined, ctx: ComponentContext, opts?: RunOptions) => {
      if (!action) return;
      if (action.functionCall) {
        const url = action.functionCall.args?.url;
        if (action.functionCall.call === 'openUrl' && typeof url === 'string') host.shell.openUrl(url);
        return;
      }
      if (!action.event) return;
      const dispatch = () => void ctx.dispatchAction({ event: action.event });
      if (opts?.checkpoint && action.event.name === 'confirm') {
        setConfirm({ title: action.label ?? 'Confirm', preview: action.preview, run: dispatch });
      } else dispatch();
    },
    [host],
  );

  const rejectConfirm = useCallback(() => setConfirm(undefined), []);

  // ---- Voice ----------------------------------------------------------------------------------

  const startListening = useCallback(async () => {
    if (phaseRef.current === 'listening') return;
    turnRef.current++;
    stopSpeaking();
    setConfirm(undefined);
    setError(undefined);
    setTranscript('');
    setIntent(undefined);
    setLevel(0);
    setCollapsed(false);
    setPhase('listening');
    try {
      await host.voice.start(settingsRef.current.lang);
    } catch (err) {
      setError((err as Error).message || 'Voice is unavailable. Type your request instead.');
      setPhase('idle');
    }
  }, [host]);

  const stopListening = useCallback(() => {
    if (phaseRef.current !== 'listening') return;
    void host.voice.stop();
    setLevel(0);
    window.clearTimeout(stopTimer.current);
    stopTimer.current = window.setTimeout(() => {
      if (phaseRef.current === 'listening') {
        void host.voice.cancel();
        setPhase('idle');
        setError("Didn't catch that. Try again or type it.");
      }
    }, 7000);
  }, [host]);

  useEffect(
    () =>
      host.voice.subscribe((e) => {
        switch (e.event) {
          case 'level':
            setLevel(e.level);
            break;
          case 'transcript':
            if (phaseRef.current === 'listening') setTranscript(e.text);
            break;
          case 'final':
            window.clearTimeout(stopTimer.current);
            if (phaseRef.current !== 'listening') break;
            if (e.text) void submit(e.text);
            else {
              setPhase('idle');
              setError("Didn't catch that. Hold the orb while you speak.");
            }
            break;
          case 'error':
            window.clearTimeout(stopTimer.current);
            setError(e.message);
            setPhase('idle');
            break;
        }
      }),
    [host, submit],
  );

  const close = useCallback(() => {
    turnRef.current++;
    void host.voice.cancel();
    stopSpeaking();
    setPhase('idle');
    setMenuOpen(false);
    host.shell.close();
  }, [host]);

  const stopAll = useCallback(() => {
    if (phaseRef.current === 'idle' || phaseRef.current === 'done') {
      if (!confirm) {
        close();
        return;
      }
    }
    turnRef.current++;
    void host.voice.cancel();
    stopSpeaking();
    setConfirm(undefined);
    setActionBusy(false);
    setPhase('idle');
  }, [close, confirm, host, rejectConfirm]);

  // ---- Shell events ---------------------------------------------------------------------------

  useEffect(
    () =>
      host.shell.onOpen((t) => {
        turnRef.current++;
        void host.voice.cancel();
        stopSpeaking();
        setTarget(t);
        setCollapsed(false);
        a2ui.reset();
        setSay('');
        setBadge(undefined);
        setIntent(undefined);
        setConfirm(undefined);
        setError(undefined);
        setTranscript('');
        setPhase('idle');
      }),
    [host, a2ui],
  );

  useEffect(
    () =>
      host.shell.onHide(() => {
        turnRef.current++;
        void host.voice.cancel();
        stopSpeaking();
        setPhase('idle');
        setMenuOpen(false);
      }),
    [host],
  );

  useEffect(() => host.shell.onMaxHeight(setMaxHeight), [host]);

  useEffect(
    () => host.shell.onPushToTalk((down) => (down ? void startListening() : stopListening())),
    [host, startListening, stopListening],
  );

  // Keys while the overlay itself has focus: hold Option/Alt to talk, Escape to back out.
  useEffect(() => {
    let holdTimer: number | undefined;
    let holding = false;
    const down = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (menuOpen) setMenuOpen(false);
        else if (confirm) rejectConfirm();
        else close();
      } else if (e.key === 'Alt' && !e.repeat && !e.shiftKey && !e.metaKey && !e.ctrlKey) {
        holdTimer = window.setTimeout(() => {
          holding = true;
          void startListening();
        }, 220);
      } else window.clearTimeout(holdTimer);
    };
    const up = (e: KeyboardEvent) => {
      if (e.key !== 'Alt') return;
      window.clearTimeout(holdTimer);
      if (holding) {
        holding = false;
        stopListening();
      }
    };
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
    };
  }, [close, confirm, menuOpen, rejectConfirm, startListening, stopListening]);

  // The options menu closes on any click outside it, including clicks on the page itself.
  useEffect(() => {
    if (!menuOpen) return;
    const away = (e: PointerEvent) => {
      if (!menuRef.current?.contains(e.target as Node)) setMenuOpen(false);
    };
    const blur = () => setMenuOpen(false);
    window.addEventListener('pointerdown', away);
    window.addEventListener('blur', blur);
    return () => {
      window.removeEventListener('pointerdown', away);
      window.removeEventListener('blur', blur);
    };
  }, [menuOpen]);

  // ---- Render ---------------------------------------------------------------------------------

  const env: CardEnv = useMemo(() => ({ run, busy: actionBusy, large }), [run, actionBusy, large]);

  const busy = phase === 'thinking' || phase === 'searching' || phase === 'listening';
  const bubble = phase === 'listening' ? transcript || 'Listening…' : intent;
  const source = target ? SOURCE_META[target.source] : undefined;
  const orbSize = large ? 52 : 40;

  return (
    <div
      ref={rootRef}
      className="mi-root"
      data-large={large || undefined}
      style={maxHeight ? ({ '--max-h': `${maxHeight}px` } as CSSProperties) : undefined}
    >
      <div
        ref={pillRef}
        className="mi-pill"
        onPointerDown={(e) => {
          if (e.target !== e.currentTarget) return;
          e.currentTarget.setPointerCapture(e.pointerId);
          let last = { x: e.screenX, y: e.screenY };
          const move = (ev: PointerEvent) => {
            host.shell.drag(ev.screenX - last.x, ev.screenY - last.y);
            last = { x: ev.screenX, y: ev.screenY };
          };
          const up = () => {
            e.currentTarget.removeEventListener('pointermove', move);
            e.currentTarget.removeEventListener('pointerup', up);
          };
          e.currentTarget.addEventListener('pointermove', move);
          e.currentTarget.addEventListener('pointerup', up);
        }}
      >
        <button
          type="button"
          className="mi-orb-btn"
          aria-label={phase === 'listening' ? 'Release to send' : 'Hold to talk'}
          title="Hold to talk (or hold ⌥)"
          onPointerDown={(e) => {
            e.currentTarget.setPointerCapture(e.pointerId);
            void startListening();
          }}
          onPointerUp={stopListening}
          onPointerCancel={stopListening}
        >
          <Orb state={phase} level={level} size={orbSize} />
        </button>
        <button type="button" className="mi-pill-btn" onClick={() => setCollapsed((c) => !c)}>
          {collapsed ? <ChevronUp /> : <ChevronDown />}
          {collapsed ? 'Show' : 'Hide'}
        </button>
        <button
          type="button"
          className="mi-pill-stop"
          aria-label={phase === 'idle' || phase === 'done' ? 'Close' : 'Stop'}
          title={phase === 'idle' || phase === 'done' ? 'Close' : 'Stop'}
          onClick={stopAll}
        >
          <span />
        </button>
      </div>

      <AnimatePresence initial={false}>
        {!collapsed && (
          <motion.div
            key="panel"
            ref={panelRef}
            className="mi-panel"
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ type: 'spring', stiffness: 420, damping: 40 }}
          >
            <div className="mi-panel-inner">
              <div className="mi-scroll">
                {(bubble || badge) && (
                  <div className="mi-top">
                    {badge && <span className="mi-badge">{badge}</span>}
                    {bubble && (
                      <motion.span
                        key={phase === 'listening' ? 'live' : bubble}
                        className="mi-intent"
                        data-live={phase === 'listening' || undefined}
                        initial={{ opacity: 0, y: -4 }}
                        animate={{ opacity: 1, y: 0 }}
                      >
                        {bubble}
                      </motion.span>
                    )}
                  </div>
                )}

                {(phase === 'thinking' || phase === 'searching') && (
                  <div className="mi-thinking">
                    <span className="mi-shimmer">
                      {actionBusy ? 'Doing it…' : filler || (phase === 'searching' ? 'Checking your calendar…' : 'Thinking…')}
                    </span>
                  </div>
                )}

                {error && (
                  <div className="mi-error" role="alert">
                    <TriangleAlert />
                    <span>{error}</span>
                  </div>
                )}

                <AnimatePresence initial={false}>
                  {confirm && (
                    <ConfirmSheet
                      key="confirm"
                      title={confirm.title}
                      preview={confirm.preview}
                      busy={actionBusy}
                      onConfirm={confirm.run}
                      onCancel={rejectConfirm}
                    />
                  )}
                </AnimatePresence>

                {say && <p className="mi-say">“{say}”</p>}
                {a2ui.surfaces.length > 0 && (
                  <div className="mi-result" data-dimmed={confirm ? true : undefined}>
                    <CardEnvContext.Provider value={env}>
                      <Surfaces surfaces={a2ui.surfaces} />
                    </CardEnvContext.Provider>
                  </div>
                )}
              </div>

              <div className="mi-chips" role="toolbar" aria-label="Suggestions">
                {CHIPS.map((chip, i) => (
                  <Fragment key={chip.label}>
                    {i > 0 && <span className="mi-dot" aria-hidden />}
                    <button type="button" className="mi-chip" disabled={busy} onClick={() => void submit(chip.label)}>
                      {chip.icon}
                      {chip.label}
                    </button>
                  </Fragment>
                ))}
              </div>

              <form
                className="mi-input"
                onSubmit={(e) => {
                  e.preventDefault();
                  void submit(draft);
                }}
              >
                <div className="mi-input-line">
                  <input
                    value={draft}
                    onChange={(e) => setDraft(e.target.value)}
                    aria-label="Ask about this"
                  />
                  {!draft && (
                    <span className="mi-input-hint" aria-hidden>
                      Ask about this, or hold <kbd>⌥</kbd> to talk
                    </span>
                  )}
                </div>
                <div className="mi-input-row">
                  {source && (
                    <span className="mi-context" title={target?.snippet}>
                      {source.icon}
                      <b>{source.label}</b>
                      {target?.snippet && <span>{target.snippet}</span>}
                    </span>
                  )}
                  <div className="mi-menu-wrap" ref={menuRef}>
                    <button
                      type="button"
                      className="mi-more"
                      aria-label="Options"
                      aria-expanded={menuOpen}
                      onClick={() => setMenuOpen((m) => !m)}
                    >
                      <Ellipsis />
                    </button>
                    <AnimatePresence>
                      {menuOpen && (
                        <motion.div
                          className="mi-menu"
                          initial={{ opacity: 0, y: 6 }}
                          animate={{ opacity: 1, y: 0 }}
                          exit={{ opacity: 0, y: 6 }}
                        >
                          <Toggle
                            label="Large mode"
                            hint="Bigger text and buttons, reads aloud"
                            on={large}
                            onChange={(v) => void host.settings.update({ largeMode: v })}
                          />
                          <Toggle
                            label="Read answers aloud"
                            on={readAloud}
                            disabled={large}
                            onChange={(v) => void host.settings.update({ readAloud: v })}
                          />
                          <Toggle
                            label="Deutsch"
                            on={settings.lang === 'de'}
                            onChange={(v) => void host.settings.update({ lang: v ? 'de' : 'en' })}
                          />
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </div>
                  <button type="submit" className="mi-send" aria-label="Send" disabled={!draft.trim() || busy}>
                    <Play />
                  </button>
                </div>
              </form>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function Toggle(props: { label: string; hint?: string; on: boolean; disabled?: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="mi-toggle" data-disabled={props.disabled || undefined}>
      <span>
        {props.label}
        {props.hint && <small>{props.hint}</small>}
      </span>
      <input
        type="checkbox"
        role="switch"
        checked={props.on}
        disabled={props.disabled}
        onChange={(e) => props.onChange(e.target.checked)}
      />
      <i aria-hidden />
    </label>
  );
}
