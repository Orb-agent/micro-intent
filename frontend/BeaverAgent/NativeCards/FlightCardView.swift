import SwiftUI

public struct FlightCardView: View {
    public let card: FlightCard
    public let onAction: ((String) -> Void)?

    public init(card: FlightCard, onAction: ((String) -> Void)? = nil) {
        self.card = card
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header pills: Flight number, Booking reference
            HStack(spacing: 8) {
                GlassPillView(
                    iconName: "airplane",
                    text: card.flightNumber,
                    tintColor: CardTheme.skyBlue
                )

                Spacer()

                if let ref = card.bookingRef, !ref.isEmpty {
                    GlassPillView(
                        iconName: "tag.fill",
                        text: "Ref: \(ref)",
                        tintColor: CardTheme.purpleAccent
                    )
                }
            }

            // Route & Times display
            HStack(alignment: .firstTextBaseline) {
                // Departure
                VStack(alignment: .leading, spacing: 2) {
                    Text(CardFormatters.formatTime(card.departure))
                        .font(CardTheme.timeFont)
                        .foregroundColor(CardTheme.textPrimary)

                    Text(card.from)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(CardTheme.textPrimary)

                    Text(CardFormatters.formatShortDate(card.departure))
                        .font(CardTheme.captionFont)
                        .foregroundColor(CardTheme.textSecondary)
                }

                Spacer()

                // Airplane Flight Track
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(CardTheme.skyBlue)
                            .frame(width: 6, height: 6)

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [CardTheme.skyBlue, CardTheme.skyBlue.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)

                        Image(systemName: "airplane")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(CardTheme.skyBlue)

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [CardTheme.skyBlue.opacity(0.3), CardTheme.skyBlue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)

                        Circle()
                            .fill(CardTheme.skyBlue)
                            .frame(width: 6, height: 6)
                    }
                    .frame(width: 110)

                    Text(CardFormatters.formatDuration(from: card.departure, to: card.arrival))
                        .font(CardTheme.captionFont)
                        .foregroundColor(CardTheme.textMuted)
                }
                .padding(.horizontal, 6)

                Spacer()

                // Arrival
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CardFormatters.formatTime(card.arrival))
                        .font(CardTheme.timeFont)
                        .foregroundColor(CardTheme.textPrimary)

                    Text(card.to)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(CardTheme.textPrimary)

                    Text(CardFormatters.formatShortDate(card.arrival))
                        .font(CardTheme.captionFont)
                        .foregroundColor(CardTheme.textSecondary)
                }
            }

            // Large Action Buttons
            CardActionButtonsView(
                confirmTitle: "Bestätigen",
                cancelTitle: "Abbrechen",
                confirmActionId: "confirm_flight",
                cancelActionId: "cancel_flight",
                onAction: onAction
            )
        }
        .darkGlassCard()
    }
}

// MARK: - Previews

#Preview("Flight Card - Dark") {
    ZStack {
        Color.black.ignoresSafeArea()
        FlightCardView(card: Card.sampleFlight) { action in
            print("Action tapped: \(action)")
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Flight Card - Light") {
    ZStack {
        Color(white: 0.92).ignoresSafeArea()
        FlightCardView(card: Card.sampleFlight) { action in
            print("Action tapped: \(action)")
        }
        .padding()
    }
    .preferredColorScheme(.light)
}
