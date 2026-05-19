#!/usr/bin/env swift

import Foundation

struct HookRecord: Codable {
    var id: String
    var name: String
    var detail: String
    var state: String
    var updatedAt: TimeInterval
    var expiresAfter: TimeInterval?
}

let validStates: [String: String] = [
    "working": "working",
    "work": "working",
    "ready": "ready_for_input",
    "ready_for_input": "ready_for_input",
    "input": "ready_for_input",
    "needs_input": "ready_for_input",
    "needs-you": "ready_for_input",
    "waiting": "waiting",
    "wait": "waiting",
    "quiet": "quiet",
    "alive": "alive"
]

func statusFileURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return base
        .appendingPathComponent("Awayo", isDirectory: true)
        .appendingPathComponent("agent-sessions.json")
}

func loadRecords(from url: URL) -> [HookRecord] {
    guard let data = try? Data(contentsOf: url) else {
        return []
    }

    return (try? JSONDecoder().decode([HookRecord].self, from: data)) ?? []
}

func saveRecords(_ records: [HookRecord], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(records)
    try data.write(to: url, options: .atomic)
}

func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
    }

    return arguments[index + 1]
}

func normalizedState(_ rawValue: String?) -> String {
    guard let rawValue else {
        return "alive"
    }

    return validStates[rawValue.lowercased()] ?? "alive"
}

func usage() {
    print("""
    Usage:
      swift Scripts/awayo_agent_status.swift upsert --id ID --name NAME --detail DETAIL --state working|ready|waiting|quiet|alive [--ttl seconds]
      swift Scripts/awayo_agent_status.swift clear --id ID
      swift Scripts/awayo_agent_status.swift list

    Example:
      swift Scripts/awayo_agent_status.swift upsert --id codex-awayo --name Codex --detail "Awayo lock polish" --state working
      swift Scripts/awayo_agent_status.swift upsert --id codex-awayo --name Codex --detail "Awayo lock polish" --state ready
      swift Scripts/awayo_agent_status.swift clear --id codex-awayo
    """)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    usage()
    exit(1)
}

let url = statusFileURL()
var records = loadRecords(from: url)

switch command {
case "upsert":
    guard let id = value(after: "--id", in: arguments),
          let name = value(after: "--name", in: arguments),
          let detail = value(after: "--detail", in: arguments)
    else {
        usage()
        exit(1)
    }

    let ttl = value(after: "--ttl", in: arguments).flatMap(TimeInterval.init)
    let record = HookRecord(
        id: id,
        name: name,
        detail: detail,
        state: normalizedState(value(after: "--state", in: arguments)),
        updatedAt: Date().timeIntervalSince1970,
        expiresAfter: ttl
    )

    records.removeAll { $0.id == id }
    records.append(record)
    try saveRecords(records, to: url)
    print("updated \(name): \(detail) -> \(record.state)")

case "clear":
    guard let id = value(after: "--id", in: arguments) else {
        usage()
        exit(1)
    }

    records.removeAll { $0.id == id }
    try saveRecords(records, to: url)
    print("cleared \(id)")

case "list":
    guard !records.isEmpty else {
        print("no hooked Awayo agent sessions")
        exit(0)
    }

    records.forEach { record in
        print("\(record.id): \(record.name) - \(record.detail) [\(record.state)]")
    }

default:
    usage()
    exit(1)
}
