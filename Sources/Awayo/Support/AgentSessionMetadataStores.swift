import Foundation

struct ClaudeCodeSessionMetadata {
    let title: String?
    let cwd: String?
    let originCwd: String?
    let worktreePath: String?
    let worktreeName: String?
    let lastActivityAt: TimeInterval?

    var workspaceName: String? {
        cleanDisplayText(worktreeName, maxLength: 34)
            ?? displayName(forPath: worktreePath)
            ?? displayName(forPath: cwd)
            ?? displayName(forPath: originCwd)
    }
}

struct ClaudeCodeSessionMetadataIndex {
    let byCliSessionID: [String: ClaudeCodeSessionMetadata]
    let byWorkspacePath: [String: ClaudeCodeSessionMetadata]
}

struct ClaudeCodeSessionMetadataStore {
    func loadIndex() -> ClaudeCodeSessionMetadataIndex {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ClaudeCodeSessionMetadataIndex(byCliSessionID: [:], byWorkspacePath: [:])
        }

        var records: [String: ClaudeCodeSessionMetadata] = [:]
        var pathRecords: [String: ClaudeCodeSessionMetadata] = [:]
        let recentCutoff = Date().addingTimeInterval(-60 * 60 * 24 * 14)

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "json" else {
                continue
            }

            if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
               values.isRegularFile != true || (values.contentModificationDate ?? .distantPast) < recentCutoff {
                continue
            }

            guard let data = try? Data(contentsOf: fileURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cliSessionID = object["cliSessionId"] as? String
            else {
                continue
            }

            let metadata = ClaudeCodeSessionMetadata(
                title: cleanDisplayText(object["title"] as? String, maxLength: 48),
                cwd: object["cwd"] as? String,
                originCwd: object["originCwd"] as? String,
                worktreePath: object["worktreePath"] as? String,
                worktreeName: object["worktreeName"] as? String,
                lastActivityAt: (object["lastActivityAt"] as? Double).map { $0 / 1000 }
            )

            if let existing = records[cliSessionID],
               (existing.lastActivityAt ?? 0) > (metadata.lastActivityAt ?? 0) {
                continue
            }

            records[cliSessionID] = metadata

            for path in [metadata.cwd, metadata.worktreePath].compactMap({ $0 }) {
                if let existing = pathRecords[path],
                   (existing.lastActivityAt ?? 0) > (metadata.lastActivityAt ?? 0) {
                    continue
                }
                pathRecords[path] = metadata
            }
        }

        return ClaudeCodeSessionMetadataIndex(byCliSessionID: records, byWorkspacePath: pathRecords)
    }
}

