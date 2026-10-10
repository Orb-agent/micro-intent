import A2UISwiftCore
import A2UISwiftUI
import SwiftUI

/// The reply's cards. A2UI surfaces are the main path (contracts § A2UI); when a reply
/// has cards but no `a2ui` frame, `nativeCards` is the switch point for native views.
struct CardsView: View {
    let surfaces: [SurfaceViewModel]
    let cards: [CardPayload]

    var body: some View {
        if !surfaces.isEmpty {
            VStack(spacing: 8) {
                ForEach(surfaces.indices, id: \.self) { i in
                    A2UISurfaceView(viewModel: surfaces[i], scrolls: false)
                }
            }
            .a2uiCatalogItem(.card) { context in
                guard let child = context.node.children.first else { return nil }
                return AnyView(GlassCard { context.buildChild(child) })
            }

        } else if !cards.isEmpty {
            nativeCards(cards)
        }
    }

    /// Fallback for replies without `a2ui` (WP1 task 3). Native card views from
    /// `frontend/BeaverAgent/NativeCards/` plug in here, e.g.
    /// `ForEach(cards) { NativeCardView(card: $0, onAction: ...) }`.
    @ViewBuilder
    private func nativeCards(_ cards: [CardPayload]) -> some View {
        EmptyView()
    }
}

/// The A2UI `Card`, drawn as a glass card from the prototype's result panel.
private struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Theme.surfaceCard))
            .overlay(shape.strokeBorder(Theme.borderSubtle, lineWidth: 1))
            .padding(.vertical, 6)
    }
}

extension SurfaceViewModel {
    /// Maps the text variants the server uses onto the type scale: `h2` is the hero
    /// line (a time or verdict), `body` the detail, `caption` the meta line.
    func applyAppStyle(_ type: TypeScale = .regular) {
        var style = a2uiStyle
        style.primaryColor = Theme.accent
        style.leafMargin = 4
        let heading = A2UIStyle.TextStyle(font: type.time, color: Theme.textPrimary)
        style.textStyles = [
            "h1": heading,
            "h2": heading,
            "h3": .init(font: type.bodyStrong, color: Theme.textPrimary),
            "h4": .init(font: type.bodyStrong, color: Theme.textPrimary),
            "h5": .init(font: type.bodyStrong, color: Theme.textPrimary),
            "body": .init(font: type.body, color: Theme.textSecondary),
            "caption": .init(font: type.meta, color: Theme.textMuted),
        ]
        a2uiStyle = style
    }
}
