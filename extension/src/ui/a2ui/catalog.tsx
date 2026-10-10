// The trusted A2UI component catalog (docs/API.md, catalog https://micro-intent.app/a2ui/catalog/v1).
// The agent picks components by name; anything not listed here is rejected by the renderer,
// so the model never ships UI code.
import { createBinderlessComponentImplementation, type ReactComponentImplementation } from '@a2ui/react/v0_9';
import { Catalog, type ComponentContext } from '@a2ui/web_core/v0_9';
import {
  ArrowRight,
  BellRing,
  CalendarCheck,
  CalendarDays,
  CheckCircle2,
  ExternalLink,
  MapPin,
  MessageSquareText,
  Radio,
  ShieldCheck,
  TrainFront,
  TriangleAlert,
} from 'lucide-react';
import { motion } from 'motion/react';
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { z } from 'zod';
import { fmtDay, fmtDuration, fmtRange, fmtTime } from '../format';
import { Orb as OrbView, type OrbState } from '../Orb';
import { CATALOG_ID, type A2uiAction } from './protocol';

// ---- Environment shared by every card ---------------------------------------------------------

export interface RunOptions {
  /**
   * Show the confirm sheet before dispatching. Used for write actions on cards that are not
   * themselves a checkpoint (EventCard, ConflictCard); ConfirmCard, ReminderCard and
   * MessageDraftCard show their preview inline and are the checkpoint.
   */
  checkpoint?: boolean;
}

export interface CardEnv {
  run: (action: A2uiAction | undefined, ctx: ComponentContext, opts?: RunOptions) => void;
  /** An action is in flight; buttons are disabled. */
  busy: boolean;
  large: boolean;
}

export const CardEnvContext = createContext<CardEnv>({ run: () => {}, busy: false, large: false });

const useEnv = () => useContext(CardEnvContext);

type ViewProps<T> = { p: T; ctx: ComponentContext };

/** Re-renders when the agent updates the component. */
function useProps<T>(ctx: ComponentContext): T {
  const [props, setProps] = useState(() => ctx.componentModel.properties as T);
  useEffect(() => {
    const sub = ctx.componentModel.onUpdated.subscribe((m) => setProps(m.properties as T));
    return () => sub.unsubscribe();
  }, [ctx]);
  return props;
}

function component<T>(name: string, View: (props: ViewProps<T>) => ReactNode): ReactComponentImplementation {
  function Bound({ ctx }: { ctx: ComponentContext }) {
    const p = useProps<T>(ctx);
    return <View p={p} ctx={ctx} />;
  }
  return createBinderlessComponentImplementation({ name, schema: z.object({}).passthrough() }, ({ context }) => (
    <Bound ctx={context} />
  ));
}

// ---- Building blocks --------------------------------------------------------------------------

function Card({ kind, children }: { kind: string; children: ReactNode }) {
  return (
    <motion.section
      className={`mi-card mi-card-${kind}`}
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: 'spring', stiffness: 380, damping: 30 }}
    >
      {children}
    </motion.section>
  );
}

function CardHead({ icon, label, trailing }: { icon: ReactNode; label: ReactNode; trailing?: ReactNode }) {
  return (
    <header className="mi-card-head">
      <span className="mi-card-icon">{icon}</span>
      <span className="mi-card-label">{label}</span>
      {trailing && <span className="mi-card-trailing">{trailing}</span>}
    </header>
  );
}

type ButtonStyle = 'primary' | 'secondary' | 'ghost';

interface ButtonSpec {
  action?: A2uiAction;
  label: string;
  style: ButtonStyle;
  write?: boolean;
  checkpoint?: boolean;
  icon?: ReactNode;
}

function Buttons({ ctx, buttons }: { ctx: ComponentContext; buttons: ButtonSpec[] }) {
  const env = useEnv();
  const shown = buttons.filter((b) => b.action);
  if (shown.length === 0) return null;
  return (
    <div className="mi-actions">
      {shown.map((b) => (
        <button
          key={b.label}
          type="button"
          className="mi-btn"
          data-style={b.style}
          disabled={env.busy && !b.action?.functionCall}
          onClick={() => env.run(b.action, ctx, { checkpoint: b.checkpoint })}
        >
          {b.icon ?? (b.write ? <ShieldCheck /> : null)}
          {b.label}
        </button>
      ))}
    </div>
  );
}

function Preview({ text }: { text?: string }) {
  if (!text) return null;
  return (
    <p className="mi-preview">
      <ShieldCheck />
      <span>{text}</span>
    </p>
  );
}

// ---- Components --------------------------------------------------------------------------------

interface OrbProps {
  state: OrbState;
}

const Orb = component<OrbProps>('Orb', ({ p }) => <OrbView state={p.state ?? 'idle'} size={40} />);

interface EventProps {
  title: string;
  start: string;
  end?: string;
  location?: string;
  url?: string;
  availability: 'free' | 'conflict' | 'unknown';
  inCalendar?: boolean;
  addAction?: A2uiAction;
}

