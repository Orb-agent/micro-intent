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
Turn off "Use demo data" in settings and enter the tunnel URL and `APP_TOKEN` to go live.

Touch and hold the orb to type a question (the `text` frame).
In fixture mode the same sheet can pretend a screenshot arrived, which shows the screen chip.

## Files

| File | Role |
| --- | --- |
| `Protocol.swift` | Wire types for `/ws` |
| `WebSocketClient.swift` | `hello`, frame decoding, reconnect after 1 s and on foreground |
| `AgentSession.swift` | Screen state for the latest turn, fixture replay |
| `CardsView.swift` | A2UI surfaces; `nativeCards` is the switch point for native fallback cards |
| `OrbView.swift` | Orb states and the status pill |
| `Theme.swift` | Design tokens from the Paper design system, light and dark |
| `Fixtures/` | `demo_reply.json`, `cards.json`, `screen.json` from WP2; `demo_a2ui.json`, `cards_a2ui.json` stand in for WP3's files |

When WP3 pushes `backend/fixtures/demo_a2ui.json` and `cards_a2ui.json`, copy them over the files in `Fixtures/`.

## Screenshots and rehearsals

Launch arguments set up a state without tapping through it:

```sh
xcrun simctl launch <udid> ch.microintent.BeaverAgent -appearance dark -demoScene searching
```

| Argument | Values |
| --- | --- |
| `-demoScene` | `listening`, `thinking`, `searching`, `speaking`, `reply`, `kinds`, `screen`, `error` |
| `-demoSheet` | `settings`, `debug` |
| `-demoAsk` | A question sent 2 s after launch, live or in fixture mode |
| `-appearance` | `system`, `light`, `dark` |
| `-largeText` | `YES`, `NO` |
| `-useFixtures`, `-serverURL`, `-token` | Override the settings for one launch |
