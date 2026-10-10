import SwiftUI

public struct TrainCardView: View {
    public let card: TrainCard
    public let onAction: ((String) -> Void)?

    public init(card: TrainCard, onAction: ((String) -> Void)? = nil) {
        self.card = card
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header pills: Line, Platform, Delay
            HStack(spacing: 8) {
                GlassPillView(
                    iconName: "train.side.front.car",
                    text: card.line,
                    tintColor: CardTheme.skyBlue
                )

                if let platform = card.platform, !platform.isEmpty {
                    GlassPillView(
                        iconName: "tram.fill",
                        text: "Gleis \(platform)",
                        tintColor: CardTheme.purpleAccent
                    )
                }

                Spacer()

                if let delay = card.delayMin {
                    if delay == 0 {
                        GlassPillView(
                            iconName: "checkmark.circle.fill",
                            text: "Pünktlich",
                            tintColor: CardTheme.emeraldGreen
                        )
                    } else {
                        GlassPillView(
                            iconName: "exclamationmark.circle.fill",
                            text: "+\(delay) Min.",
                            tintColor: CardTheme.coralRed
                        )
                    }
                }
            }

            // Times display
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CardFormatters.formatTime(card.departure))
                        .font(CardTheme.timeFont)
                        .foregroundColor(CardTheme.textPrimary)
                    Text(card.from)
                        .font(CardTheme.stationFont)
                        .foregroundColor(CardTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(CardTheme.textMuted)

                    Text(CardFormatters.formatDuration(from: card.departure, to: card.arrival))
                        .font(CardTheme.captionFont)
                        .foregroundColor(CardTheme.textMuted)
                }
                .padding(.horizontal, 8)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(CardFormatters.formatTime(card.arrival))
                        .font(CardTheme.timeFont)
                        .foregroundColor(CardTheme.textPrimary)
                    Text(card.to)
                        .font(CardTheme.stationFont)
                        .foregroundColor(CardTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            // Info meta row: Date, Transfers
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                    Text(CardFormatters.formatShortDate(card.departure))
                        .font(CardTheme.captionFont)
                }
                .foregroundColor(CardTheme.textSecondary)

                HStack(spacing: 6) {
                    Image(systemName: card.transfers == 0 ? "arrow.right.circle" : "arrow.triangle.swap")
                        .font(.system(size: 14, weight: .semibold))
                    Text(card.transfers == 0 ? "Direktverbindung" : "\(card.transfers) Umstieg(e)")
                        .font(CardTheme.captionFont)
                }
                .foregroundColor(CardTheme.textSecondary)
            }
            .padding(.horizontal, 4)

            // Large Action Buttons
            CardActionButtonsView(
                confirmTitle: "Bestätigen",
                cancelTitle: "Abbrechen",
                confirmActionId: "confirm_train",
                cancelActionId: "cancel_train",
                onAction: onAction
            )
        }
        .darkGlassCard()
    }
}

// MARK: - Previews

#Preview("Train Card - Dark") {
    ZStack {
        Color.black.ignoresSafeArea()
        TrainCardView(card: Card.sampleTrain) { action in
            print("Action tapped: \(action)")
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Train Card - Light") {
    ZStack {
        Color(white: 0.92).ignoresSafeArea()
        TrainCardView(card: Card.sampleTrain) { action in
            print("Action tapped: \(action)")
        }
        .padding()
    }
    .preferredColorScheme(.light)
}
