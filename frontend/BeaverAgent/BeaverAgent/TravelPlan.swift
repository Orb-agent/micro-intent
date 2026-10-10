import Foundation
import SwiftUI

/// A route suggestion from the existing cards, independent of the A2UI rendering path.
struct TravelPlan {
    let title: String
    let origin: String
    let destination: String
    let start: Date?
    let connection: Connection?
    let mapsURL: URL

    struct Connection {
        let line: String
        let departure: Date
        let arrival: Date
        let delayMinutes: Int
    }

    private struct Fields: Decodable {
        let kind: String
        let title: String?
        let location: String?
        let start: String?
        let from: String?
        let to: String?
        let line: String?
        let departure: String?
        let arrival: String?
        let delay_min: Int?
    }

    static func make(cards: [CardPayload], question: String, now: Date = Date()) -> TravelPlan? {
        guard !cards.contains(where: { $0.kind == "conflict" }) else { return nil }
        let decoded = cards.compactMap { try? JSONDecoder().decode(Fields.self, from: $0.raw) }
        let event = decoded.first { card in
            card.kind == "event" && !trim(card.location).isEmpty
                && (date(card.start) ?? .distantPast) > now
        }
        let deadline = date(event?.start) ?? .distantFuture
        let train = decoded.first { card in
            guard card.kind == "train", !trim(card.to).isEmpty,
                  let departure = date(card.departure), let arrival = date(card.arrival) else { return false }
            let adjustedArrival = arrival.addingTimeInterval(Double(max(0, card.delay_min ?? 0)) * 60)
            return departure > now && arrival >= departure && adjustedArrival <= deadline
        }
        let attending = question.range(
            of: "\\b(attend|make it|can i go|want to go|asistir|llegar|puedo ir|quiero ir|ir al evento)\\b",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        guard train != nil || (event != nil && attending && !cards.contains(where: { $0.kind == "train" })) else {
            return nil
        }
        let origin = trim(train?.from).isEmpty ? "Winterthur" : trim(train?.from)
        let destination = event.map { trim($0.location) } ?? trim(train?.to)
        var url = URLComponents(string: "https://www.google.com/maps/dir/")!
        url.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: origin),
            URLQueryItem(name: "destination", value: destination),
            URLQueryItem(name: "travelmode", value: "transit"),
        ]
        guard let mapsURL = url.url, mapsURL.absoluteString.count <= 2048 else { return nil }
        let connection: Connection?
        if let train, let departure = date(train.departure), let arrival = date(train.arrival) {
            connection = Connection(line: train.line ?? "Train", departure: departure,
                                    arrival: arrival, delayMinutes: max(0, train.delay_min ?? 0))
        } else {
            connection = nil
        }
        return TravelPlan(title: event?.title ?? "Suggested connection", origin: origin,
                          destination: destination, start: date(event?.start),
                          connection: connection, mapsURL: mapsURL)
    }

    private static func trim(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return CardDateParser.parse(value)
    }
}

struct TravelSheet: View {
    let plan: TravelPlan
    @Environment(\.dismiss) private var dismiss
    @Environment(\.typeScale) private var type

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(plan.title).font(type.display).foregroundStyle(Theme.textPrimary)
                    Text("\(plan.origin) → \(plan.destination)")
                        .font(type.bodyStrong).foregroundStyle(Theme.textSecondary)
                    if let connection = plan.connection {
                        Text("\(connection.line) · \(Self.day(connection.departure))")
                            .font(type.bodyStrong)
                        Text("\(Self.time(connection.departure)) → \(Self.time(connection.arrival))")
                            .font(type.time)
                        if connection.delayMinutes > 0 {
                            Text("Delay: +\(connection.delayMinutes) min").font(type.meta)
                        }
                    } else {
                        Text("Explore public transport connections from Winterthur.").font(type.body)
                    }
                    if let start = plan.start {
                        Text("In Google Maps, set “Arrive by” to \(Self.day(start)) \(Self.time(start)). Allow time from the station to the venue.")
                            .font(type.body).foregroundStyle(Theme.textMuted)
                    } else {
                        Text("Check this date and time in Google Maps and allow time from the station to the venue.")
                            .font(type.body).foregroundStyle(Theme.textMuted)
                    }
                    Link("Open Google Maps", destination: plan.mapsURL)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(Theme.surfaceCard)
            .navigationTitle("Travel to event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private static func time(_ date: Date) -> String { format(date, "HH:mm") }
    private static func day(_ date: Date) -> String { format(date, "EEE d MMM") }
    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
