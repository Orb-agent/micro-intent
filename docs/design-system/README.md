# Orb Agent design system

Design tokens and component spec for the Orb Agent app and overlay, derived from the Paper prototype (variant D, dark glass).

- Paper design system page: https://app.paper.design/file/01M4JSJGYH0GS4803ZCHM16907/p-3-0
- Paper prototype: https://app.paper.design/file/01M4JSJGYH0GS4803ZCHM16907/p-1-0
- `design-tokens.json` is the source of truth; `design-tokens.css` is generated from it with identical values.
- The iOS app maps these values in `frontend/BeaverAgent/BeaverAgent/Theme.swift`.

### Token files

- `design-tokens.json` is the source of truth.
- `design-tokens.css` is generated from the JSON, so both files carry identical values.
- Naming: `--mi-<group>-<name>`; groups are color, gradient, effect, font, text, space, radius, size, duration, easing.
- Text roles expand to `--mi-text-<role>-size | -line | -weight | -tracking`.
- Large mode: set `data-mi-mode="large"` on the overlay root.
  - The same role tokens are overridden (answer 44/52, time and body-strong 26/32, button 24/30, body 20/28, meta 18/22).
  - Panel width becomes 800.
  - Controls and touch targets become 72.
- `prefers-reduced-motion` shortens durations to 160ms and turns the loops off.
- Without backdrop-filter support, the glass falls back to an opaque `#1A1C24`.

### Component spec (maps 1:1 to the A2UI catalog names)

Core components:

- **Orb**
  - Props: `state` (idle | listening | thinking | speaking | done), `size` (32 | 104).
  - States: idle breathes (4000ms); listening shows rings (1200ms loop); thinking uses a conic gradient with an orbiting arc (1100ms); speaking ripples (1600ms); done draws a check, then returns to idle after 4s.
  - Size: 32 inside a 44 halo in the Pill; 104 as the hero.
- **Pill**
  - Props: `state`, `label`, `onHide`, `onStop`.
  - States: idle is compact (orb plus "Look and say", no Hide/Stop); listening, thinking, speaking and done have the same layout and a different label; the awaiting-confirm label is `Listening for "yes"`.
  - Size: height 58, padding 6, gap 6, radius full; Hide and Stop are 40 on desktop, 44 on iPhone.
- **Panel**
  - Props: `context`, `cards`, `checkpoint`, `chips`, `input`, `mode` (default | large).
  - Slot order: ContextRow, then card, then ConfirmCard, then IntentChips, then InputRow.
  - Size: width 560 (480-600), padding 18, gap 14, radius 24; large mode is 800 wide.
  - On iPhone it is a full-width bottom sheet (glass-sheet, radius 24 on top, padding 16).
  - It sits 8 below the Pill, next to the gaze target, never as a sidebar.
- **IntentChip**
  - Props: `icon`, `label`, `state` (default | hover | active | disabled), `onSelect`.
  - Size: desktop 13/16, padding 4/8, radius 10, dot separators, at most 4.
  - On iPhone: 36-tall capsules in a horizontal scroll row.
  - Hidden in large mode, where two big buttons replace them.
- **InputRow**
  - Props: `state` (idle | listening | typing | disabled), `value`, `placeholder`, `shortcut`, `onSubmit`, `onMic`.
  - States: idle shows the placeholder and the shortcut hint; listening shows the live transcript with a caret; typing turns the mic into a send button.
  - Size: height 52, radius 16, round action button 36.

A2UI card catalog:

- **ConflictCard**
  - Props: `event {title, start, end, calendar, guests}`, `conflictsWith`, `options [move {to}, skip, keep]`, `selected` (null | move | skip | keep), `onSelect`.
  - States: unresolved; move, skip or keep selected, shown with an accent-soft fill and a check.
  - Move and Skip open a ConfirmCard; Keep changes nothing.
  - Size: option buttons 40 tall on desktop, 44 on iPhone.
- **TrainCard**
  - Props: `line`, `dep {time, station, platform}`, `arr {time, station}`, `duration`, `transfers`, `walk {minutes, arrive}`, `openUrl`.
  - States: default and selected.
  - The SBB tile is 36 in service red, the times use text-time, and the meta uses text-meta.
  - On iPhone the timeline collapses to "17:31 → 17:57" with the line badge.
- **EventCard**
  - Props: `title`, `start`, `end`, `location`, `source` (domain of the page being looked at), `status` (new | in-calendar).
  - States: new shows an accent badge; in-calendar shows a success badge.
  - Date tile 52x56.
- **ReminderCard**
  - Props: `time`, `offset`, `anchor`, `previewText`, `onChange`, `onUndo`.
  - States: set and changed.
  - Bell tile 44, notification preview row.
- **MessageDraftCard**
  - Props: `recipient {name, relation}`, `channel`, `body`, `status` (draft | sent), `shareTrip`, `onEdit`.
  - It is always followed by a ConfirmCard with Edit / Send; nothing is sent before Confirm.
- **ConfirmCard (human checkpoint)**
  - Props: `question`, `changes[] {kind: add | move | send | remind, title, detail}`, `confirmLabel`, `cancelLabel`, `variant` (inline | expanded), `voice`.
  - States: pending, confirming, confirmed (which swaps to DoneCard) and cancelled.
  - Cancel is always on the left and the primary action on the right.
  - Buttons are 38 inline, 48 expanded, 44 on iPhone and 72 in large mode.
  - The voice hint reads 'Or just say "yes" or "cancel"'.
- **DoneCard (done state)**
  - Props: `title`, `changes[]`, `onUndo`, `openLink {label, url}`.
  - Success-soft tint with a green check (36).
  - Undo stays available until the panel closes.

