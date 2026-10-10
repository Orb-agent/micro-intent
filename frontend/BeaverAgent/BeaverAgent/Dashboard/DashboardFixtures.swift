import Foundation

/// DEMO STAND-IN: the helpers below are bundled fixture data, not live cloud agent tasks.
/// The WebSocket contract (docs/contracts.md) has no message for background tasks yet,
/// so this screen shows a fixed demo story until one exists.
enum DashboardFixtures {
    static let helpers: [Helper] = [
        Helper(
            id: "train",
            symbol: "tram.fill",
            title: "Watching your 17:31 train to Zurich",
            detail: "IC 8. I tell you about delays until you board.",
            state: .waitingForOK,
            proposal: Helper.Proposal(
                message: "Your IC 8 is 10 minutes late. Take the 17:33 IC 5 instead? Lena knows.",
                confirmed: .init(title: "Watching your 17:33 train to Zurich", detail: "IC 5 instead of the late IC 8. Lena knows."),
                cancelled: .init(title: "Watching your 17:31 train to Zurich", detail: "IC 8, about 10 minutes late. Lena knows.")
            )
        ),
        Helper(
            id: "reminder",
            symbol: "bell.fill",
            title: "Reminder at 17:01",
            detail: "Time to leave for the station.",
            state: .running
        ),
        Helper(
            id: "lena",
            symbol: "message.fill",
            title: "Lena will get a message when you arrive",
            detail: "Sent when you reach Zurich HB.",
            state: .running
        ),
        Helper(
            id: "dinner",
            symbol: "calendar",
            title: "Dinner with Lena is in your calendar",
            detail: "Saturday at 19:00. You said OK at 14:12.",
            state: .done
        ),
        Helper(
            id: "rain",
            symbol: "cloud.rain.fill",
            title: "Rain check for your walk",
            detail: "You stopped it at 15:20.",
            state: .stopped
        ),
    ]
}
