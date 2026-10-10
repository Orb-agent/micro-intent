import SwiftUI

public struct ConflictCardView: View {
    public let card: ConflictCard
    public let onAction: ((String) -> Void)?

    public init(card: ConflictCard, onAction: ((String) -> Void)? = nil) {
        self.card = card
        self.onAction = onAction
    }

    private var plainLineAbove: String {
        if let note = card.note, !note.isEmpty {
            return note
        }
        switch card.verdict {
        case .fits:
            return "Passt zeitlich: Keine Terminüberschneidung."
        case .tight:
            return "Zeitlich knapp: Sehr wenig Puffer zwischen den Terminen."
        case .clash:
            return "Terminkonflikt: Beide Termine überschneiden sich."
        }
    }

    private var suggestedFixButtonTitle: String {
        switch card.verdict {
        case .fits:
            return "Vorschlag übernehmen"
        case .tight:
            return "Termin anpassen"
        case .clash:
            return "Termin verschieben"
        }
    }

    private var verdictPill: some View {
        switch card.verdict {
        case .fits:
            return GlassPillView(
                iconName: "checkmark.seal.fill",
                text: "Passt zeitlich",
                tintColor: CardTheme.successText
            )
        case .tight:
            return GlassPillView(
                iconName: "clock.badge.exclamationmark.fill",
                text: "Zeitlich knapp",
                tintColor: CardTheme.warnText
            )
        case .clash:
            return GlassPillView(
                iconName: "exclamationmark.triangle.fill",
                text: "Terminkonflikt",
                tintColor: CardTheme.dangerText
            )
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with Verdict Pill & Date
            HStack {
                verdictPill
                Spacer()
                Text(CardFormatters.formatShortDate(card.event.start))
                    .font(CardTheme.captionFont)
                    .foregroundColor(CardTheme.textSecondary)
            }

            // One plain line above the mini day rail
            Text(plainLineAbove)
                .font(CardTheme.headlineFont)
                .foregroundColor(CardTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Mini Day Rail (17:00 - 22:00)
            MiniDayRailView(
                event: card.event,
                proposal: card.proposal,
                verdict: card.verdict
            )

            // Event Details Cards (Current Event & Proposal)
            VStack(spacing: 12) {
                // Event 1: Current Event
                HStack(alignment: .center, spacing: 14) {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "calendar")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(CardTheme.textPrimary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.event.title)
                            .font(CardTheme.headlineFont)
                            .foregroundColor(CardTheme.textPrimary)

                        Text("Aktueller Termin")
                            .font(CardTheme.captionFont)
                            .foregroundColor(CardTheme.textMuted)
                    }

                    Spacer()

                    Text("\(CardFormatters.formatTime(card.event.start)) – \(CardFormatters.formatTime(card.event.end))")
                        .font(CardTheme.headlineFont)
                        .foregroundColor(CardTheme.textSecondary)
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CardTheme.surfaceCard)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(CardTheme.borderSubtle, lineWidth: 1)
                }

                // Event 2: Proposed Event
                HStack(alignment: .center, spacing: 14) {
                    Circle()
                        .fill(CardTheme.accentSoft)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(CardTheme.accentText)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.proposal.title)
                            .font(CardTheme.headlineFont)
                            .foregroundColor(CardTheme.textPrimary)

                        if let place = card.proposal.place, !place.isEmpty {
                            Text(place)
                                .font(CardTheme.captionFont)
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
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CardTheme.accentSoft)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(CardTheme.accentBorder, lineWidth: 1)
                }
            }

            // One suggested-fix button (at least 60pt tall)
            Button {
                onAction?("suggested_fix")
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                    Text(suggestedFixButtonTitle)
                        .font(CardTheme.buttonFont)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: CardTheme.minButtonHeight)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: CardTheme.buttonCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        CardTheme.accent,
                                        CardTheme.accentStrong
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        RoundedRectangle(cornerRadius: CardTheme.buttonCornerRadius, style: .continuous)
                            .strokeBorder(CardTheme.accentBorder, lineWidth: 1)
                    }
                }
                .shadow(
                    color: CardTheme.accent.opacity(0.35),
                    radius: 12,
                    x: 0,
                    y: 4
                )
            }
            .buttonStyle(CardScaleButtonStyle())
            .accessibilityLabel(suggestedFixButtonTitle)
        }
        .darkGlassCard()
    }
}

// MARK: - Mini Day Rail (17:00 - 22:00)

public struct MiniDayRailView: View {
    public let event: ConflictEvent
    public let proposal: ConflictProposal
    public let verdict: ConflictVerdict

