import A2UISwiftCore
import Foundation

extension CardPayload {
    private var fields: [String: Any] {
        (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] ?? [:]
    }

    var needsAttention: Bool {
        guard kind == "conflict", let verdict = fields["verdict"] as? String else { return false }
        return verdict == "tight" || verdict == "clash"
    }

    /// Advice can be rephrased without making an acknowledged conflict new again.
    var conflictKey: String {
        let value = fields
        let event = value["event"] as? [String: Any] ?? [:]
        let proposal = value["proposal"] as? [String: Any] ?? [:]
        let identity = [
            value["verdict"] as? String ?? "",
            event["title"] as? String ?? "", event["start"] as? String ?? "", event["end"] as? String ?? "",
            proposal["title"] as? String ?? "", proposal["start"] as? String ?? "", proposal["place"] as? String ?? "",
        ]
        return (try? JSONEncoder().encode(identity))?.base64EncodedString() ?? ""
    }
}

enum ConflictPresentation {
    /// Split the existing single-surface card tree without changing the wire protocol.
    static func messages(_ messages: [A2uiMessage], including indices: Set<Int>) -> [A2uiMessage] {
        guard !indices.isEmpty,
              let data = try? JSONEncoder().encode(messages),
              var objects = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        let cardIDs = Set(indices.map { "c\($0)" })
        for index in objects.indices {
            guard var update = objects[index]["updateComponents"] as? [String: Any],
                  let components = update["components"] as? [[String: Any]] else { continue }
            update["components"] = components.compactMap { component -> [String: Any]? in
                guard let id = component["id"] as? String else { return nil }
                if id == "root" {
                    guard let children = component["children"] as? [String] else { return nil }
                    var root = component
                    root["children"] = children.filter { cardIDs.contains($0) }
                    return root
                }
                return cardIDs.contains(where: { id == $0 || id.hasPrefix("\($0)-") }) ? component : nil
            }
            objects[index]["updateComponents"] = update
        }
        guard let selected = try? JSONSerialization.data(withJSONObject: objects) else { return [] }
        return (try? JSONDecoder().decode([A2uiMessage].self, from: selected)) ?? []
    }
}
