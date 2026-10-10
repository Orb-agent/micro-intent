import Foundation

// MARK: - Card Kinds & Enums

public enum CardKind: String, Codable, CaseIterable, Sendable {
    case train
    case conflict
    case event
    case flight
}

public enum ConflictVerdict: String, Codable, Sendable {
    case fits
    case tight
    case clash
}

public enum EventSource: String, Codable, Sendable {
    case calendar
    case luma
}

// MARK: - Date Parser Helper

public enum CardDateParser {
    public static let zurichTimeZone: TimeZone = TimeZone(identifier: "Europe/Zurich") ?? TimeZone(secondsFromGMT: 7200) ?? .current

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = zurichTimeZone
        return f
    }()

    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = zurichTimeZone
        return f
    }()

    private static let isoFormatterDateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = zurichTimeZone
        return f
    }()

    public static func parse(_ string: String) -> Date? {
        if let date = isoFormatterStandard.date(from: string) { return date }
        if let date = isoFormatterFractional.date(from: string) { return date }
        if let date = isoFormatterDateOnly.date(from: string) { return date }
        return nil
    }

    public static func formatISO(_ date: Date) -> String {
        isoFormatterStandard.string(from: date)
    }
}

// MARK: - Train Card

public struct TrainCard: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String { "\(line)-\(from)-\(to)-\(departure.timeIntervalSince1970)" }
    public let kind: CardKind
    public let line: String
    public let from: String
    public let to: String
    public let departure: Date
    public let arrival: Date
    public let platform: String?
    public let transfers: Int
    public let delayMin: Int?

    public init(
        line: String,
        from: String,
        to: String,
        departure: Date,
        arrival: Date,
        platform: String? = nil,
        transfers: Int = 0,
        delayMin: Int? = nil
    ) {
        self.kind = .train
        self.line = line
        self.from = from
        self.to = to
        self.departure = departure
        self.arrival = arrival
        self.platform = platform
        self.transfers = transfers
        self.delayMin = delayMin
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case line
        case from
        case to
        case departure
        case arrival
        case platform
        case transfers
        case delayMin
        case delay_min
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(CardKind.self, forKey: .kind) ?? .train
        self.line = try container.decode(String.self, forKey: .line)
        self.from = try container.decode(String.self, forKey: .from)
        self.to = try container.decode(String.self, forKey: .to)

        if let date = try? container.decode(Date.self, forKey: .departure) {
            self.departure = date
        } else {
            let str = try container.decode(String.self, forKey: .departure)
            guard let date = CardDateParser.parse(str) else {
                throw DecodingError.dataCorruptedError(forKey: .departure, in: container, debugDescription: "Invalid ISO date: \(str)")
            }
            self.departure = date
        }

        if let date = try? container.decode(Date.self, forKey: .arrival) {
            self.arrival = date
        } else {
            let str = try container.decode(String.self, forKey: .arrival)
            guard let date = CardDateParser.parse(str) else {
                throw DecodingError.dataCorruptedError(forKey: .arrival, in: container, debugDescription: "Invalid ISO date: \(str)")
            }
            self.arrival = date
        }

        self.platform = try container.decodeIfPresent(String.self, forKey: .platform)
        self.transfers = try container.decodeIfPresent(Int.self, forKey: .transfers) ?? 0
        self.delayMin = (try? container.decodeIfPresent(Int.self, forKey: .delayMin)) ?? (try? container.decodeIfPresent(Int.self, forKey: .delay_min)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(line, forKey: .line)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(departure, forKey: .departure)
        try container.encode(arrival, forKey: .arrival)
        try container.encodeIfPresent(platform, forKey: .platform)
        try container.encode(transfers, forKey: .transfers)
        try container.encodeIfPresent(delayMin, forKey: .delayMin)
    }
}

// MARK: - Conflict Card

public struct ConflictEvent: Codable, Equatable, Hashable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date

    public init(title: String, start: Date, end: Date) {
        self.title = title
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey {
        case title, start, end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)

        if let date = try? container.decode(Date.self, forKey: .start) {
            self.start = date
        } else {
            let str = try container.decode(String.self, forKey: .start)
            guard let date = CardDateParser.parse(str) else {
                throw DecodingError.dataCorruptedError(forKey: .start, in: container, debugDescription: "Invalid ISO date: \(str)")
            }
            self.start = date
        }

        if let date = try? container.decode(Date.self, forKey: .end) {
            self.end = date
        } else {
            let str = try container.decode(String.self, forKey: .end)
            guard let date = CardDateParser.parse(str) else {
                throw DecodingError.dataCorruptedError(forKey: .end, in: container, debugDescription: "Invalid ISO date: \(str)")
            }
            self.end = date
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
    }
}

public struct ConflictProposal: Codable, Equatable, Hashable, Sendable {
    public let title: String
    public let start: Date
    public let place: String?

