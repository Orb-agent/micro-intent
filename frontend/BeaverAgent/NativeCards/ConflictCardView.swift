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
            return "Fits schedule: No overlap between events."
        case .tight:
            return "Tight schedule: Very little buffer between events."
        case .clash:
            return "Schedule conflict: Both events overlap."
        }
    }

    private var suggestedFixButtonTitle: String {
        switch card.verdict {
        case .fits:
            return "Accept Proposal"
        case .tight:
            return "Adjust Event"
        case .clash:
            return "Move Event"
        }
    }

    private var verdictPill: some View {
        switch card.verdict {
        case .fits:
            return GlassPillView(
                iconName: "checkmark.seal.fill",
                text: "Fits schedule",
                tintColor: CardTheme.successText
            )
        case .tight:
            return GlassPillView(
                iconName: "clock.badge.exclamationmark.fill",
                text: "Tight schedule",
                tintColor: CardTheme.warnText
            )
        case .clash:
            return GlassPillView(
                iconName: "exclamationmark.triangle.fill",
                text: "Schedule Conflict",
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
                HStack(alignment: .center, spacing: 12) {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "calendar")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(CardTheme.textPrimary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.event.title)
                            .font(CardTheme.headlineFont)
                            .foregroundColor(CardTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text("Current Event")
                            .font(CardTheme.captionFont)
                            .foregroundColor(CardTheme.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text("\(CardFormatters.formatTime(card.event.start)) – \(CardFormatters.formatTime(card.event.end))")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(CardTheme.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(CardTheme.surfaceCard)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(CardTheme.borderSubtle, lineWidth: 1)
                }

                // Event 2: Proposed Event
                HStack(alignment: .center, spacing: 12) {
                    Circle()
                        .fill(CardTheme.accentSoft)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(CardTheme.accentText)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.proposal.title)
                            .font(CardTheme.headlineFont)
                            .foregroundColor(CardTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let place = card.proposal.place, !place.isEmpty {
                            Text(place)
                                .font(CardTheme.captionFont)
                                .foregroundColor(CardTheme.textSecondary)
                                .lineLimit(1)
                        } else {
                            Text("Proposed Event")
                                .font(CardTheme.captionFont)
                                .foregroundColor(CardTheme.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(CardFormatters.formatTime(card.proposal.start))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(CardTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
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
            // Rail Hour Labels: 17:00, 19:30, 22:00 with identical font and weight (>= 17pt)
            HStack {
                Text("17:00")
                    .font(CardTheme.captionFont)
                    .foregroundColor(CardTheme.textSecondary)
                Spacer()
                Text("19:30")
                    .font(CardTheme.captionFont)
                    .foregroundColor(CardTheme.textSecondary)
                Spacer()
                Text("22:00")
                    .font(CardTheme.captionFont)
                    .foregroundColor(CardTheme.textSecondary)
            }

            // Two separate thin lanes on the 17:00 - 22:00 axis
            GeometryReader { geometry in
                let width = geometry.size.width
                let trackHeight: CGFloat = 52
                let laneHeight: CGFloat = 12
                let lane1Y: CGFloat = 8
                let lane2Y: CGFloat = 32

                // Calculate event 1 (top lane) geometry
                let e1StartMin = minutesFrom1700(date: event.start)
                let e1EndMin = minutesFrom1700(date: event.end)
                let e1X = width * (e1StartMin / totalSpanMinutes)
                let e1W = max(16, width * ((e1EndMin - e1StartMin) / totalSpanMinutes))

                // Calculate proposal / event 2 (bottom lane) geometry
                let pStartMin = minutesFrom1700(date: proposal.start)
                let pEndMin = minutesFrom1700(date: proposalEnd)
                let pX = width * (pStartMin / totalSpanMinutes)
                let pW = max(16, width * ((pEndMin - pStartMin) / totalSpanMinutes))

                // Overlap calculation
                let overlapStart = max(event.start, proposal.start)
                let overlapEnd = min(event.end, proposalEnd)
                let hasOverlap = overlapEnd > overlapStart

                let oStartMin = hasOverlap ? minutesFrom1700(date: overlapStart) : 0
                let oEndMin = hasOverlap ? minutesFrom1700(date: overlapEnd) : 0
                let oX = width * (oStartMin / totalSpanMinutes)
                let oW = max(18, width * ((oEndMin - oStartMin) / totalSpanMinutes))
                let oCenterX = oX + (oW / 2)

                ZStack(alignment: .topLeading) {
                    // Full track background container
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CardTheme.surfaceControl)
                        .frame(height: trackHeight)

                    // Hour tick dividers at 18:00, 19:00, 20:00, 21:00
                    ForEach(1...4, id: \.self) { hourOffset in
                        let tickX = width * (Double(hourOffset * 60) / totalSpanMinutes)
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 1, height: trackHeight)
                            .offset(x: tickX)
                    }

                    // Background track groove for Lane 1 (top)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: width - 8, height: laneHeight)
                        .offset(x: 4, y: lane1Y)

                    // Background track groove for Lane 2 (bottom)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: width - 8, height: laneHeight)
                        .offset(x: 4, y: lane2Y)

                    // Overlap background highlight band across both lanes
                    if hasOverlap {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CardTheme.warn.opacity(0.18))
                            .frame(width: min(oW, width - oX), height: trackHeight - 8)
                            .offset(x: oX, y: 4)
                    }

                    // --- LANE 1 (Current Event) ---
                    // Base event 1 bar (neutral slate)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.40))
                        .frame(width: min(e1W, width - e1X), height: laneHeight)
                        .offset(x: e1X, y: lane1Y)

                    // Highlight overlapping span on Lane 1 in warning color
                    if hasOverlap {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(CardTheme.warn)
                            .frame(width: min(oW, width - oX), height: laneHeight)
                            .offset(x: oX, y: lane1Y)
                    }

                    // --- LANE 2 (Proposed Event) ---
                    // Base event 2 bar (accent cyan)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CardTheme.accent)
                        .frame(width: min(pW, width - pX), height: laneHeight)
                        .offset(x: pX, y: lane2Y)

                    // Highlight overlapping span on Lane 2 in warning color
                    if hasOverlap {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(CardTheme.warn)
                            .frame(width: min(oW, width - oX), height: laneHeight)
                            .offset(x: oX, y: lane2Y)
                    }

                    // Warning icon centered on the overlapping span
                    if hasOverlap {
                        ZStack {
                            Circle()
                                .fill(CardTheme.warn)
                                .frame(width: 24, height: 24)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(red: 11/255, green: 13/255, blue: 18/255))
                        }
                        .shadow(color: CardTheme.warn.opacity(0.6), radius: 6, x: 0, y: 0)
                        .offset(x: max(14, min(width - 24, oCenterX - 12)), y: 14)
                    }
                }
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
            title: "Meeting with Team",
            start: CardDateParser.parse("2026-10-15T18:00:00+02:00") ?? Date(),
            end: CardDateParser.parse("2026-10-15T19:30:00+02:00") ?? Date()
        ),
        proposal: ConflictProposal(
            title: "Dinner in Bern",
            start: CardDateParser.parse("2026-10-15T19:00:00+02:00") ?? Date(),
            place: "Bern"
        ),
        verdict: .clash,
        note: "30 min overlap between Meeting and Dinner"
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
