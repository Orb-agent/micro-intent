const time = new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Zurich' });
const day = new Intl.DateTimeFormat('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Europe/Zurich' });
const dayKey = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Zurich' });

function parse(iso: string | undefined): Date | undefined {
  if (!iso) return undefined;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? undefined : d;
}

export function fmtTime(iso: string | undefined): string {
  const d = parse(iso);
  return d ? time.format(d) : (iso ?? '');
}

export function fmtDay(iso: string | undefined): string {
  const d = parse(iso);
  if (!d) return '';
  const today = new Date();
  const tomorrow = new Date(today.getTime() + 86_400_000);
  if (dayKey.format(d) === dayKey.format(today)) return 'Today';
  if (dayKey.format(d) === dayKey.format(tomorrow)) return 'Tomorrow';
  return day.format(d);
}

export function fmtRange(start: string | undefined, end?: string): string {
  const s = fmtTime(start);
  return end ? `${s}–${fmtTime(end)}` : s;
}

export function minutesBetween(a: string | undefined, b: string | undefined): number | undefined {
  const da = parse(a);
  const db = parse(b);
  if (!da || !db) return undefined;
  return Math.round((db.getTime() - da.getTime()) / 60000);
}

export function fmtDuration(min: number | undefined): string {
  if (min === undefined) return '';
  const h = Math.floor(min / 60);
  const m = min % 60;
  return h ? `${h} h${m ? ` ${m} min` : ''}` : `${m} min`;
}