const AVAILABILITY = {
  free: { label: "You're free", icon: <CheckCircle2 /> },
  conflict: { label: 'Conflict', icon: <TriangleAlert /> },
} as const;

const EventCard = component<EventProps>('EventCard', ({ p, ctx }) => {
  const a = p.availability === 'free' || p.availability === 'conflict' ? AVAILABILITY[p.availability] : undefined;
  return (
    <Card kind="event">
      <CardHead
        icon={<CalendarDays />}
        label={fmtDay(p.start)}
        trailing={
          p.inCalendar ? (
            <span className="mi-pilltag" data-tone="ok">
              <CalendarCheck /> In your calendar
            </span>
          ) : a ? (
            <span className="mi-pilltag" data-tone={p.availability}>
              {a.icon}
              {a.label}
            </span>
          ) : undefined
        }
      />
      <h3 className="mi-card-title">{p.title}</h3>
      <div className="mi-card-meta">
        <span className="mi-big-time">{fmtRange(p.start, p.end)}</span>
        {p.location && (
          <span className="mi-meta-item">
            <MapPin /> {p.location}
          </span>
        )}
      </div>
      <Buttons
        ctx={ctx}
        buttons={[
          { action: p.addAction, label: p.addAction?.label ?? 'Add to calendar', style: 'primary', write: true, checkpoint: true },
        ]}
      />
    </Card>
  );
});

interface ConflictProps {
  conflict: { eventId?: string; title: string; start: string; end: string; calendar?: string };
  eventTitle: string;
  move?: { label: string; preview: string; newStart: string; newEnd: string; action: A2uiAction };
  skipAction: A2uiAction;
  keepAction: A2uiAction;
}

const ConflictCard = component<ConflictProps>('ConflictCard', ({ p, ctx }) => (
  <Card kind="conflict">
    <CardHead
      icon={<TriangleAlert />}
      label={`Overlaps ${p.eventTitle}`}
      trailing={
        <span className="mi-pilltag" data-tone="conflict">
          {fmtDay(p.conflict.start)}
        </span>
      }
    />
    <ol className="mi-timeline">
      <li data-kind="busy">
        <span className="mi-tl-time">{fmtRange(p.conflict.start, p.conflict.end)}</span>
        <span className="mi-tl-title">
          {p.conflict.title}
          {p.conflict.calendar && <em> · {p.conflict.calendar}</em>}
        </span>
      </li>
      {p.move && (
        <li data-kind="proposal">
          <span className="mi-tl-time">{fmtRange(p.move.newStart, p.move.newEnd)}</span>
          <span className="mi-tl-title">
            {p.conflict.title} <em>· free slot</em>
          </span>
        </li>
      )}
    </ol>
    <Buttons
      ctx={ctx}
      buttons={([
        p.move && {
          action: { ...p.move.action, label: p.move.label, preview: p.move.preview },
          label: p.move.label,
          style: 'primary' as const,
          write: true,
          checkpoint: true,
        },
        { action: p.keepAction, label: 'Keep both', style: 'secondary' as const },
        { action: p.skipAction, label: 'Skip event', style: 'ghost' as const },
      ] as (ButtonSpec | undefined)[]).filter((b): b is ButtonSpec => !!b)}
    />
  </Card>
));

interface Connection {
  departure: string;
  arrival: string;
  durationMin?: number;
  transfers?: number;
  products?: string[];
  platform?: string;
  recommended?: boolean;
  delayMin?: number;
}

interface TrainProps {
  from: string;
  to: string;
  connections: Connection[];
  live: boolean;
  openAction?: A2uiAction;
}

const TrainCard = component<TrainProps>('TrainCard', ({ p, ctx }) => {
  const env = useEnv();
  const all = p.connections ?? [];
  const max = env.large ? 2 : 3;
  // Always show the recommended connection, plus its neighbours.
  const rec = Math.max(0, all.findIndex((c) => c.recommended));
  const start = Math.max(0, Math.min(rec - 1, all.length - max));
  const items = all.slice(start, start + max);
  return (
    <Card kind="train">
      <CardHead
        icon={<TrainFront />}
        label={`${p.from} → ${p.to}`}
        trailing={
          <span className="mi-pilltag" data-tone={p.live ? 'live' : undefined}>
            {p.live ? <Radio /> : null}
            {p.live ? 'Live' : 'Timetable'}
          </span>
        }
      />
      <ul className="mi-trains">
        {items.map((c, i) => (
          <li key={i} data-recommended={c.recommended || undefined}>
            <span className="mi-line">{c.products?.[0] ?? 'Train'}</span>
            <span className="mi-big-time">
              {fmtTime(c.departure)}
              {(c.delayMin ?? 0) > 0 && <span className="mi-delay">+{c.delayMin}</span>}
            </span>
            <span className="mi-train-mid">
              <i />
              <small>
                {fmtDuration(c.durationMin)} · {c.transfers ? `${c.transfers}×` : 'direct'}
              </small>
            </span>
            <span className="mi-big-time">{fmtTime(c.arrival)}</span>
            <span className="mi-platform">{c.platform ? `Pl. ${c.platform}` : ''}</span>
          </li>
        ))}
      </ul>
      <Buttons
        ctx={ctx}
        buttons={[{ action: p.openAction, label: 'Open route', style: 'ghost', icon: <ExternalLink /> }]}
      />
    </Card>
  );
});

