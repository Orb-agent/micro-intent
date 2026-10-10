import SwiftUI

public struct ConflictCardView: View {
    public let card: ConflictCard
    public let onAction: ((String) -> Void)?

    public init(card: ConflictCard, onAction: ((String) -> Void)? = nil) {
        self.card = card
        self.onAction = onAction
    }

    private var verdictPill: some View {
        switch card.verdict {
        case .fits:
            return GlassPillView(
                iconName: "checkmark.seal.fill",
                text: "Passt zeitlich",
                tintColor: CardTheme.emeraldGreen
            )
        case .tight:
            return GlassPillView(
                iconName: "clock.badge.exclamationmark.fill",
                text: "Zeitlich knapp",
                tintColor: CardTheme.amberYellow
            )
        case .clash:
            return GlassPillView(
                iconName: "exclamationmark.triangle.fill",
                text: "Terminkonflikt",
                tintColor: CardTheme.coralRed
            )
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header with verdict pill
            HStack {
                verdictPill
                Spacer()
                Text(CardFormatters.formatShortDate(card.event.start))
                    .font(CardTheme.captionFont)
                    .foregroundColor(CardTheme.textSecondary)
            }

            // Note Banner (if present)
            if let note = card.note, !note.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(CardTheme.amberYellow)
                    Text(note)
                        .font(CardTheme.bodyFont)
                        .foregroundColor(CardTheme.textPrimary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
            }

            // Comparison Sections: Current Event vs Proposed Event
            VStack(spacing: 12) {
                // Event 1: Current Event
                HStack(alignment: .center, spacing: 14) {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "calendar")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(CardTheme.textPrimary)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Aktueller Termin")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(CardTheme.textMuted)
                            .textCase(.uppercase)

                        Text(card.event.title)
                            .font(CardTheme.headlineFont)
                            .foregroundColor(CardTheme.textPrimary)
                    }

                    Spacer()

                    Text("\(CardFormatters.formatTime(card.event.start)) – \(CardFormatters.formatTime(card.event.end))")
                        .font(CardTheme.headlineFont)
                        .foregroundColor(CardTheme.textSecondary)
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }

                // Buffer indicator between events
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(CardTheme.textMuted)
                    Text("Puffer: \(CardFormatters.formatDuration(from: card.event.end, to: card.proposal.start))")
                        .font(CardTheme.captionFont)
                        .foregroundColor(CardTheme.textMuted)
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                }
                .padding(.horizontal, 8)

                // Event 2: Proposed Event
                HStack(alignment: .center, spacing: 14) {
                    Circle()
                        .fill(CardTheme.emeraldGreen.opacity(0.25))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(CardTheme.emeraldGreen)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Neuer Vorschlag")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(CardTheme.emeraldGreen)
                            .textCase(.uppercase)

                        Text(card.proposal.title)
                            .font(CardTheme.headlineFont)
                            .foregroundColor(CardTheme.textPrimary)

                        if let place = card.proposal.place, !place.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(place)
                                    .font(CardTheme.captionFont)
                            }
                            .foregroundColor(CardTheme.textSecondary)
                        }
                    }

                    Spacer()

                    Text(CardFormatters.formatTime(card.proposal.start))
                        .font(CardTheme.timeFont)
                        .foregroundColor(CardTheme.textPrimary)
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CardTheme.emeraldGreen.opacity(0.10))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(CardTheme.emeraldGreen.opacity(0.25), lineWidth: 1)
                }
            }

            // Large Action Buttons
            CardActionButtonsView(
                confirmTitle: "Vorschlag annehmen",
                cancelTitle: "Ablehnen",
                confirmActionId: "confirm_conflict",
                cancelActionId: "cancel_conflict",
                onAction: onAction
            )
        }
        .darkGlassCard()
    }
}

// MARK: - Previews

#Preview("Conflict Card - Dark") {
    ZStack {
        Color.black.ignoresSafeArea()
        ConflictCardView(card: Card.sampleConflict) { action in
            print("Action tapped: \(action)")
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Conflict Card - Light") {
    ZStack {
        Color(white: 0.92).ignoresSafeArea()
        ConflictCardView(card: Card.sampleConflict) { action in
            print("Action tapped: \(action)")
        }
        .padding()
    }
    .preferredColorScheme(.light)
}
