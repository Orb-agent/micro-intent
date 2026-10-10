import SwiftUI

public struct TrainCardView: View {
    public let card: TrainCard
    public let onAction: ((String) -> Void)?

    public init(card: TrainCard, onAction: ((String) -> Void)? = nil) {
        self.card = card
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header: SBB tile (36 in service red), Train line pill, Delay pill
            HStack(spacing: 10) {
                // SBB Tile in service red
                HStack(spacing: 6) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 17, weight: .bold))
                    Text("SBB")
                        .font(CardTheme.badgeFont)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CardTheme.sbbRed)
                }
                .fixedSize(horizontal: true, vertical: false)

                // Train Line
                GlassPillView(
                    iconName: "train.side.front.car",
                    text: card.line,
                    tintColor: CardTheme.accentText
                )

                Spacer()

                if let delay = card.delayMin {
                    if delay == 0 {
                        GlassPillView(
                            iconName: "checkmark.circle.fill",
                            text: "Pünktlich",
                            tintColor: CardTheme.successText
                        )
                    } else {
                        GlassPillView(
                            iconName: "exclamationmark.circle.fill",
                            text: "+\(delay) Min.",
                            tintColor: CardTheme.dangerText
                        )
                    }
                }
            }

            // Hero Departure Time (48pt+) as the primary visual focus, plus Platform
            VStack(alignment: .leading, spacing: 6) {
                Text("Abfahrt")
                    .font(CardTheme.captionFont)
                    .foregroundColor(CardTheme.textMuted)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline) {
                    Text(CardFormatters.formatTime(card.departure))
                        .font(CardTheme.heroDeparture)
                        .foregroundColor(CardTheme.textPrimary)

                    Spacer()

                    if let platform = card.platform, !platform.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "signpost.right.fill")
                                .font(.system(size: 17, weight: .bold))
                            Text("Gleis \(platform)")
                                .font(CardTheme.titleFont)
                        }
                        .foregroundColor(Color(red: 210/255, green: 170/255, blue: 255/255))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(red: 170/255, green: 102/255, blue: 245/255).opacity(0.20))
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(red: 170/255, green: 102/255, blue: 245/255).opacity(0.35), lineWidth: 1)
                        }
                    }
                }

                Text(card.from)
                    .font(CardTheme.stationFont)
                    .foregroundColor(CardTheme.textPrimary)
                    .lineLimit(1)
            }

            // Journey Route: Destination, Arrival & Duration
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ankunft: \(CardFormatters.formatTime(card.arrival))")
                        .font(CardTheme.timeFont)
                        .foregroundColor(CardTheme.textPrimary)

                    Text(card.to)
                        .font(CardTheme.stationFont)
                        .foregroundColor(CardTheme.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 17, weight: .semibold))
                        Text(CardFormatters.formatDuration(from: card.departure, to: card.arrival))
                            .font(CardTheme.headlineFont)
                    }
                    .foregroundColor(CardTheme.accentText)

                    Text(card.transfers == 0 ? "Direktverbindung" : "\(card.transfers) Umstieg(e)")
                        .font(CardTheme.captionFont)
                        .foregroundColor(CardTheme.textMuted)
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CardTheme.surfaceCard)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(CardTheme.borderSubtle, lineWidth: 1)
            }

            // Info meta row: Date
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .semibold))
                    Text(CardFormatters.formatShortDate(card.departure))
                        .font(CardTheme.captionFont)
                }
                .foregroundColor(CardTheme.textSecondary)
            }
            .padding(.horizontal, 4)

            // Large Action Buttons (at least 60pt tall)
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
        CardTheme.canvas.ignoresSafeArea()
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
