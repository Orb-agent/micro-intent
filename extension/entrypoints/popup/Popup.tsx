import { Mic, RotateCcw, Sparkles } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { ApiResult } from '@/src/api/types';
import type { ApiCall, ToBackground } from '@/lib/messages';
import { DEFAULT_SETTINGS, getSettings, updateSettings, type BackendMode, type Settings } from '@/lib/settings';

type Health = { state: 'checking' } | { state: 'ok'; detail: string } | { state: 'mock' } | { state: 'down'; detail: string };

async function api(call: ApiCall): Promise<ApiResult<Record<string, unknown>>> {
  const msg: ToBackground = { type: 'mi:api', call };
  return (await browser.runtime.sendMessage(msg)) as ApiResult<Record<string, unknown>>;
}

export function Popup() {
  const [s, setS] = useState<Settings>(DEFAULT_SETTINGS);
  const [url, setUrl] = useState(DEFAULT_SETTINGS.backendUrl);
  const [health, setHealth] = useState<Health>({ state: 'checking' });
  const [note, setNote] = useState('');

  const check = async () => {
    setHealth({ state: 'checking' });
    const res = await api({ op: 'health' });
    if (!res.ok) setHealth({ state: 'down', detail: res.error });
    else if (res.mocked) setHealth({ state: 'mock' });
    else {
      const d = res.data;
      setHealth({ state: 'ok', detail: [d.model, d.calendar && `calendar: ${d.calendar}`].filter(Boolean).join(' · ') });
    }
  };

  useEffect(() => {
    void getSettings().then((v) => {
      setS(v);
      setUrl(v.backendUrl);
      void check();
    });
  }, []);

  const save = async (patch: Partial<Settings>) => {
    const next = await updateSettings(patch);
    setS(next);
    if (patch.largeMode !== undefined || patch.lang !== undefined) {
      void api({ op: 'profile', body: { large_mode: next.largeMode, locale: next.lang } });
    }
    if (patch.backendUrl !== undefined || patch.backendMode !== undefined) void check();
  };

  return (
    <main data-large={s.largeMode || undefined}>
      <header>
        <span className="logo">
          <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path
              d="M2.5 12c2.3-4.2 5.6-6.3 9.5-6.3s7.2 2.1 9.5 6.3c-2.3 4.2-5.6 6.3-9.5 6.3S4.8 16.2 2.5 12Z"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinejoin="round"
            />
            <circle cx="12" cy="12" r="3.2" fill="currentColor" />
          </svg>
        </span>
        <div>
          <h1>Micro Intent</h1>
          <p>Look at it, say it, approve it.</p>
        </div>
      </header>

      <button
        className="primary"
        type="button"
        onClick={() => {
          void browser.runtime.sendMessage({ type: 'mi:open-active-tab' } satisfies ToBackground);
          window.close();
        }}
      >
        <Sparkles /> Ask about this page <kbd>⌥⇧M</kbd>
      </button>

      <section>
        <h2>Profile</h2>
        <Switch label="Large mode" hint="Big text and buttons, answers read aloud" on={s.largeMode} onChange={(v) => save({ largeMode: v })} />
        <Switch
          label="Read answers aloud"
          on={s.largeMode || s.readAloud}
          disabled={s.largeMode}
          onChange={(v) => save({ readAloud: v })}
        />
        <Switch label="Deutsch" on={s.lang === 'de'} onChange={(v) => save({ lang: v ? 'de' : 'en' })} />
      </section>

      <section>
        <h2>Backend</h2>
        <form
          className="row"
          onSubmit={(e) => {
            e.preventDefault();
            void save({ backendUrl: url.trim() || DEFAULT_SETTINGS.backendUrl });
          }}
        >
          <input value={url} onChange={(e) => setUrl(e.target.value)} aria-label="Backend URL" spellCheck={false} />
          <button type="submit" disabled={url === s.backendUrl}>
            Save
          </button>
        </form>
        <div className="seg" role="radiogroup" aria-label="Backend mode">
          {(['auto', 'live', 'mock'] as BackendMode[]).map((m) => (
            <button key={m} type="button" role="radio" aria-checked={s.backendMode === m} onClick={() => save({ backendMode: m })}>
              {m === 'auto' ? 'Auto' : m === 'live' ? 'Backend only' : 'Mock'}
            </button>
          ))}
        </div>
        <p className={`health ${health.state}`}>
          <i />
          {health.state === 'checking' && 'Checking…'}
          {health.state === 'ok' && `Connected${health.detail ? ` · ${health.detail}` : ''}`}
          {health.state === 'mock' && 'Using the local mock (backend not reachable)'}
          {health.state === 'down' && health.detail}
        </p>
      </section>

      <section className="buttons">
        <button type="button" onClick={() => browser.tabs.create({ url: browser.runtime.getURL('/mic-permission.html') })}>
          <Mic /> Enable microphone
        </button>
        <button
          type="button"
          onClick={async () => {
            const res = await api({ op: 'demo-reset' });
            setNote(res.ok ? 'Demo data reset.' : res.error);
          }}
        >
          <RotateCcw /> Reset demo
        </button>
      </section>
      {note && <p className="note">{note}</p>}
    </main>
  );
}

function Switch(p: { label: string; hint?: string; on: boolean; disabled?: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="switch" data-disabled={p.disabled || undefined}>
      <span>
        {p.label}
        {p.hint && <small>{p.hint}</small>}
      </span>
      <input type="checkbox" role="switch" checked={p.on} disabled={p.disabled} onChange={(e) => p.onChange(e.target.checked)} />
      <i aria-hidden />
    </label>
  );
}
