import Foundation

final class AgentSessionHookStore: Sendable {
    private struct HookRecord: Codable {
        let id: String
        let name: String
        let detail: String
        let state: AgentSession.State
        let updatedAt: TimeInterval
        let expiresAfter: TimeInterval?
    }

    func loadFreshSessions(now: Date = Date()) -> [AgentSession] {
        let records = loadRecords()
        let nowInterval = now.timeIntervalSince1970

        return records
            .filter { record in
                let freshnessWindow = max(30, record.expiresAfter ?? 600)
                return nowInterval - record.updatedAt <= freshnessWindow
            }
            .compactMap { record in
                guard let name = sanitize(record.name),
                      let detail = sanitize(record.detail)
                else {
                    return nil
                }

                return AgentSession(name: name, detail: detail, state: record.state)
            }
    }

    private func loadRecords() -> [HookRecord] {
        let url = Self.fileURL
        guard let data = try? Data(contentsOf: url) else {
            return []
        }

        return (try? JSONDecoder().decode([HookRecord].self, from: data)) ?? []
    }

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Awayo", isDirectory: true)
            .appendingPathComponent("agent-sessions.json")
    }

    private func sanitize(_ value: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- /:#[]()"))
        let cleaned = String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        })
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return nil
        }

        return String(cleaned.prefix(72))
    }
}
