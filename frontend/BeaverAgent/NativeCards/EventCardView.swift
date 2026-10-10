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
                tintColor: CardTheme.accentText
            )
        case .luma:
            return GlassPillView(
                iconName: "ticket.fill",
                text: "Luma Event",
                tintColor: Color(red: 190/255, green: 140/255, blue: 255/255)
            )
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with source pill and duration
            HStack {
                sourcePill
                Spacer()
                GlassPillView(
                    iconName: "clock",
                    text: CardFormatters.formatDuration(from: card.start, to: card.end),
                    tintColor: CardTheme.textSecondary
                )
            }

            // Title
            Text(card.title)
                .font(CardTheme.titleFont)
                .foregroundColor(CardTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Details rows
            VStack(alignment: .leading, spacing: 14) {
                // Date & Time
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(CardTheme.textPrimary)
                        }

                    VStack(alignment: .leading, spacing: 3) {
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
                    HStack(spacing: 14) {
                        Circle()
                            .fill(CardTheme.dangerSoft)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(CardTheme.danger)
                            }

                        VStack(alignment: .leading, spacing: 3) {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CardTheme.surfaceCard)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(CardTheme.borderSubtle, lineWidth: 1)
            }

            // Large Action Buttons (at least 60pt tall)
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
        CardTheme.canvas.ignoresSafeArea()
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
