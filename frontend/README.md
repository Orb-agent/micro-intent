# Frontend: Orb Agent (iPhone app)

The visible app name is Orb Agent; the Xcode project, target and bundle ID stay `BeaverAgent`.

WP1 from [docs/work-packages.md](../docs/work-packages.md).
The WebSocket, Cards and A2UI sections of [docs/contracts.md](../docs/contracts.md) are the API.

## Build and run

Open `BeaverAgent/BeaverAgent.xcodeproj` in Xcode and run the `BeaverAgent` scheme, or build from the command line:

```sh
xcodebuild -project frontend/BeaverAgent/BeaverAgent.xcodeproj -scheme BeaverAgent \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath ./.derived build
```

For the demo iPhone, pick your own team under Signing & Capabilities.

`a2ui-swift` is pinned to upstream revision `16476ba`, not `from: "0.3.0"`.
Every 0.3.x tag depends on `swift-foundation-icu` by revision, which SwiftPM refuses under a version requirement, and that commit drops the dependency.
Move back to a version rule once a tag after 0.3.5 is released.

## Modes

The app starts in fixture mode ("Demo data"): typed questions replay the bundled fixtures as server frames, through the same decoding and rendering path as live frames.
Questions about flights, events or the week return the event and flight cards; anything else returns the demo reply.
Type `sin conflictos` or `no conflicts` to try the travel popup with a fixture connection from Winterthur.
In live mode, a reply with a future connection and no conflict card opens the travel sheet, with
departure/arrival times and a Google Maps transit link. Event-only replies open it for explicit
attendance questions; calendar listings stay quiet. Maps URLs do not set an arrival time, so the
sheet shows the event time to select with “Arrive by” in Maps. Train arrival is at the station;
allow time to reach the venue.
Turn off "Use demo data" in settings and enter the tunnel URL and `APP_TOKEN` to go live.

The keyboard button next to the orb opens a sheet to type a question (the `text` frame).
In fixture mode, touching and holding the orb opens the same sheet, and the sheet can pretend a screenshot arrived, which shows the screen chip.

## Voice

Live, the orb is push-to-talk: hold it and talk, let go to send.
A touch shorter than 250 ms is a tap: it stops the mascot (`interrupt`) instead of starting a question.
The mic audio from the moment the finger went down is kept and sent once the touch counts as a hold, so the first word is not lost.

"Hands-free" in settings reconnects with `mode: "handsfree"`: the mic streams the whole time, also while the mascot speaks, and the server decides when a turn ends.
Talking over the mascot makes the server send `state: listening`, and the app stops playback at once.

`VoiceIO.swift` follows contracts § Audio: `.playAndRecord` with `.defaultToSpeaker`, voice processing on, mic converted to Int16 24 kHz mono and sent as 3840-byte chunks, TTS played on an `AVAudioPlayerNode` on the same engine.
The orb shows `speaking` while TTS audio is still queued, even after the server's `state: idle`.
After an interrupt, the rest of the cancelled turn's audio is dropped until the next turn's `state: thinking`.
The console logs one line per reply (`voice: reply played, … underruns`) and every stop (`voice: playback stopped …`).

## Files

| File | Role |
| --- | --- |
| `Protocol.swift` | Wire types for `/ws` |
| `WebSocketClient.swift` | `hello`, frame decoding, reconnect after 1 s and on foreground |
| `AgentSession.swift` | Screen state for the latest turn, fixture replay, push-to-talk and interrupts |
| `VoiceIO.swift` | Audio session, mic capture and conversion, TTS playback |
| `CardsView.swift` | A2UI surfaces; `nativeCards` is the switch point for native fallback cards |
| `OrbView.swift` | Orb states and the status pill |
| `Theme.swift` | Design tokens from the Paper design system, light and dark |
| `Fixtures/` | `demo_reply.json`, `cards.json`, `screen.json` from WP2; `demo_a2ui.json`, `cards_a2ui.json` are copies of WP3's `backend/fixtures/` files |

When `backend/a2ui.py` changes, regenerate the backend fixtures and copy them over the files in `Fixtures/`.

## Screenshots and rehearsals

Launch arguments set up a state without tapping through it:

```sh
xcrun simctl launch <udid> ch.microintent.BeaverAgent -appearance dark -demoScene searching
```

| Argument | Values |
| --- | --- |
| `-demoScene` | `listening`, `thinking`, `searching`, `speaking`, `reply`, `kinds`, `screen`, `error`, `travel` |
| `-demoSheet` | `settings`, `debug`, `dashboard` |
| `-demoDashboard` | With `-demoSheet dashboard`: `stop` opens the Stop confirmation, `confirmed` answers the train alert with Confirm |
| `-demoAsk` | A question sent 2 s after launch, live or in fixture mode |
| `-appearance` | `system`, `light`, `dark` |
| `-largeText` | `YES`, `NO` |
| `-useFixtures`, `-serverURL`, `-token`, `-handsFree` | Override the settings for one launch |
| `-micFile` | A WAV file in the app's Documents folder, looped in real time as the mic; for a Mac without an audio input |
| `-demoHold` | Live only: hold the orb for this many seconds once connected |
| `-demoTapAt` | Live only: tap the orb this many seconds after connecting |
