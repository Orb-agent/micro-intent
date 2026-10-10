# Orbs · Design and implementation kit · v1.0 · FINAL RING DIRECTION
10 October 2026. Hackathon handoff. Mobile + web.

## Direction
Content stays primary. Orbs appears at the point of attention, carries context into a spoken request, and returns a small actionable card. Monochrome, fine-line, calm, compact. Avoid dashboards, full-screen chat takeovers, neon glows, glass blur, decorative gradients, and large assistant avatars.

References reviewed: supplied 23.9-second eye-tracking + voice recording; all eleven supplied screenshots; https://libraries.dev/orbs. Phone footage demonstrates gaze as additional probabilistic context, not a command. Dark screenshots supply fine-line orb forms and compact pill/card composition. Colored heatmaps and blue/green UI accents are translated to grayscale to meet this kit's monochrome requirement. Values below are new implementation decisions, not extracted measurements.

## Files
- index.html — self-contained animated visual guide. Open directly in any modern browser.
- tokens.css — production tokens and small reusable component styles.
- OrbsIndicator.tsx — React adapter using the exact thinking-orbs component.
- tokens.json — platform-neutral tokens, including typography and motion.
- orb-motion.css — selected pulse, rotation and burst animations. Import alongside OrbsIndicator.tsx.

## Color
Light: canvas #FAFAFA, surface #FFFFFF, raised #F4F4F4, text #171717, secondary #666666, border #DEDEDE. Dark: canvas #111111, surface #1A1A1A, raised #242424, text #F5F5F5, secondary #AAAAAA, border #383838. Black and white establish the identity; grays express hierarchy. Use text and icons for success, warning and error; no color-only status. Never place small gray labels over animated orb lines.

## Typography
System sans: SF on Apple; Segoe UI on Windows; system fallback elsewhere. No font downloads required. Product wordmark: Orbs, medium, -0.04em; use text rather than a fabricated logo asset.
Display 48/52 weight 500, -0.04em (mobile 36/40). Section 28/34 weight 500, -0.025em. Card title 18/24 weight 600, -0.015em. Body 15/22 weight 400. Control 14/20 weight 500. Metadata 12/16 weight 500. Native units are points; web units pixels. Honor native Dynamic Type / web zoom; do not lock card heights.

## Layout
Spacing grid: 4,8,12,16,20,24,32,48,64. Screen gutter 20 mobile / 32 desktop. Card padding 20; nested rows 12; gaps 8 or 12. Card radius 24; controls 12; pills 999. Fine 1px borders. Shadow only on floating surfaces. 44px minimum interaction targets, including any visible 20px icon. Card widths: web 360 (max 400), mobile viewport minus 32px. Cards grow vertically with content.

## Attention / initial heatmap
Default product view shows no heatmap. On hover, focus, touch selection or gaze candidate, show a single soft grayscale patch (8% ink, 18px blur) plus a fine outline once selected. Debug mode may reveal raw attention intensity; label it Debug, keep it separate from the product default. Gaze is evidence, not authorization. For this day's demo, hover/tap may simulate attention; label simulation in the demo. An approximate 350ms dwell can expose a candidate but must be calibrated; voice or explicit selection commits context. Keep text readable and do not track gaze across apps without implemented support.

## Orb anatomy and selected state contract
Final choice: Ring, as shown in the approved screenshot (10 October, 14:35). All states use the exact thinking-orbs 0.3.2 breathing geometry. Never switch to composing, working or listening geometry. Keep the 64px hero and 20px inline library presets. A wrapper introduces distinct motion without replacing the library renderer. Status labels remain mandatory.

| App state | Library state | Speed / dotSize | Wrapper movement | Label |
|---|---|---|---|---|
| Idle | breathing | .3 / .8 | slow native drift | Ready |
| Listening | breathing | .65 / 1 | irregular scale .88–1.2 over 2.6s | Listening… |
| Thinking | breathing | .75 / 1 | continuous 360° rotation, 4.5s linear | Thinking… |
| Acting | breathing | 1.2 / 1.15 | three 120° forward bursts, 2.2s, scale 1–1.12 | Actual tool activity |
| Confirmation | breathing, paused | .3 / .8 | static | Ready to add |
| Done | breathing, paused | .3 / .8 | static + adjacent check | Added to your calendar |
| Error | breathing, paused | .3 / .8 | static + adjacent warning | Calendar unavailable · Retry |

