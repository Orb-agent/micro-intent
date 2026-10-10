import SwiftUI

public struct NativeCardView: View {
    public let card: Card
    public let onAction: ((String) -> Void)?

    public init(card: Card, onAction: ((String) -> Void)? = nil) {
        self.card = card
        self.onAction = onAction
    }

    public var body: some View {
        switch card {
        case .train(let trainCard):
            TrainCardView(card: trainCard, onAction: onAction)
        case .conflict(let conflictCard):
            ConflictCardView(card: conflictCard, onAction: onAction)
        case .event(let eventCard):
            EventCardView(card: eventCard, onAction: onAction)
        case .flight(let flightCard):
            FlightCardView(card: flightCard, onAction: onAction)
        }
    }
}

// MARK: - Native Card List / Feed Container

public struct NativeCardListView: View {
    public let cards: [Card]
    public let onAction: ((String) -> Void)?

    public init(cards: [Card], onAction: ((String) -> Void)? = nil) {
        self.cards = cards
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: 16) {
            ForEach(cards) { card in
                NativeCardView(card: card, onAction: onAction)
            }
        }
    }
}

// MARK: - Previews

#Preview("All Cards - Dark Mode") {
    ScrollView {
        VStack(spacing: 20) {
            Text("Native SwiftUI Cards")
                .font(CardTheme.titleFont)
                .foregroundColor(CardTheme.textPrimary)
                .padding(.top)

            NativeCardListView(cards: Card.allSamples) { actionId in
                print("Action: \(actionId)")
            }
        }
        .padding()
    }
    .background(CardTheme.canvas.ignoresSafeArea())
    .preferredColorScheme(.dark)
}

#Preview("All Cards - Light Mode") {
    ScrollView {
        VStack(spacing: 20) {
            Text("Native SwiftUI Cards")
                .font(CardTheme.titleFont)
                .foregroundColor(.black)
                .padding(.top)

            NativeCardListView(cards: Card.allSamples) { actionId in
                print("Action: \(actionId)")
            }
        }
        .padding()
    }
    .background(Color(white: 0.94).ignoresSafeArea())
    .preferredColorScheme(.light)
}

#Preview("Demo Reply Cards (Conflict + Train)") {
    ScrollView {
        VStack(spacing: 20) {
            Text("Demo Question Cards")
                .font(CardTheme.titleFont)
                .foregroundColor(CardTheme.textPrimary)
                .padding(.top)

            NativeCardListView(cards: Card.demoCards) { actionId in
                print("Action: \(actionId)")
            }
        }
        .padding()
    }
    .background(CardTheme.canvas.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
