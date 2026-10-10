import SwiftUI

@main
struct BeaverAgentApp: App {
    @State private var session = AgentSession()
    @State private var sheet: AppSheet?
    @AppStorage(SettingsKey.serverURL) private var serverURL = ""
    @AppStorage(SettingsKey.token) private var token = ""
    @AppStorage(SettingsKey.useFixtures) private var useFixtures = true
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.system
    @AppStorage(SettingsKey.largeText) private var largeText = false
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
                    }
                }
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.typeScale, typeScale)
                .task {
                    applySettings()
                    DemoLaunch.apply(to: session, sheet: $sheet)
                }
                .onChange(of: settingsKey) { applySettings() }
                .onChange(of: largeText, initial: true) { session.typeScale = typeScale }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { session.appBecameActive() }
                }
        }
    }

    private var typeScale: TypeScale { largeText ? .large : .regular }

    private var settingsKey: String { "\(useFixtures)|\(serverURL)|\(token)" }

    private func applySettings() {
        session.configure(useFixtures: useFixtures, serverURL: serverURL, token: token)
    }
}

/// Launch arguments for rehearsals and screenshots, e.g.
/// `-demoScene searching`, `-demoSheet debug`, `-demoAsk "Can I make it?"`.
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
        case "error":
            session.handle(.transcript(question))
            session.handle(.error("Sorry, something went wrong."))
        default:
            break
        }
    }
}