Listening pulse is the approved illustrative rhythm, not microphone-driven. Render it only while recording. If implementing audio reactivity later, replace its wrapper scale with normalized RMS, clamped to .88–1.2; leave breathing geometry intact. Hero slot needs 12px motion clearance on each side (64 × 1.2 = 76.8px). Inline orb sits inside a minimum 44px pill. Motion changes have a distinct rhythm, rather than speed alone.

State path: Idle → Listening → Thinking → Acting → Confirmation (for writes) → Acting → Done. Cancel returns Idle; failure enters Error. User correction can return Listening. Read-only results may go Acting → Done directly. No fake progress, fabricated success, or invented completion percentages. After 8s show 'Still checking…'; after 20s show cancel/retry if backend supports it. Keep truthful text when tools take longer.

## Cards
1. Context: small source chip + user's interpreted request; edit/change target available.
2. Result: one sentence outcome; up to three information rows; source attribution.
3. Confirmation: summarize exact writes and affected objects; primary Confirm, secondary Cancel.
4. Done: report confirmed changes; Undo only if backend provides reversal.
5. Error: what failed, preserved context, Retry/Cancel.
Desktop: anchored 12px from target, flip to keep 16px viewport margin; clamp to viewport, close on Escape and restore trigger focus. Mobile: bottom contextual sheet above keyboard and safe area with 16px side margins. No dim backdrop for passive results; modal confirmation may use 20% black scrim, dialog semantics and trapped focus. Scroll result content when height exceeds 60vh. Voice transcript remains editable; text input remains available.

## Motion
Enter: 320ms cubic-bezier(.16,1,.3,1), opacity 0→1, y 8→0px, scale .98→1. Exit: 160ms cubic-bezier(.4,0,1,1), opacity 1→0, y 0→4px. State change: 200ms cubic-bezier(.4,0,.2,1). Control feedback:120ms. Native equivalents can use cubic timing curves; avoid spring overshoot. Orbs can loop linearly internally; never bounce the whole card. Animate transforms/opacity; pause offscreen. Reduced motion: static orb, persistent textual state, immediate placement with optional 100ms opacity fade. No essential state conveyed only through animation.

## Accessibility
Visible labels for all states. role=status / aria-live=polite for status text, not a per-frame announcement. Canvas aria-hidden when adjacent text duplicates it. Modal confirmation uses role=dialog, labelled title, focus trap, Escape and restored focus. Keyboard selection offers same context as hover. Maintain body contrast ≥4.5:1; large text ≥3:1. Focus ring 2px with 3px offset. Debug attention layer pointer-events:none. Microphone button has explicit accessible name and recording state. Do not auto-record.

## Using the selected exact library component
npm install thinking-orbs@0.3.2 react react-dom

```tsx
import { OrbsIndicator } from './OrbsIndicator';
<OrbsIndicator state="thinking" size={64} dark={false} reducedMotion={false} />
```

OrbsIndicator imports orb-motion.css. Internally it always renders <ThinkingOrb state="breathing" size={64} /> (or 20) with state-specific speed and dotSize props. Theme is theme="dark" / theme="light". Supply reducedMotion from your app's hook; the CSS also honors the OS preference. All wrappers stop for confirmation, done and error. Use check/warning icons and visible text beside them. The standalone guide bundles React and the exact library and opens offline. MIT notices included. No custom geometry renderer remains.

## Demo acceptance checklist
- Mobile 390px and desktop 1440px, no overflow; zoom 200% remains usable.
- Exact 64px hero and 20px inline presets, no stretch or color overrides.
- Listening only during capture; acting labels reflect actual tools.
- Confirmation before changes; actual success before Done.
- Cancel, error, empty and reduced-motion views remain understandable.
- Mobile safe areas + keyboard placement checked on target device.