    public init(title: String, start: Date, place: String? = nil) {
        self.title = title
        self.start = start
        self.place = place
    }

    enum CodingKeys: String, CodingKey {
        case title, start, place
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)

        if let date = try? container.decode(Date.self, forKey: .start) {
            self.start = date
        } else {
            let str = try container.decode(String.self, forKey: .start)
            guard let date = CardDateParser.parse(str) else {
                throw DecodingError.dataCorruptedError(forKey: .start, in: container, debugDescription: "Invalid ISO date: \(str)")
            }
            self.start = date
        }

        self.place = try container.decodeIfPresent(String.self, forKey: .place)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(start, forKey: .start)
        try container.encodeIfPresent(place, forKey: .place)
    }
}

public struct ConflictCard: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String { "\(event.title)-\(proposal.title)-\(verdict.rawValue)" }
    public let kind: CardKind
    public let event: ConflictEvent
    public let proposal: ConflictProposal
    public let verdict: ConflictVerdict
    public let note: String?

    public init(
        event: ConflictEvent,
        proposal: ConflictProposal,
        verdict: ConflictVerdict,
        note: String? = nil
    ) {
        self.kind = .conflict
        self.event = event
        self.proposal = proposal
        self.verdict = verdict
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case kind, event, proposal, verdict, note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(CardKind.self, forKey: .kind) ?? .conflict
        self.event = try container.decode(ConflictEvent.self, forKey: .event)
        self.proposal = try container.decode(ConflictProposal.self, forKey: .proposal)
        self.verdict = try container.decode(ConflictVerdict.self, forKey: .verdict)
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(event, forKey: .event)
        try container.encode(proposal, forKey: .proposal)
        try container.encode(verdict, forKey: .verdict)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

// MARK: - Event Card

public struct EventCard: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String { "\(title)-\(start.timeIntervalSince1970)-\(source.rawValue)" }
    public let kind: CardKind
    public let title: String
    public let start: Date
    public let end: Date
    public let location: String?
    public let source: EventSource

    public init(
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        source: EventSource
    ) {
        self.kind = .event
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case kind, title, start, end, location, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(CardKind.self, forKey: .kind) ?? .event
        self.title = try container.decode(String.self, forKey: .title)

        if let date = try? container.decode(Date.self, forKey: .start) {
            self.start = date
        } else {
            let str = try container.decode(String.self, forKey: .start)
            guard let date = CardDateParser.parse(str) else {
                throw DecodingError.dataCorruptedError(forKey: .start, in: container, debugDescription: "Invalid ISO date: \(str)")
            }
            self.start = date
        }

        if let date = try? container.decode(Date.self, forKey: .end) {
            self.end = date
        } else {
            let str = try container.decode(String.self, forKey: .end)
            guard let date = CardDateParser.parse(str) else {
                throw DecodingError.dataCorruptedError(forKey: .end, in: container, debugDescription: "Invalid ISO date: \(str)")
            }
            self.end = date
        }

        self.location = try container.decodeIfPresent(String.self, forKey: .location)
        self.source = try container.decode(EventSource.self, forKey: .source)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(source, forKey: .source)
    }
}

// MARK: - Flight Card

public struct FlightCard: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String { "\(flightNumber)-\(from)-\(to)-\(departure.timeIntervalSince1970)" }
    public let kind: CardKind
    public let flightNumber: String
    public let from: String
    public let to: String
    public let departure: Date
    public let arrival: Date
    public let bookingRef: String?

    public init(
        flightNumber: String,
        from: String,
        to: String,
        departure: Date,
        arrival: Date,
        bookingRef: String? = nil
    ) {
        self.kind = .flight
        self.flightNumber = flightNumber
        self.from = from
        self.to = to
        self.departure = departure
        self.arrival = arrival
        self.bookingRef = bookingRef
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case flightNumber
        case flight_number
        case from
        case to
        case departure
        case arrival
        case bookingRef
        case booking_ref
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(CardKind.self, forKey: .kind) ?? .flight

        if let fn = try? container.decodeIfPresent(String.self, forKey: .flightNumber) {
            self.flightNumber = fn
        } else if let fn = try? container.decodeIfPresent(String.self, forKey: .flight_number) {
            self.flightNumber = fn
        } else {
            self.flightNumber = try container.decode(String.self, forKey: .flightNumber)
        }

        self.from = try container.decode(String.self, forKey: .from)
        self.to = try container.decode(String.self, forKey: .to)

        if let date = try? container.decode(Date.self, forKey: .departure) {
            self.departure = date
        } else {
            let str = try container.decode(String.self, forKey: .departure)
            guard let date = CardDateParser.parse(str) else {
                throw DecodingError.dataCorruptedError(forKey: .departure, in: container, debugDescription: "Invalid ISO date: \(str)")
            }
            self.departure = date
        }

        if let date = try? container.decode(Date.self, forKey: .arrival) {
            self.arrival = date
        } else {
            let str = try container.decode(String.self, forKey: .arrival)
            guard let date = CardDateParser.parse(str) else {
                throw DecodingError.dataCorruptedError(forKey: .arrival, in: container, debugDescription: "Invalid ISO date: \(str)")
            }
            self.arrival = date
        }

        self.bookingRef = (try? container.decodeIfPresent(String.self, forKey: .bookingRef)) ?? (try? container.decodeIfPresent(String.self, forKey: .booking_ref)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(flightNumber, forKey: .flightNumber)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(departure, forKey: .departure)
        try container.encode(arrival, forKey: .arrival)
        try container.encodeIfPresent(bookingRef, forKey: .bookingRef)
    }
}

