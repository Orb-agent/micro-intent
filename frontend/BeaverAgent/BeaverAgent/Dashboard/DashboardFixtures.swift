import Foundation

// Demo stand-in: cloud agent tasks fixture
// Bundled local fixtures representing background cloud agent helpers for the live demo.
// No new WebSocket message types or backend changes; pure client-side demo stand-in.
enum DashboardFixtures {
    static let tasks: [HelperTask] = [
        HelperTask(
            id: "train-alert-ic8",
            title: "Your IC 8 is 10 minutes late. Take the 17:33 IC 5 instead? Lena knows.",
            subtitle: "Train connection update",
            detail: "Alternative train leaves in 12 min from Platform 33. Arrives in Bern 18:56. Lena is notified.",
            state: .waitingForApproval,
            categoryIcon: "tram.fill",
            agentBadge: "SBB Travel Helper",
            familyStatus: "Lena is in the loop",
            alertAction: HelperAlertAction(
                confirmTitle: "Take 17:33 IC 5",
                cancelTitle: "Keep IC 8",
                promptQuestion: "Switch your journey to the 17:33 IC 5?",
                confirmedMessage: "Switched to 17:33 IC 5. Lena knows and arrival time updated.",
                cancelledMessage: "Kept original 17:31 IC 8 train."
            ),
            timestamp: "Just now"
        ),
        HelperTask(
            id: "train-watcher-1731",
            title: "Watching your 17:31 train to Zurich",
            subtitle: "Live timetable monitor",
            detail: "Checks delay and track changes every 2 minutes. Alerts you before departure.",
            state: .running,
            categoryIcon: "tram.fill",
            agentBadge: "SBB Mobility Helper",
            familyStatus: "Status shared with family",
            alertAction: nil,
            timestamp: "Updated 1m ago"
        ),
        HelperTask(
            id: "reminder-1701",
            title: "Reminder at 17:01",
            subtitle: "Timed departure reminder",
            detail: "Voice reminder to pack charger and start walking to Zurich HB Platform 31.",
            state: .running,
            categoryIcon: "bell.badge.fill",
            agentBadge: "Schedule Helper",
            familyStatus: nil,
            alertAction: nil,
            timestamp: "Fires in 1h 10m"
        ),
        HelperTask(
            id: "family-message-lena",
            title: "Lena will get a message when you arrive",
            subtitle: "Family loop update",
            detail: "Sends an automatic text message to daughter Lena as soon as you reach Zurich HB.",
            state: .running,
            categoryIcon: "person.crop.circle.badge.checkmark",
            agentBadge: "Family Loop Helper",
            familyStatus: "Lena's phone connected",
            alertAction: nil,
            timestamp: "Active"
        ),
        HelperTask(
            id: "calendar-acme-check",
            title: "Calendar check with Acme call",
            subtitle: "Schedule conflict check",
            detail: "Confirmed your call ends at 17:45 with 15 minutes to reach the station. Saved to calendar.",
            state: .done,
            categoryIcon: "checkmark.circle.fill",
            agentBadge: "Calendar Helper",
            familyStatus: nil,
            alertAction: nil,
            timestamp: "Completed at 15:45"
        ),
        HelperTask(
            id: "weather-watch-zurich",
            title: "Rain check for walking route",
            subtitle: "Weather monitor",
            detail: "Precipitation radar check between office and station. Stopped upon arrival.",
            state: .stopped,
            categoryIcon: "cloud.sun.rain.fill",
            agentBadge: "Weather Helper",
            familyStatus: nil,
            alertAction: nil,
            timestamp: "Stopped by you"
        )
    ]
}
