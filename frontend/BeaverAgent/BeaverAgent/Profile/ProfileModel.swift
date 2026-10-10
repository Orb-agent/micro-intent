import SwiftUI

/// Storage keys for user profile, travel preferences, and family settings.
enum ProfileKey {
    static let hasCompletedFirstRun = "profile_hasCompletedFirstRun"
    static let userRole = "profile_userRole"
    static let homeCity = "profile_homeCity"
    static let travelTrain = "profile_travelTrain"
    static let travelBus = "profile_travelBus"
    static let travelWalk = "profile_travelWalk"
    static let walkingPace = "profile_walkingPace"
    static let helperMode = "profile_helperMode"
}

/// The first-run question choice: "Is this iPhone for you, or for someone you help?".
enum UserRole: String, CaseIterable, Identifiable {
    case forMe = "forMe"
    case forSomeoneIHelp = "forSomeoneIHelp"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forMe:
            return "For me"
        case .forSomeoneIHelp:
            return "For someone I help"
        }
    }

    var subtitle: String {
        switch self {
        case .forMe:
            return "I use this iPhone myself. The assistant speaks simply and shows large cards."
        case .forSomeoneIHelp:
            return "I am setting up this iPhone for an older family member. Helper mode enables remote assistance."
        }
    }

    var icon: String {
        switch self {
        case .forMe:
            return "person.fill"
        case .forSomeoneIHelp:
            return "person.2.fill"
        }
    }
}

/// Walking speed preference for journey planning and connection buffers.
enum WalkingPace: String, CaseIterable, Identifiable {
    case leisurely = "leisurely"
    case steady = "steady"
    case brisk = "brisk"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leisurely:
            return "Leisurely"
        case .steady:
            return "Steady"
        case .brisk:
            return "Brisk"
        }
    }

    var detail: String {
        switch self {
        case .leisurely:
            return "Extra time for platforms and stairs (+8 min buffer)"
        case .steady:
            return "Standard connection times (+4 min buffer)"
        case .brisk:
            return "Quick connections without extra buffer"
        }
    }

    var icon: String {
        switch self {
        case .leisurely:
            return "figure.walk"
        case .steady:
            return "figure.walk.motion"
        case .brisk:
            return "figure.run"
        }
    }
}

/// A trusted family member or caregiver who stays in the loop.
struct TrustedContact: Identifiable, Hashable {
    let id: String
    let name: String
    let relationship: String
    let phone: String
    let isHelper: Bool
    let canReceiveUpdates: Bool
    let note: String
}
