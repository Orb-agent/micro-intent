import { useEffect, useRef, useState } from "react";
import {
  ArrowUpRight,
  ArrowRight,
  CalendarDays,
  Check,
  ChevronRight,
  Download,
  Eye,
  MapPin,
  Mic,
  MicOff,
  MousePointer2,
  Plus,
  Settings2,
  Sparkles,
  TrainFront,
  X,
  Plane,
  Link2,
  LoaderCircle,
  Volume2,
  Square,
} from "lucide-react";
import { useGaze } from "./hooks/useGaze";
import { useReadAloud } from "./hooks/useReadAloud";
import { GazeCalibration } from "./components/GazeCalibration";
import { currentPosition, isTravelIntent } from "./location";
type EventContext = {
  image?: string;
  title: string;
  start: string;
  end: string;
  location: string;
  url: string;
};
type Plan = {
  summary: string;
  mode: "demo" | "google";
  conflicts: { id: string; title: string; start: string; end: string }[];
  routes: { mapsUrl: string; flightsUrl: string; sbbUrl: string };
  agents: { name: string; status: string }[];
};
const sample: EventContext = {
  image: "",
  title: "Creative Coding Meetup",
  start: "2026-10-14T18:30:00+02:00",
  end: "2026-10-14T20:30:00+02:00",
  location: "Kraftwerk, Selnaustrasse 25, Zürich",
  url: "https://luma.com/",
};
const fmt = (date: string, options: Intl.DateTimeFormatOptions) =>
  Number.isFinite(Date.parse(date))
    ? new Intl.DateTimeFormat("en-GB", {
        timeZone: "Europe/Zurich",
        ...options,
      }).format(new Date(date))
    : "Date not set";
const time = (date: string) =>
  fmt(date, { hour: "2-digit", minute: "2-digit" });