struct CodexSessionMetadataStore {
    private struct IndexRecord: Decodable {
        let id: String
        let threadName: String
        let updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
            case updatedAt = "updated_at"
        }
    }

    private struct ThreadRecord {
        let id: String
        let cwd: String?
        let openChildCount: Int
    }

    func loadRecentSessions(maxCount: Int) -> [AgentSession] {
        let indexRecords = loadIndexRecords()
        guard !indexRecords.isEmpty else {
            return []
        }

        let titleByID = Dictionary(uniqueKeysWithValues: indexRecords.map { ($0.id, $0.threadName) })
        let threadByID = Dictionary(uniqueKeysWithValues: loadThreadRecords().map { ($0.id, $0) })
        let activityByID = loadRecentActivity()
        let sortedIDs = orderedThreadIDs(indexRecords: indexRecords, activityByID: activityByID)

        return sortedIDs.compactMap { id -> AgentSession? in
            guard let title = cleanDisplayText(titleByID[id], maxLength: 48) else {
                return nil
            }

            let workspace = displayName(forPath: threadByID[id]?.cwd)
            let openChildCount = threadByID[id]?.openChildCount ?? 0
            let childSummary = openChildCount > 0 ? "\(openChildCount) open helper\(openChildCount == 1 ? "" : "s")" : nil
            let detail = [title, workspace, childSummary].compactMap { $0 }.joined(separator: " - ")
            let lastActivity = activityByID[id] ?? indexRecords.first(where: { $0.id == id })?.updatedAt?.timeIntervalSince1970
            let state = stateForCodexActivity(lastActivity)
            return AgentSession(name: "Codex", detail: detail, state: state)
        }
        .prefix(maxCount)
        .map { $0 }
    }

    private func orderedThreadIDs(indexRecords: [IndexRecord], activityByID: [String: TimeInterval]) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []

        for id in activityByID
            .sorted(by: { $0.value > $1.value })
            .map(\.key)
        where seen.insert(id).inserted {
            ids.append(id)
        }

        for record in indexRecords
            .sorted(by: { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) })
        where seen.insert(record.id).inserted {
            ids.append(record.id)
        }

        return ids
    }

    private func loadIndexRecords() -> [IndexRecord] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = iso8601Date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? decoder.decode(IndexRecord.self, from: Data(String(line).utf8))
            }
    }

    private func loadThreadRecords() -> [ThreadRecord] {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
            .path
        guard FileManager.default.fileExists(atPath: database) else {
            return []
        }

        let openChildCounts = loadOpenChildCounts(database: database)
        let query = "select id,cwd from threads order by updated_at desc limit 40;"
        let output = run("/usr/bin/sqlite3", arguments: ["-separator", "\t", database, query])
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard let id = parts.first.map(String.init), !id.isEmpty else {
                    return nil
                }

                let cwd = parts.count > 1 ? String(parts[1]) : nil
                return ThreadRecord(id: id, cwd: cwd, openChildCount: openChildCounts[id] ?? 0)
            }
    }

    private func loadOpenChildCounts(database: String) -> [String: Int] {
        let query = """
        select parent_thread_id,count(*) from thread_spawn_edges
        where status = 'open'
        group by parent_thread_id;
        """
        let output = run("/usr/bin/sqlite3", arguments: ["-separator", "\t", database, query])
        return Dictionary(uniqueKeysWithValues: output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> (String, Int)? in
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, let count = Int(parts[1]) else {
                    return nil
                }
                return (String(parts[0]), count)
            })
    }

    private func loadRecentActivity() -> [String: TimeInterval] {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/logs_2.sqlite")
            .path
        guard FileManager.default.fileExists(atPath: database) else {
            return [:]
        }

        let query = """
        select thread_id,max(ts) from logs
        where thread_id is not null
        group by thread_id
        order by max(ts) desc
        limit 24;
        """
        let output = run("/usr/bin/sqlite3", arguments: ["-separator", "\t", database, query])
        return Dictionary(uniqueKeysWithValues: output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> (String, TimeInterval)? in
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2,
                      let timestamp = TimeInterval(parts[1])
                else {
                    return nil
                }
                return (String(parts[0]), timestamp)
            })
    }

    private func stateForCodexActivity(_ timestamp: TimeInterval?) -> AgentSession.State {
        guard let timestamp else {
            return .alive
        }

        let age = Date().timeIntervalSince1970 - timestamp
        if age < 120 {
            return .working
        }
        if age < 60 * 60 * 2 {
            return .alive
        }
        return .quiet
    }
}

private func iso8601Date(from value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
        return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private func cleanDisplayText(_ value: String?, maxLength: Int) -> String? {
    guard let value else {
        return nil
    }

    let collapsed = value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
        .split(separator: " ", omittingEmptySubsequences: true)
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !collapsed.isEmpty else {
        return nil
    }

    return String(collapsed.prefix(maxLength))
}

private func displayName(forPath path: String?) -> String? {
    guard let path, !path.isEmpty else {
        return nil
    }

    let ignoredPrefixes = [
        "/",
        "/Applications",
        "/System",
        "/Library"
    ]

    if ignoredPrefixes.contains(path) || path.contains("/Library/Application Support/") {
        return nil
    }

    let components = path
        .split(separator: "/")
        .map(String.init)

    if let worktreeIndex = components.lastIndex(of: "worktrees"),
       components.indices.contains(worktreeIndex + 1) {
        return cleanDisplayText(components[worktreeIndex + 1], maxLength: 34)
    }

    return cleanDisplayText(components.last, maxLength: 34)
}

private func run(_ launchPath: String, arguments: [String]) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ""
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