// MARK: - Unified Card Enum

public enum Card: Codable, Identifiable, Equatable, Hashable, Sendable {
    case train(TrainCard)
    case conflict(ConflictCard)
    case event(EventCard)
    case flight(FlightCard)

    public var id: String {
        switch self {
        case .train(let c): return "train-\(c.id)"
        case .conflict(let c): return "conflict-\(c.id)"
        case .event(let c): return "event-\(c.id)"
        case .flight(let c): return "flight-\(c.id)"
        }
    }

    public var kind: CardKind {
        switch self {
        case .train: return .train
        case .conflict: return .conflict
        case .event: return .event
        case .flight: return .flight
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(CardKind.self, forKey: .kind)
        switch kind {
        case .train:
            self = .train(try TrainCard(from: decoder))
        case .conflict:
            self = .conflict(try ConflictCard(from: decoder))
        case .event:
            self = .event(try EventCard(from: decoder))
        case .flight:
            self = .flight(try FlightCard(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .train(let card):
            try card.encode(to: encoder)
        case .conflict(let card):
            try card.encode(to: encoder)
        case .event(let card):
            try card.encode(to: encoder)
        case .flight(let card):
            try card.encode(to: encoder)
        }
    }
}

// MARK: - Reply Container

public struct Reply: Codable, Equatable, Sendable {
    public let say: String
    public let cards: [Card]

    public init(say: String, cards: [Card]) {
        self.say = say
        self.cards = cards
    }
}

// MARK: - Sample Data for Previews and Tests

extension Card {
    public static var sampleTrain: TrainCard {
        TrainCard(
            line: "IC 8",
            from: "Zürich HB",
            to: "Bern",
            departure: CardDateParser.parse("2026-10-15T18:01:00+02:00") ?? Date(),
            arrival: CardDateParser.parse("2026-10-15T18:58:00+02:00") ?? Date().addingTimeInterval(3420),
            platform: "31",
            transfers: 0,
            delayMin: 0
        )
    }

    public static var sampleConflict: ConflictCard {
        ConflictCard(
            event: ConflictEvent(
                title: "Call with Acme",
                start: CardDateParser.parse("2026-10-15T17:30:00+02:00") ?? Date(),
                end: CardDateParser.parse("2026-10-15T17:45:00+02:00") ?? Date().addingTimeInterval(900)
            ),
            proposal: ConflictProposal(
                title: "Dinner in Bern",
                start: CardDateParser.parse("2026-10-15T19:00:00+02:00") ?? Date().addingTimeInterval(5400),
                place: "Bern"
            ),
            verdict: .fits,
            note: "Leave right after the call"
        )
    }

    public static var sampleEvent: EventCard {
        EventCard(
            title: "Hackathon",
            start: CardDateParser.parse("2026-10-17T09:00:00+02:00") ?? Date(),
            end: CardDateParser.parse("2026-10-18T18:00:00+02:00") ?? Date().addingTimeInterval(118800),
            location: "Zürich",
            source: .luma
        )
    }

    public static var sampleFlight: FlightCard {
        FlightCard(
            flightNumber: "LX 1820",
            from: "ZRH",
            to: "LIS",
            departure: CardDateParser.parse("2026-10-20T07:10:00+02:00") ?? Date(),
            arrival: CardDateParser.parse("2026-10-20T09:15:00+01:00") ?? Date().addingTimeInterval(7500),
            bookingRef: "K7Q2ZP"
        )
    }

    public static var demoCards: [Card] {
        [
            .conflict(sampleConflict),
            .train(sampleTrain)
        ]
    }

    public static var fixtureCards: [Card] {
        [
            .event(sampleEvent),
            .flight(sampleFlight)
        ]
    }

    public static var allSamples: [Card] {
        [
            .conflict(sampleConflict),
            .train(sampleTrain),
            .event(sampleEvent),
            .flight(sampleFlight)
        ]
    }
}