interface ReminderProps {
  text: string;
  at: string;
  preview: string;
  confirmAction: A2uiAction;
  rejectAction: A2uiAction;
}

const ReminderCard = component<ReminderProps>('ReminderCard', ({ p, ctx }) => (
  <Card kind="reminder">
    <CardHead icon={<BellRing />} label={fmtDay(p.at)} trailing={<CheckpointTag />} />
    <h3 className="mi-card-title">{p.text}</h3>
    <div className="mi-card-meta">
      <span className="mi-big-time">{fmtTime(p.at)}</span>
    </div>
    <Preview text={p.preview} />
    <Buttons
      ctx={ctx}
      buttons={[
        { action: p.rejectAction, label: 'Not now', style: 'ghost' },
        { action: p.confirmAction, label: 'Set reminder', style: 'primary', write: true },
      ]}
    />
  </Card>
));

interface MessageProps {
  to: { name: string; relation?: string; channel?: string };
  body: string | { path: string };
  preview: string;
  sendAction: A2uiAction;
  discardAction: A2uiAction;
}

function MessageDraftView({ p, ctx }: ViewProps<MessageProps>) {
  const bound = typeof p.body === 'object' ? p.body.path : undefined;
  const [body, setBody] = useState(() =>
    bound ? String(ctx.dataContext.resolveDynamicValue<string>(p.body) ?? '') : String(p.body ?? ''),
  );
  return (
    <Card kind="message">
      <CardHead
        icon={<MessageSquareText />}
        label={`To ${p.to.name}${p.to.relation ? ` (${p.to.relation})` : ''}`}
        trailing={p.to.channel ? <span className="mi-pilltag">{p.to.channel}</span> : <CheckpointTag />}
      />
      <textarea
        className="mi-draft"
        value={body}
        rows={3}
        aria-label={`Message to ${p.to.name}`}
        onChange={(e) => {
          setBody(e.target.value);
          if (bound) ctx.dataContext.set(bound, e.target.value);
        }}
      />
      <Preview text={p.preview} />
      <Buttons
        ctx={ctx}
        buttons={[
          { action: p.discardAction, label: 'Discard', style: 'ghost' },
          { action: p.sendAction, label: 'Send', style: 'primary', write: true },
        ]}
      />
    </Card>
  );
}

const MessageDraftCard = component<MessageProps>('MessageDraftCard', MessageDraftView);

interface ConfirmProps {
  title: string;
  preview: string;
  tool?: string;
  confirmAction: A2uiAction;
  rejectAction: A2uiAction;
}

function CheckpointTag() {
  return (
    <span className="mi-pilltag" data-tone="checkpoint">
      <ShieldCheck /> Needs your OK
    </span>
  );
}

const ConfirmCard = component<ConfirmProps>('ConfirmCard', ({ p, ctx }) => (
  <Card kind="confirm">
    <CardHead icon={<ShieldCheck />} label={p.title} trailing={<CheckpointTag />} />
    <p className="mi-card-body">{p.preview}</p>
    <p className="mi-fine">Nothing changes until you confirm.</p>
    <Buttons
      ctx={ctx}
      buttons={[
        { action: p.rejectAction, label: 'Cancel', style: 'ghost' },
        { action: p.confirmAction, label: 'Confirm', style: 'primary', write: true },
      ]}
    />
  </Card>
));

interface DoneProps {
  title: string;
  text?: string;
  link?: { label: string; url: string };
}

/** Client-side result card after a confirmed action; the backend deletes the action's surface. */
const DoneCard = component<DoneProps>('DoneCard', ({ p, ctx }) => (
  <Card kind="done">
    <div className="mi-done">
      <motion.span
        className="mi-done-check"
        initial={{ scale: 0.4, rotate: -20, opacity: 0 }}
        animate={{ scale: 1, rotate: 0, opacity: 1 }}
        transition={{ type: 'spring', stiffness: 420, damping: 16 }}
      >
        <CheckCircle2 />
      </motion.span>
      <div className="mi-done-text">
        <h3 className="mi-card-title">{p.title}</h3>
        {p.text && <p className="mi-card-body">{p.text}</p>}
      </div>
    </div>
    {p.link && (
      <Buttons
        ctx={ctx}
        buttons={[
          {
            action: { functionCall: { call: 'openUrl', args: { url: p.link.url } } },
            label: p.link.label,
            style: 'secondary',
            icon: <ArrowRight />,
          },
        ]}
      />
    )}
  </Card>
));

export const catalog = new Catalog(CATALOG_ID, 'v0.9', [
  Orb,
  EventCard,
  ConflictCard,
  TrainCard,
  ReminderCard,
  MessageDraftCard,
  ConfirmCard,
  DoneCard,
]);
