import Foundation

/// Local demo fixtures for Profile and Family screens.
///
/// DEMO STAND-IN:
/// This fixture data stands in for backend profile and family sync in the hackathon prototype.
/// All changes are stored locally in @AppStorage and never transmitted over the wire.
enum ProfileFixtures {
    /// Default home city from the hackathon brief.
    static let defaultHomeCity = "Winterthur"

    /// Default walking pace: comfortable for an older user at arm's length.
    static let defaultWalkingPace = WalkingPace.leisurely

    /// Trusted contacts list bundled for the Zurich hackathon demo.
    /// Lena is the daughter and designated family helper.
    static let demoContacts: [TrustedContact] = [
        TrustedContact(
            id: "lena-daughter",
            name: "Lena",
            relationship: "Daughter",
            phone: "+41 79 432 10 98",
            isHelper: true,
            canReceiveUpdates: true,
            note: "Designated helper. Receives trip notifications and can adjust settings."
        ),
        TrustedContact(
            id: "markus-son",
            name: "Markus",
            relationship: "Son",
            phone: "+41 78 876 54 32",
            isHelper: false,
            canReceiveUpdates: true,
            note: "Receives arrival updates when travel plans change."
        )
    ]

    /// Cities available in quick selection.
    static let popularStations = [
        "Winterthur",
        "Zürich HB",
        "Bern",
        "Basel SBB",
        "St. Gallen"
    ]
}
