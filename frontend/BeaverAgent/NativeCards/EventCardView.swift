import SwiftUI

public struct EventCardView: View {
    public let card: EventCard
    public let onAction: ((String) -> Void)?

    public init(card: EventCard, onAction: ((String) -> Void)? = nil) {
        self.card = card
        self.onAction = onAction
    }

    private var sourcePill: some View {
        switch card.source {
        case .calendar:
            return GlassPillView(
                iconName: "calendar",
                text: "Kalender",
                tintColor: CardTheme.skyBlue
            )
        case .luma:
            return GlassPillView(
                iconName: "ticket.fill",
                text: "Luma Event",
                tintColor: CardTheme.purpleAccent
            )
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header with source pill and duration
            HStack {
                sourcePill
                Spacer()
                GlassPillView(
                    iconName: "clock",
                    text: CardFormatters.formatDuration(from: card.start, to: card.end),
                    tintColor: Color(white: 0.85)
                )
            }

            // Title
            Text(card.title)
                .font(CardTheme.titleFont)
                .foregroundColor(CardTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Details rows
            VStack(alignment: .leading, spacing: 12) {
                // Date & Time
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(CardTheme.textPrimary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(CardFormatters.formatShortDate(card.start)) – \(CardFormatters.formatShortDate(card.end))")
                            .font(CardTheme.headlineFont)
                            .foregroundColor(CardTheme.textPrimary)

                        Text("\(CardFormatters.formatTime(card.start)) – \(CardFormatters.formatTime(card.end)) Uhr")
                            .font(CardTheme.captionFont)
                            .foregroundColor(CardTheme.textSecondary)
                    }
                }

                // Location (if present)
                if let location = card.location, !location.isEmpty {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 38, height: 38)
                            .overlay {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(CardTheme.coralRed)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(location)
                                .font(CardTheme.headlineFont)
                                .foregroundColor(CardTheme.textPrimary)

                            Text("Veranstaltungsort")
                                .font(CardTheme.captionFont)
                                .foregroundColor(CardTheme.textMuted)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }

            // Large Action Buttons
            CardActionButtonsView(
                confirmTitle: "Bestätigen",
                cancelTitle: "Abbrechen",
                confirmActionId: "confirm_event",
                cancelActionId: "cancel_event",
                onAction: onAction
            )
        }
        .darkGlassCard()
    }
}

// MARK: - Previews

#Preview("Event Card - Dark") {
    ZStack {
        Color.black.ignoresSafeArea()
        EventCardView(card: Card.sampleEvent) { action in
            print("Action tapped: \(action)")
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Event Card - Light") {
    ZStack {
        Color(white: 0.92).ignoresSafeArea()
        EventCardView(card: Card.sampleEvent) { action in
            print("Action tapped: \(action)")
        }
        .padding()
    }
    .preferredColorScheme(.light)
}
