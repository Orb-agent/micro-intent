import SwiftUI

@main
struct BeaverAgentApp: App {
    @State private var session = AgentSession()
    @State private var sheet: AppSheet?
    @AppStorage(SettingsKey.serverURL) private var serverURL = ""
    @AppStorage(SettingsKey.token) private var token = ""
    @AppStorage(SettingsKey.useFixtures) private var useFixtures: Bool?
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.system
    @AppStorage(SettingsKey.largeText) private var largeText = false
    @AppStorage(SettingsKey.handsFree) private var handsFree = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(session: session, sheet: $sheet)
                .sheet(item: $sheet) { sheet in
                    switch sheet {
                    case .settings:
                        SettingsSheet(connection: session.connection)
                    case .debug:
                        DebugSheet(
                            isFixtureMode: session.connection == .fixtures,
                            ask: session.ask,
                            simulateScreenshot: session.simulateScreenshot
                        )
                        .presentationDetents([.medium, .large])
                    case .travel:
                        if let plan = session.travelPlan { TravelSheet(plan: plan) }
                    }
                }
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.typeScale, typeScale)
                .task {
                    applySettings()
                    DemoLaunch.apply(to: session, sheet: $sheet)
                }
                .onChange(of: settingsKey) { applySettings() }
                .onChange(of: session.replyRevision) {
                    if session.travelPlan != nil { sheet = .travel }
                    else if sheet == .travel { sheet = nil }
                }
                .onChange(of: session.serverState) { _, state in
                    if sheet == .travel && (state == .thinking || state == .listening) { sheet = nil }
                }
                .onChange(of: largeText, initial: true) { session.typeScale = typeScale }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { session.appBecameActive() }
                }
        }
    }

    private var typeScale: TypeScale { largeText ? .large : .regular }

    private var settingsKey: String { "\(String(describing: useFixtures))|\(serverURL)|\(token)|\(handsFree)" }

    private func applySettings() {
        session.configure(useFixtures: SettingsKey.replays(useFixtures, serverURL: serverURL), serverURL: serverURL, token: token, handsFree: handsFree)
    }
}

/// Launch arguments for rehearsals and screenshots, e.g.
/// `-demoScene searching`, `-demoSheet debug`, `-demoAsk "Can I make it?"`.
/// Live server only: `-demoHold 3` holds the orb for 3 s once connected, `-demoTapAt 9`
/// taps it 9 s after connecting; with `-micFile` this drives the voice path without a finger.
@MainActor
enum DemoLaunch {
    static func apply(to session: AgentSession, sheet: Binding<AppSheet?>) {
        let defaults = UserDefaults.standard
        if let scene = defaults.string(forKey: "demoScene") {
            play(scene, on: session)
        }
        if let name = defaults.string(forKey: "demoSheet"), let value = AppSheet(rawValue: name) {
            sheet.wrappedValue = value
        }
        if let question = defaults.string(forKey: "demoAsk") {
            Task {
                try? await Task.sleep(for: .seconds(2))
                session.ask(question)
            }
        }
        let hold = defaults.double(forKey: "demoHold")
        let tapAt = defaults.double(forKey: "demoTapAt")
        if hold > 0 || tapAt > 0 {
            Task {
                while session.connection != .live { try? await Task.sleep(for: .milliseconds(100)) }
                if hold > 0 {
                    session.orbPressBegan()
                    try? await Task.sleep(for: .seconds(hold))
                    session.orbPressEnded()
                }
                if tapAt > hold {
                    try? await Task.sleep(for: .seconds(tapAt - hold))
                    session.orbPressBegan()
                    try? await Task.sleep(for: .milliseconds(80))
                    session.orbPressEnded()
                }
            }
        }
    }

    private static func play(_ scene: String, on session: AgentSession) {
        let question = "Can I make it to dinner in Bern?"
        switch scene {
        case "listening":
            session.handle(.state(.listening, label: nil))
        case "thinking":
            session.handle(.transcript(question))
            session.handle(.state(.thinking, label: nil))
        case "searching":
            session.handle(.transcript(question))
            session.handle(.state(.thinking, label: nil))
            session.handle(.state(.searching, label: "Checking trains…"))
        case "speaking", "reply", "kinds":
            let turn = scene == "kinds" ? Fixtures.otherKinds : Fixtures.demo
            session.handle(.transcript(scene == "kinds" ? "What's coming up this week?" : question))
            session.handle(.state(.thinking, label: nil))
            session.handle(.state(.searching, label: turn.label))
            turn.frames.forEach(session.receive)
            session.handle(.state(scene == "speaking" ? .speaking : .idle, label: nil))
        case "screen":
            session.simulateScreenshot()
        case "travel":
            session.handle(.transcript("Can I attend dinner without conflicts?"))
            session.handle(.state(.thinking, label: nil))
            Fixtures.travel.frames.forEach(session.receive)
            session.handle(.state(.idle, label: nil))
        case "seeing":
            session.simulateScreenshot()
            session.handle(.state(.thinking, label: nil))
            session.handle(.state(.searching, label: "Checking your calendar…"))
        case "screen-failed":
            session.receive(Data(#"{"type": "screen_ok"}"#.utf8))
        case "error":
            session.handle(.transcript(question))
            session.handle(.error("Sorry, something went wrong."))
        default:
            break
        }
    }
}
