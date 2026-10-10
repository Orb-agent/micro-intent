import A2UISwiftUI
import SwiftUI

/// A small, non-modal A2UI notice. It leaves the orb and voice session usable.
struct ConflictNotice: View {
    let surfaces: [SurfaceViewModel]
    let cards: [CardPayload]
    let dismiss: () -> Void

    @Environment(\.typeScale) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Calendar needs attention")
                    .font(type.meta)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Dismiss calendar conflict")
            }
            ScrollView {
                CardsView(surfaces: surfaces, cards: cards, compact: true)
            }
            .frame(height: min(CGFloat(cards.count) * (type.name == "large" ? 190 : 150), 260))
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxWidth: 340)
        .glassSurface(.panel, cornerRadius: Theme.Radius.xxl)
    }
}