    // Rail bounds: 17:00 to 22:00 (5 hours = 300 minutes)
    private let railStartHour = 17
    private let railEndHour = 22
    private let totalSpanMinutes: Double = 300.0

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = CardDateParser.zurichTimeZone
        return cal
    }

    private func minutesFrom1700(date: Date) -> Double {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minutes = Double((hour - railStartHour) * 60 + minute)
        return min(max(minutes, 0), totalSpanMinutes)
    }

    private var proposalEnd: Date {
        // If not explicit, assume 90 min proposal
        proposal.start.addingTimeInterval(5400)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Rail Hour Labels: 17:00, 19:30, 22:00 (>= 17pt)
            HStack {
                Text("17:00")
                    .font(CardTheme.captionFont)
                    .foregroundColor(CardTheme.textMuted)
                Spacer()
                Text("19:30")
                    .font(CardTheme.captionFont)
                    .foregroundColor(CardTheme.textTertiary)
                Spacer()
                Text("22:00")
                    .font(CardTheme.captionFont)
                    .foregroundColor(CardTheme.textMuted)
            }

            // Visual Rail Canvas
            GeometryReader { geometry in
                let width = geometry.size.width
                let height: CGFloat = 44

                ZStack(alignment: .leading) {
                    // Rail background track
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CardTheme.surfaceControl)
                        .frame(height: height)

                    // Hour tick dividers at 18:00, 19:00, 20:00, 21:00
                    ForEach(1...4, id: \.self) { hourOffset in
                        let tickX = width * (Double(hourOffset * 60) / totalSpanMinutes)
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1, height: height)
                            .offset(x: tickX)
                    }

                    // Event 1 block
                    let e1StartMin = minutesFrom1700(date: event.start)
                    let e1EndMin = minutesFrom1700(date: event.end)
                    let e1X = width * (e1StartMin / totalSpanMinutes)
                    let e1W = max(24, width * ((e1EndMin - e1StartMin) / totalSpanMinutes))

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(white: 0.35).opacity(0.85))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        }
                        .frame(width: min(e1W, width - e1X), height: height - 8)
                        .offset(x: e1X, y: 0)

                    // Event 2 (Proposal) block
                    let pStartMin = minutesFrom1700(date: proposal.start)
                    let pEndMin = minutesFrom1700(date: proposalEnd)
                    let pX = width * (pStartMin / totalSpanMinutes)
                    let pW = max(24, width * ((pEndMin - pStartMin) / totalSpanMinutes))

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CardTheme.accentStrong.opacity(0.85))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(CardTheme.accentBorder, lineWidth: 1)
                        }
                        .frame(width: min(pW, width - pX), height: height - 8)
                        .offset(x: pX, y: 0)

                    // Overlap region in accent warning color (#FBBF24)
                    let overlapStart = max(event.start, proposal.start)
                    let overlapEnd = min(event.end, proposalEnd)

                    if overlapEnd > overlapStart {
                        let oStartMin = minutesFrom1700(date: overlapStart)
                        let oEndMin = minutesFrom1700(date: overlapEnd)
                        let oX = width * (oStartMin / totalSpanMinutes)
                        let oW = max(18, width * ((oEndMin - oStartMin) / totalSpanMinutes))

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CardTheme.warn)
                            .overlay {
                                HStack(spacing: 2) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color(red: 11/255, green: 13/255, blue: 18/255))
                                }
                            }
                            .frame(width: min(oW, width - oX), height: height - 8)
                            .offset(x: oX, y: 0)
                            .shadow(color: CardTheme.warn.opacity(0.6), radius: 8, x: 0, y: 0)
                    } else if verdict == .clash {
                        // In case of conflict without direct time overlap (e.g. transit travel clash)
                        let clashX = width * (e1EndMin / totalSpanMinutes)
                        let clashW = max(20, width * ((pStartMin - e1EndMin) / totalSpanMinutes))

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(CardTheme.warn.opacity(0.9))
                            .overlay {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(red: 11/255, green: 13/255, blue: 18/255))
                            }
                            .frame(width: min(clashW, width - clashX), height: height - 8)
                            .offset(x: clashX, y: 0)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 52)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CardTheme.surfaceCard)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CardTheme.borderSubtle, lineWidth: 1)
        }
    }
}

// MARK: - Previews

#Preview("Conflict Card (Fits) - Dark") {
    ZStack {
        CardTheme.canvas.ignoresSafeArea()
        ConflictCardView(card: Card.sampleConflict) { action in
            print("Action tapped: \(action)")
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Conflict Card (Clash with Overlap) - Dark") {
    let clashCard = ConflictCard(
        event: ConflictEvent(
            title: "Meeting mit Team",
            start: CardDateParser.parse("2026-10-15T18:00:00+02:00") ?? Date(),
            end: CardDateParser.parse("2026-10-15T19:30:00+02:00") ?? Date()
        ),
        proposal: ConflictProposal(
            title: "Dinner in Bern",
            start: CardDateParser.parse("2026-10-15T19:00:00+02:00") ?? Date(),
            place: "Bern"
        ),
        verdict: .clash,
        note: "30 Min. Überschneidung zwischen Meeting und Dinner"
    )

    return ZStack {
        CardTheme.canvas.ignoresSafeArea()
        ConflictCardView(card: clashCard) { action in
            print("Action tapped: \(action)")
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