const safeLink = (url: string) => {
  try {
    return new URL(url).protocol === "https:" ? url : "#";
  } catch {
    return "#";
  }
};
function Beaver() {
  return (
    <svg
      viewBox="0 0 100 110"
      aria-label="Lumi, your beaver companion"
      role="img"
    >
      <ellipse
        cx="81"
        cy="86"
        rx="14"
        ry="22"
        fill="#74573e"
        transform="rotate(30 81 86)"
      />
      <path
        d="m74 76 15 16m-18-5 13 14m-6-28-8 26"
        stroke="#4f402e"
        strokeWidth="2"
      />
      <ellipse cx="47" cy="74" rx="30" ry="31" fill="#ac7648" />
      <circle cx="22" cy="29" r="12" fill="#98643f" />
      <circle cx="69" cy="29" r="12" fill="#98643f" />
      <ellipse cx="46" cy="45" rx="33" ry="29" fill="#b98452" />
      <ellipse cx="46" cy="66" rx="21" ry="25" fill="#e5bc83" />
      <circle cx="33" cy="41" r="4" fill="#202c25" />
      <circle cx="60" cy="41" r="4" fill="#202c25" />
      <circle cx="34" cy="40" r="1.3" fill="white" />
      <circle cx="61" cy="40" r="1.3" fill="white" />
      <ellipse cx="46" cy="53" rx="7" ry="5" fill="#483323" />
      <path d="M40 61h12v11H40z" fill="#fff9e9" />
      <path d="M46 61v10" stroke="#b98452" />
      <ellipse
        cx="20"
        cy="72"
        rx="9"
        ry="16"
        fill="#ac7648"
        transform="rotate(-30 20 72)"
      />
      <ellipse
        cx="71"
        cy="72"
        rx="9"
        ry="16"
        fill="#ac7648"
        transform="rotate(30 71 72)"
      />
      <ellipse cx="30" cy="99" rx="13" ry="7" fill="#815b3b" />
      <ellipse cx="63" cy="99" rx="13" ry="7" fill="#815b3b" />
    </svg>
  );
}
export function App() {
  const [event, setEvent] = useState<EventContext>(() => {
    try {
      const incoming = JSON.parse(
        new URLSearchParams(location.search).get("event") || "null",
      );
      return incoming && typeof incoming.title === "string"
        ? {
            title: "", start: "", end: "", location: "", url: "",
            ...Object.fromEntries(
              Object.entries(incoming).filter(
                ([k, v]) => k in sample && typeof v === "string",
              ),
            ),
          }
        : sample;
    } catch {
      return sample;
    }
  });
  const [query, setQuery] = useState("I want to attend this event");
  const [origin, setOrigin] = useState("");
  const [currentLocation, setCurrentLocation] = useState(true);
  const [locationStatus, setLocationStatus] = useState("");
  const locationOrigin = useRef("");
  const [plan, setPlan] = useState<Plan | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [dialog, setDialog] = useState<
    "settings" | "install" | "review" | "event" | null
  >(null);
  const [token, setToken] = useState("");
  const [clientId, setClientId] = useState("");
  const [googleReady, setGoogleReady] = useState(false);
  const [listening, setListening] = useState(false);
  const [contextSource, setContextSource] = useState("Selected event");
  const [installPrompt, setInstallPrompt] = useState<any>(null);
  const [saved, setSaved] = useState(false);
  const speech = useRef<any>(null);
  const tokenTimer = useRef<ReturnType<typeof setTimeout> | undefined>(
    undefined,
  );
  const gaze = useGaze();
  const readAloud = useReadAloud();
  useEffect(() => {
    fetch("/api/config")
      .then((r) => r.json())
      .then((c) => setClientId(c.googleClientId || ""))
      .catch(() => setError("The server is unavailable. Start Micro Intent and try again."));
    const install = (e: Event) => {
      e.preventDefault();
      setInstallPrompt(e);
    };
    window.addEventListener("beforeinstallprompt", install);
    return () => {
      window.removeEventListener("beforeinstallprompt", install);
      speech.current?.abort();
      clearTimeout(tokenTimer.current);
    };
  }, []);
  useEffect(() => {
    if (!clientId) return;
    if ((window as any).google?.accounts?.oauth2) {
      setGoogleReady(true);
      return;
    }
    const s = document.createElement("script");
    s.src = "https://accounts.google.com/gsi/client";
    s.async = true;
    s.onload = () => setGoogleReady(true);
    s.onerror = () => setError("Google could not load. Check your connection.");
    document.head.appendChild(s);
    return () => {
      s.remove();
    };
  }, [clientId]);
  useEffect(() => {
    if (gaze.status !== "active" || !gaze.point) return;
    const el = document
      .elementFromPoint(gaze.point.x, gaze.point.y)
      ?.closest("[data-context]");
    if (el) setContextSource(`Gaze · ${el.getAttribute("data-context")}`);
  }, [gaze.point, gaze.status]);
  useEffect(() => {
    if (!dialog) return;
    const previous = document.activeElement as HTMLElement | null;
    const modal = document.querySelector<HTMLElement>('[role="dialog"]');
    const selector = "button:not(:disabled),a[href],input,textarea,select";
    modal?.querySelector<HTMLElement>(selector)?.focus();
    const keyboard = (e: KeyboardEvent) => {
      if (e.key === "Escape") setDialog(null);
      if (e.key !== "Tab" || !modal) return;
      const items = Array.from(modal.querySelectorAll<HTMLElement>(selector));
      if (e.shiftKey && document.activeElement === items[0]) {
        e.preventDefault();
        items.at(-1)?.focus();
      } else if (!e.shiftKey && document.activeElement === items.at(-1)) {
        e.preventDefault();
        items[0]?.focus();
      }
    };
    document.addEventListener("keydown", keyboard);
    return () => {
      document.removeEventListener("keydown", keyboard);
      previous?.focus();
    };
  }, [dialog]);
  async function submitIntent(text = query, forceLocation = false) {
    if (!text.trim() || busy) return;
    readAloud.stop();
    setBusy(true);
    setError("");
    setNotice("");
    setPlan(null);
    setSaved(false);
    try {
      let routeOrigin = currentLocation ? locationOrigin.current : origin.trim();
      if (forceLocation || (isTravelIntent(text) && (currentLocation || !routeOrigin))) {
        setCurrentLocation(true);
        setOrigin("");
        locationOrigin.current = "";
        setLocationStatus("Finding your current location…");
        const position = await currentPosition();
        routeOrigin = position.origin;
        locationOrigin.current = position.origin;
        setOrigin("Current location");
        setLocationStatus(`Current location · accurate to about ${Math.max(1, Math.round(position.accuracy))} m`);
      }
      const r = await fetch("/api/plan", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          query: text,
          event,
          origin: routeOrigin,
          accessToken: token || undefined,
        }),
        signal: AbortSignal.timeout(45000),
      });
      const data = await r.json();
      if (r.status === 401) {
        setToken("");
        clearTimeout(tokenTimer.current);
      }
      if (!r.ok) throw new Error(data.error || "Unable to prepare your plan.");
      setPlan(data);
    } catch (e) {
      setLocationStatus("");
      setError(
        e instanceof Error ? e.message : "Unable to connect to the server.",
      );
    } finally {
      setBusy(false);
    }
  }
  function connectGoogle() {
    if (!clientId || !googleReady) {
      setError(
        clientId
          ? "Google is loading. Please try again."
          : "GOOGLE_CLIENT_ID is missing in .env. See the README for OAuth setup.",
      );
      return;
    }
    const client = (window as any).google.accounts.oauth2.initTokenClient({
      client_id: clientId,
      scope: "https://www.googleapis.com/auth/calendar.events",
      callback: (r: any) => {
        if (r.error || !r.access_token) {
          setError("Google did not grant calendar access.");
          return;
        }
        if (!(window as any).google.accounts.oauth2.hasGrantedAllScopes(r, "https://www.googleapis.com/auth/calendar.events")) {
          setError("Calendar permission was not granted. Reconnect and allow Calendar access to check conflicts.");
          return;
        }
        setToken(r.access_token);
        setPlan(null);
        setNotice(
          "Google Calendar connected. Check the event to review your schedule.",
        );
        setError("");
        setDialog(null);
        clearTimeout(tokenTimer.current);
        tokenTimer.current = setTimeout(
          () => {
            setToken("");
            setPlan(null);
            setNotice("Your Google session has expired. Please reconnect.");
          },
          Math.max(0, Number(r.expires_in || 3600) - 60) * 1000,
        );
      },
      error_callback: () =>
        setError("The Google connection was not completed. Please try again."),
    });
    client.requestAccessToken();
  }
  function disconnect() {
    if (token) (window as any).google?.accounts.oauth2.revoke(token);
    setToken("");
    setPlan(null);
    clearTimeout(tokenTimer.current);
    setNotice("Google disconnected.");
  }
  function toggleVoice() {
    readAloud.stop();
    if (listening) {
      speech.current?.stop();
      return;
    }
    const Speech =
      (window as any).SpeechRecognition ||
      (window as any).webkitSpeechRecognition;
    if (!Speech) {
      setError(
        "Voice input is not supported in this browser. Type your intent instead.",
      );
      return;
    }
    const recognition = new Speech();
    speech.current = recognition;
    recognition.lang = "en-US";
    recognition.interimResults = false;
    recognition.onstart = () => {
      setListening(true);
      setError("");
    };
    recognition.onend = () => setListening(false);
    recognition.onerror = (e: any) => {
      setListening(false);
      setError(
        e.error === "not-allowed"
          ? "Allow microphone access to use voice input, or type your intent."
          : "Speech could not be recognized. Please try again.",
      );
    };
    recognition.onresult = (e: any) => {
      const text = e.results[0][0].transcript;
      setQuery(text);
      void submitIntent(text);
    };
    try {
      recognition.start();
    } catch {
      setError("The microphone is unavailable.");
    }
  }
  async function saveEvent() {
    setBusy(true);
    setError("");
    try {
      const r = await fetch("/api/calendar/add", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ event, accessToken: token }),
        signal: AbortSignal.timeout(20000),
      });
      const data = await r.json();
      if (!r.ok || data.saved !== true)
        throw new Error(
          data.error || "Connect Google to save this event to your calendar.",
        );
      setSaved(true);
      setDialog(null);
      setNotice(
        "Event added to Google Calendar. Luma registration is separate.",
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unable to save the event.");
    } finally {
      setBusy(false);
    }
  }
  function downloadICS() {
    if (
      !Number.isFinite(Date.parse(event.start)) ||
      !Number.isFinite(Date.parse(event.end))
    ) {
      setError("Enter the event dates.");
      return;
    }
    const escape = (s: string) =>
      s
        .replace(/\\/g, "\\\\")
        .replace(/\r?\n/g, "\\n")
        .replace(/,/g, "\\,")
        .replace(/;/g, "\\;");
    const stamp = (s: string) =>
      new Date(s)
        .toISOString()
        .replace(/[-:]/g, "")
        .replace(/\.\d{3}/, "");
    const body = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Micro Intent//EN",
      "BEGIN:VEVENT",
      `UID:${crypto.randomUUID()}@micro-intent.local`,
      `DTSTAMP:${stamp(new Date().toISOString())}`,
      `DTSTART:${stamp(event.start)}`,
      `DTEND:${stamp(event.end)}`,
      `SUMMARY:${escape(event.title)}`,
      `LOCATION:${escape(event.location)}`,
      "END:VEVENT",
      "END:VCALENDAR",
    ].join("\r\n");
    const url = URL.createObjectURL(
      new Blob([body], { type: "text/calendar;charset=utf-8" }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = "micro-intent-event.ics";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    setNotice(
      "Calendar file downloaded. Open it to import the event into your calendar.",
    );
  }
  useEffect(() => {
    setPlan(null);
    setSaved(false);
  }, [event]);
  const contextual = (label: string) => ({
    "data-context": label,
    onPointerEnter: () => setContextSource(`Pointer · ${label}`),
    onFocus: () => setContextSource(`Selection · ${label}`),
    onTouchStart: () => setContextSource(`Touch · ${label}`),
  });
  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="brand" href="/" aria-label="Micro Intent home"><span className="brand-orb" /> micro intent</a>
        <span className="header-caption">A little help, right here.</span>
        <div className="top-actions">
          <button className="text-button" onClick={() => setDialog("install")}><Download size={16} /> Install</button>
          <button className="icon-button" aria-label="Connections" onClick={() => setDialog("settings")}><Settings2 size={18} /></button>
        </div>
      </header>
      <main className="workspace">
        <section className="event-column" aria-label="Event context">
          <div className="section-heading"><h1>Your event</h1><button className="text-button" onClick={() => setDialog("event")}><Plus size={15} /> Change event</button></div>
          <div className="date-heading"><span className="timeline-dot" /><strong>{fmt(event.start, {weekday:"long", day:"numeric", month:"long"})}</strong><span>{fmt(event.start,{year:"numeric"})}</span></div>
          <article className="selected-event" {...contextual("this event")} tabIndex={0}>
            <span className="selection-label"><Sparkles size={12} /> Selected for Lumi</span>
            <div className="event-cover">
              {event.image && safeLink(event.image) !== "#" ? <img src={event.image} alt="Event cover" referrerPolicy="no-referrer" /> : <div className="calendar-art"><span>{fmt(event.start,{month:"short"})}</span><strong>{fmt(event.start,{day:"2-digit"})}</strong><div className="cover-orbits"><i/><i/><i/></div><small>MAKE TIME FOR<br/>SOMETHING GOOD.</small></div>}
            </div>
            <div className="event-body">
              <span className="event-source">{event.url === sample.url ? "Sample event" : "From your event page"}</span>
              <h2>{event.title || "Choose an event"}</h2>
              <p className="event-meta" {...contextual("event date")}><CalendarDays size={16} /><span>{time(event.start)} – {time(event.end)} <small>Europe/Zurich</small></span></p>
              <p className="event-meta" {...contextual("event location")}><MapPin size={16} /><span>{event.location || "Add a location"}</span></p>
              <div className="event-actions"><a className="source-link" href={safeLink(event.url)} target="_blank" rel="noreferrer">View event <ArrowUpRight size={14}/></a><button className="text-button" onClick={() => setDialog("event")} aria-label="Edit event context">Edit details</button></div>
            </div>
          </article>
          <div className="context-caption"><MousePointer2 size={14}/><span>Your selected event is Lumi’s context.</span></div>
          <div className="event-bottom-note"><span className="tiny-orb"/><div><strong>Stay in the moment.</strong><p>Check your schedule and plan your journey alongside the event.</p></div></div>
        </section>
        <aside className="companion-column" aria-label="Lumi suggestions">
          <section className="suggestion-panel" aria-busy={busy}>
            <div className="panel-heading"><h2><Sparkles size={17}/> Lumi suggestions</h2><button className="icon-button" aria-label="Companion settings" onClick={() => setDialog("settings")}><Settings2 size={15}/></button></div>
            <p className="for-event">For <strong>{event.title}</strong></p>
            <div className={`progress-line ${busy ? "working" : ""}`}><span/><span/><span/><small>{busy ? "Checking your plan…" : plan ? "Your suggestions are ready" : "Ready when you are"}</small></div>
            <article className="suggestion-card calendar-card">
              <div className="card-heading"><span className="calendar-logo"><small>G</small>31</span><div><h3>{saved ? "Added to Google Calendar" : "Google Calendar"}</h3><p>{token ? "Primary calendar · connected" : "Connect to check your schedule"}</p></div>{token && <Check className="connected-check" size={16}/>}</div>
              {plan ? <div className="availability" aria-live="polite"><span className={`availability-status ${plan.conflicts.length ? "conflict" : "clear"}`}><span/>{plan.conflicts.length ? `${plan.conflicts.length} conflict${plan.conflicts.length === 1 ? "" : "s"} to review` : "You’re free for this event"}</span>{plan.mode === "demo" && <span className="demo-label">Simulated calendar</span>}{plan.conflicts.map(c => <div className="conflict-item" key={c.id}><strong>{c.title}</strong><span>{time(c.start)} – {time(c.end)}</span></div>)}</div> : <p className="card-copy">{fmt(event.start,{month:"short",day:"numeric"})} · {time(event.start)} – {time(event.end)}</p>}
              <button className="primary-link" disabled={busy || saved} onClick={() => plan ? setDialog("review") : token ? void submitIntent("Check my availability for this event") : connectGoogle()}>{saved ? "Added to calendar" : plan ? "Review calendar entry" : token ? "Check availability" : "Connect Google Calendar"}{saved ? <Check size={14}/> : <ArrowRight size={14}/>}</button>
              <p className="card-footnote">{plan ? "Confirm before adding. Registration is separate." : "Your calendar changes only after you confirm."}</p>
            </article>
            <article className="suggestion-card journey-card">
              <div className="card-heading"><span className="train-logo"><TrainFront size={20}/></span><div><h3>Find your way there</h3><p>Public transport · SBB & Maps</p></div></div>
              <div className="journey-fields"><label><span>From</span><input aria-label="Starting point" value={origin} disabled={busy} placeholder="Current location or a place" onChange={e => {setOrigin(e.target.value);setCurrentLocation(!e.target.value.trim());setLocationStatus("");setPlan(null);}}/></label><div className="journey-connector"><i/><span/><i/></div><div className="destination-row"><span>To</span><strong>{event.location || "Add an event location"}</strong></div></div>
              <button className="text-button location-button" disabled={busy} onClick={() => void submitIntent("How do I get there from my current location?", true)}><MapPin size={12}/>Use current location</button>
              {locationStatus && <p className="card-footnote" role="status">{locationStatus}</p>}
              {plan ? <div className="journey-links"><a href={safeLink(plan.routes.sbbUrl)} target="_blank" rel="noreferrer">Search SBB <ArrowUpRight size={13}/></a><a href={safeLink(plan.routes.mapsUrl)} target="_blank" rel="noreferrer">View map <ArrowUpRight size={13}/></a></div> : <button className="secondary-button" disabled={busy} onClick={() => void submitIntent("How do I get there?")}>Find transport <ArrowRight size={14}/></button>}
              <p className="card-footnote">Arrive by {fmt(event.start,{month:"short",day:"numeric"})} · {time(event.start)} Zurich time</p>
              <details className="more-options"><summary>Location & departure details<ChevronRight size={12}/></summary><div>Travel questions request your location unless you enter a place. The planner uses it to prepare your route; Maps receives it when opened. It is not saved or sent to the AI model.<p>Choose “Arrive by” in Maps and set the event date and time to check when to leave. Live times and fares come from the provider.</p></div></details>
            </article>
            <details className="more-options"><summary>More options <ChevronRight size={14}/></summary><div>{plan && <a href={safeLink(plan.routes.flightsUrl)} target="_blank" rel="noreferrer"><Plane size={15}/> Search flights <ArrowUpRight size={13}/></a>}{plan && <p>{plan.summary}</p>}{plan && readAloud.supported && <button className="text-button" onClick={() => readAloud.speaking ? readAloud.stop() : readAloud.speak(plan.summary)}>{readAloud.speaking ? <Square size={14}/> : <Volume2 size={14}/>} {readAloud.speaking ? "Stop reading" : "Listen to summary"}</button>}{!plan && <p>Check this event to see your summary and flight search.</p>}<button className="text-button" disabled={busy} onClick={() => void submitIntent()}>Refresh suggestions</button></div></details>
            <form className="intent-form" onSubmit={e => {e.preventDefault();void submitIntent();}}><input aria-label="What would you like to do?" value={query} onChange={e => setQuery(e.target.value)} placeholder="Ask Lumi about this event…" maxLength={1000}/><button className="send" type="submit" disabled={busy || !query.trim()} aria-label="Check event">{busy ? <LoaderCircle size={16} className="spin"/> : <ArrowRight size={16}/>}</button></form>
            <p className="panel-footnote">{plan?.mode === "demo" ? "Demo data · Connect Google for real availability" : token ? "Calendar connected · Review before adding" : "Context from your event · You stay in control"}</p>
          </section>
          <div className="companion-dock"><div className="control-bar"><button className={`voice-control ${listening ? "active" : ""}`} onClick={toggleVoice} aria-label={listening ? "Stop voice input" : "Speak your intent"}>{listening ? <MicOff size={15}/> : <Mic size={15}/>}</button><span className={`voice-state ${busy || listening ? "working" : ""}`}><i/><i/><i/><i/>{listening ? "Listening" : busy ? "Working" : "Ready"}</span><span className="dock-divider"/><button className="gaze-control" onClick={() => gaze.status === "off" || gaze.status === "error" ? void gaze.start() : gaze.stop()} title="Experimental gaze estimation" aria-label="Toggle eye tracking"><Eye size={16}/>{gaze.status === "active" ? "Gaze on" : gaze.status === "loading" ? "Loading…" : "Gaze off"}</button><button className="icon-button" aria-label="Open settings" onClick={() => setDialog("settings")}><Settings2 size={14}/></button></div><button className={`lumi-mascot ${busy || listening ? "working" : ""}`} onClick={() => document.querySelector<HTMLInputElement>('.intent-form input')?.focus()} aria-label="Ask Lumi"><Beaver/><span>✧</span></button></div>
          <p className="context-status"><span className="status-dot"/>{contextSource}</p>
          <div aria-live="polite">{(error || gaze.error || readAloud.error) && <div className="message error" role="alert">{error || gaze.error || readAloud.error}<button aria-label="Dismiss error" onClick={() => {setError("");if(gaze.error) gaze.stop();readAloud.stop();}}><X size={14}/></button></div>}{notice && <div className="message success">{notice}<button aria-label="Dismiss notification" onClick={() => setNotice("")}><X size={14}/></button></div>}</div>
        </aside>
      </main>
      <footer className="page-footer"><span>micro intent <span>·</span> Small gestures. Real plans.</span><span>Made in Zürich <span>✳</span></span></footer>

      {gaze.status === "calibrating" && (
        <GazeCalibration
          onSample={gaze.calibrate}
          onComplete={gaze.finishCalibration}
          onCancel={gaze.stop}
        />
      )}
      {gaze.status === "active" && gaze.point && (
        <div
          className="gaze-point"
          style={{ left: gaze.point.x, top: gaze.point.y }}
        />
      )}
      {dialog && (
        <div
          className="modal-backdrop"
          onClick={(e) => {
            if (e.target === e.currentTarget && !busy) setDialog(null);
          }}
        >
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="dialog-title"
          >
            <button
              className="modal-close"
              onClick={() => setDialog(null)}
              aria-label="Close"
            >
              <X size={20} />
            </button>
            {dialog === "settings" && (
              <>
                <span className="eyebrow">YOUR SPACE</span>
                <h2 id="dialog-title">Connections and preferences</h2>
                <label>
                  Starting from
                  <input
                    value={origin}
                    disabled={busy}
                    placeholder="Current location or enter a place"
                    onChange={(e) => {
                      setOrigin(e.target.value);
                      setCurrentLocation(!e.target.value.trim());
                      setLocationStatus("");
                      setPlan(null);
                    }}
                  />
                </label>
                <div className="settings-item">
                  <span className="google-mark">G</span>
                  <div>
                    <strong>Google Calendar</strong>
                    <p>
                      {token
                        ? "Temporary access to your primary calendar."
                        : "Check conflicts and add events with your confirmation."}
                    </p>
                  </div>
                </div>
                <button
                  className="primary-link"
                  onClick={token ? disconnect : connectGoogle}
                >
                  {token ? "Disconnect Google" : "Connect Google Calendar"}{" "}
                  <ArrowRight size={16} />
                </button>
                {!clientId && (
                  <p className="setup-note">
                    To enable OAuth, set GOOGLE_CLIENT_ID in .env and restart
                    the server. The demo works without credentials.
                  </p>
                )}
                <p className="fineprint">
                  Gaze is estimated on this device. Voice input may use your
                  browser’s speech service. When you check an event, its details
                  and your intent are sent to the server and, if configured, to
                  the model.
                </p>
              </>
            )}
            {dialog === "install" && (
              <>
                <span className="eyebrow">ALWAYS WITH YOU</span>
                <h2 id="dialog-title">Take Lumi with you.</h2>
                <h3>In Chrome on desktop</h3>
                <ol>
                  <li>
                    Open <code>chrome://extensions</code>.
                  </li>
                  <li>Enable “Developer mode” and select “Load unpacked”.</li>
                  <li>
                    Select the <code>extension</code> folder in this project and
                    pin Micro Intent to your toolbar.
                  </li>
                  <li>Open a Luma event to see your companion.</li>
                  <li>In the extension popup, select “Save URLs and grant API access”. Use localhost for this computer or your deployed HTTPS address.</li>
                </ol>
                <h3>As an app on your phone or laptop</h3>
                <p>
                  Install this website from your browser menu. On mobile, use an
                  accessible HTTPS address; localhost refers to the phone
                  itself.
                </p>
                <p className="setup-note">
                  Mobile Chrome does not run this desktop extension. Use the
                  installable web app to enter event details and check your
                  plan.
                </p>
                {installPrompt && (
                  <button
                    className="primary-link"
                    onClick={async () => {
                      await installPrompt.prompt();
                      setInstallPrompt(null);
                    }}
                  >
                    Install app <Download size={16} />
                  </button>
                )}
              </>
            )}
            {dialog === "review" && (
              <>
                <span className="eyebrow">YOU HAVE THE FINAL SAY</span>
                <h2 id="dialog-title">Add this event</h2>
                <div className="review-event">
                  <CalendarDays />
                  <div>
                    <strong>{event.title}</strong>
                    <p>
                      {fmt(event.start, { dateStyle: "medium" })} ·{" "}
                      {time(event.start)} – {time(event.end)}
                      <br />
                      {event.location}
                    </p>
                  </div>
                </div>
                {!!plan?.conflicts.length && (
                  <p className="setup-note">
                    There are conflicts in{" "}
                    {plan.mode === "demo"
                      ? "the demo calendar"
                      : "your calendar"}
                    . Adding this event will keep your existing commitments.
                  </p>
                )}
                <p>
                  An event will be created in your primary calendar. Register on
                  Luma separately.
                </p>
                {token ? (
                  <button
                    className="primary-link"
                    disabled={busy}
                    onClick={() => void saveEvent()}
                  >
                    {busy ? "Saving…" : "Confirm and add to Google"}{" "}
                    <Check size={16} />
                  </button>
                ) : (
                  <>
                    <button className="primary-link" onClick={connectGoogle}>
                      Connect Google to save <ArrowRight size={16} />
                    </button>
                    <button className="secondary-button" onClick={downloadICS}>
                      Download .ics event <Download size={16} />
                    </button>
                  </>
                )}
              </>
            )}
            {dialog === "event" && (
              <>
                <span className="eyebrow">SHARED CONTEXT</span>
                <h2 id="dialog-title">Your next event</h2>
                <p>
                  In the extension, Lumi reads the page. Here, you can enter or
                  update the event details.
                </p>
                <form
                  onSubmit={(e) => {
                    e.preventDefault();
                    setPlan(null);
                    setSaved(false);
                    setDialog(null);
                  }}
                >
                  <label>
                    Name
                    <input
                      required
                      value={event.title}
                      onChange={(e) =>
                        setEvent({ ...event, title: e.target.value })
                      }
                    />
                  </label>
                  <label>
                    Start (ISO, including time zone)
                    <input
                      required
                      value={event.start}
                      onChange={(e) =>
                        setEvent({ ...event, start: e.target.value })
                      }
                      placeholder="2026-10-14T18:30:00+02:00"
                    />
                  </label>
                  <label>
                    End (ISO, including time zone)
                    <input
                      required
                      value={event.end}
                      onChange={(e) =>
                        setEvent({ ...event, end: e.target.value })
                      }
                    />
                  </label>
                  <label>
                    Location
                    <input
                      required
                      value={event.location}
                      onChange={(e) =>
                        setEvent({ ...event, location: e.target.value })
                      }
                    />
                  </label>
                  <label>
                    Event link
                    <input
                      type="url"
                      required
                      value={event.url}
                      onChange={(e) =>
                        setEvent({ ...event, url: e.target.value })
                      }
                    />
                  </label>
                  <button className="primary-link" type="submit">
                    Use this context <Check size={16} />
                  </button>
                </form>
              </>
            )}
            {error && (
              <p className="modal-error" role="alert">
                {error}
              </p>
            )}
          </section>
        </div>
      )}
    </div>
  );
}
export default App;
