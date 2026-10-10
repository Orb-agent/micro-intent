import Foundation

/// Bundled fixtures (see Fixtures/). Fixture mode replays them as the same JSON frames
/// the server sends, so they go through the exact decoding and rendering path.
enum Fixtures {
    struct Turn {
        let label: String
        let frames: [Data]
    }

    /// The demo question: conflict and train cards (`demo_reply.json`, `demo_a2ui.json`).
    static var demo: Turn {
        Turn(
            label: "Checking trains…",
            frames: [
                frame(type: "reply", merging: object("demo_reply")),
                frame(type: "a2ui", merging: ["messages": array("demo_a2ui")]),
            ]
        )
    }

    /// The other two kinds: event and flight (`cards.json`, `cards_a2ui.json`).
    static var otherKinds: Turn {
        Turn(
            label: "Checking your calendar…",
            frames: [
                frame(type: "reply", merging: [
                    "say": "Next weekend is the hackathon, and on Tuesday you fly to Lisbon.",
                    "cards": array("cards"),
                ]),
                frame(type: "a2ui", merging: ["messages": array("cards_a2ui")]),
            ]
        )
    }

    /// A no-conflict travel rehearsal. These relative times are demo data, not a timetable.
    static var travel: Turn {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "Europe/Zurich")
        func at(_ minutes: Double) -> String { iso.string(from: now.addingTimeInterval(minutes * 60)) }
        return Turn(label: "Checking trains…", frames: [frame(type: "reply", merging: [
            "say": "Demo connection: you have time to get to dinner from Winterthur.",
            "cards": [
                ["kind": "event", "title": "Dinner in Bern", "start": at(180), "end": at(300),
                 "location": "Bern", "source": "calendar"],
                ["kind": "train", "line": "IC 1", "from": "Winterthur", "to": "Bern",
                 "departure": at(120), "arrival": at(165), "transfers": 0],
            ],
        ])])
    }

    /// Picks the fixture turn for a typed question.
    static func turn(for question: String) -> Turn {
        let q = question.lowercased()
        if q.contains("no conflict") || q.contains("sin conflicto") { return travel }
        let other = ["flight", "fly", "event", "week", "calendar", "on today"]
        return other.contains(where: q.contains) ? otherKinds : demo
    }

    static var screenOK: Data {
        frame(type: "screen_ok", merging: ["summary": object("screen")["summary"] ?? NSNull()])
    }

    // MARK: - Loading

    static func data(_ name: String) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("missing fixture \(name).json")
        }
        return data
    }

    private static func object(_ name: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data(name))) as? [String: Any] ?? [:]
    }

    private static func array(_ name: String) -> [Any] {
        (try? JSONSerialization.jsonObject(with: data(name))) as? [Any] ?? []
    }

    private static func frame(type: String, merging fields: [String: Any]) -> Data {
        var object = fields
        object["type"] = type
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
