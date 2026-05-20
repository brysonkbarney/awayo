import Foundation

final class AgentSessionDetector: Sendable {
    private struct ProcessRow {
        let pid: Int
        let cpu: Double
        let command: String
    }

    func detect() -> [AgentSession] {
        var sessions = AgentSessionHookStore().loadFreshSessions()
        var seen = Set<String>()
        sessions.forEach { session in
            seen.insert("\(session.name)|\(session.detail)")
        }

        let rows = processRows()
        let claudeMetadata = ClaudeCodeSessionMetadataStore().loadIndex()
        let codexMetadataSessions = codexIsRunning(in: rows)
            ? CodexSessionMetadataStore().loadRecentSessions(maxCount: 3)
            : []
        let includeCodexFallback = codexMetadataSessions.isEmpty

        let detectedSessions = rows.compactMap { row in
            agentSession(
                for: row,
                claudeMetadata: claudeMetadata,
                includeCodexFallback: includeCodexFallback
            )
        } + codexMetadataSessions

        for session in detectedSessions {
            let key = "\(session.name)|\(session.detail)"
            if seen.insert(key).inserted {
                sessions.append(session)
            }
        }

        return sessions.sorted {
            if $0.name == $1.name {
                return $0.detail < $1.detail
            }
            return $0.name < $1.name
        }
    }

    private func agentSession(
        for row: ProcessRow,
        claudeMetadata: ClaudeCodeSessionMetadataIndex,
        includeCodexFallback: Bool
    ) -> AgentSession? {
        let command = row.command

        if isClaudeCode(command) {
            let sessionID = fullResumeID(from: command)
            let processCwd = cwdPath(for: row.pid)
            let metadata = sessionID.flatMap { claudeMetadata.byCliSessionID[$0] }
                ?? processCwd.flatMap { claudeMetadata.byWorkspacePath[$0] }
            return AgentSession(
                name: "Claude Code",
                detail: claudeDetail(for: metadata, row: row),
                state: state(for: row)
            )
        }

        if isClaudeDesktop(command) {
            return AgentSession(name: "Claude", detail: "desktop app open", state: state(for: row))
        }

        if isCodexDesktop(command) {
            return includeCodexFallback ? AgentSession(name: "Codex", detail: "desktop session", state: state(for: row)) : nil
        }

        if isCodexCli(command) {
            return AgentSession(
                name: "Codex",
                detail: sessionDetail(for: row, fallback: "terminal session"),
                state: state(for: row)
            )
        }

        if let cliName = cliAgentName(for: command) {
            return AgentSession(
                name: cliName,
                detail: sessionDetail(for: row, fallback: "terminal session"),
                state: state(for: row)
            )
        }

        return nil
    }

    private func state(for row: ProcessRow) -> AgentSession.State {
        row.cpu >= 1.0 ? .working : .quiet
    }

    private func isClaudeCode(_ command: String) -> Bool {
        if command.contains("/Contents/Helpers/disclaimer ") {
            return false
        }

        return (command.contains("/claude-code/") && command.contains("/Contents/MacOS/claude"))
            || command.contains("/local-agent-mode-sessions/")
    }

    private func isClaudeDesktop(_ command: String) -> Bool {
        command.contains("/Claude.app/Contents/MacOS/Claude")
    }

    private func isCodexDesktop(_ command: String) -> Bool {
        command.contains("/Codex.app/Contents/MacOS/Codex")
            || command.contains("/Codex.app/Contents/Resources/codex app-server")
    }

    private func codexIsRunning(in rows: [ProcessRow]) -> Bool {
        rows.contains { row in
            isCodexDesktop(row.command) || isCodexCli(row.command)
        }
    }

    private func isCodexCli(_ command: String) -> Bool {
        guard command.contains("codex") else {
            return false
        }

        let skippedFragments = [
            "/Codex.app/",
            " app-server",
            "node_repl",
            "SkyComputerUseClient",
            "rg -i",
            "AgentSessionDetector"
        ]

        return !skippedFragments.contains { command.contains($0) }
    }

    private func cliAgentName(for command: String) -> String? {
        let lowercased = command.lowercased()
        let patterns: [(String, String)] = [
            ("opencode", "OpenCode"),
            ("aider", "Aider"),
            ("gemini", "Gemini"),
            ("goose", "Goose")
        ]

        return patterns.first { pattern, _ in
            lowercased.contains(pattern)
        }?.1
    }

    private func claudeDetail(for metadata: ClaudeCodeSessionMetadata?, row: ProcessRow) -> String {
        let title = metadata?.title
        let workspace = metadata?.workspaceName

        switch (title, workspace) {
        case let (title?, workspace?) where title != workspace:
            return "\(title) - \(workspace)"
        case let (title?, _):
            return title
        case let (nil, workspace?):
            return workspace
        case (nil, nil):
            return sessionDetail(for: row, fallback: "active session")
        }
    }

    private func sessionDetail(for row: ProcessRow, fallback: String) -> String {
        let workspace = workspaceName(from: row.command)
            ?? cwdPath(for: row.pid).flatMap(displayName)
        let sessionID = resumeID(from: row.command)

        switch (workspace, sessionID) {
        case let (workspace?, sessionID?):
            return "\(workspace) - \(sessionID)"
        case let (workspace?, nil):
            return workspace
        case let (nil, sessionID?):
            return "session \(sessionID)"
        case (nil, nil):
            return fallback
        }
    }

    private func processRows() -> [ProcessRow] {
        let output = run("/bin/ps", arguments: ["-axww", "-o", "pid=,pcpu=,command="])
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let pidIndex = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                    return nil
                }

                let pidText = String(trimmed[..<pidIndex])
                let remainder = trimmed[pidIndex...].trimmingCharacters(in: .whitespaces)
                guard let cpuIndex = remainder.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                    return nil
                }

                let cpuText = String(remainder[..<cpuIndex])
                let command = remainder[cpuIndex...].trimmingCharacters(in: .whitespaces)
                guard let pid = Int(pidText), let cpu = Double(cpuText), !command.isEmpty else {
                    return nil
                }

                return ProcessRow(pid: pid, cpu: cpu, command: command)
            }
    }

    private func cwdPath(for pid: Int) -> String? {
        let output = run("/usr/sbin/lsof", arguments: ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"])
        guard let pathLine = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first(where: { $0.hasPrefix("n/") || $0.hasPrefix("n~") })
        else {
            return nil
        }

        return String(pathLine.dropFirst())
    }

    private func workspaceName(from command: String) -> String? {
        let prefixes = [
            "--workspace_directory=",
            "--cwd=",
            "--worktree="
        ]

        for prefix in prefixes {
            guard let range = command.range(of: prefix) else {
                continue
            }

            let valueStart = range.upperBound
            let suffix = command[valueStart...]
            let rawValue = suffix.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init)
            if let rawValue, let name = displayName(forPath: rawValue) {
                return name
            }
        }

        return nil
    }

    private func fullResumeID(from command: String) -> String? {
        let tokens = command.split(separator: " ").map(String.init)

        for (index, token) in tokens.enumerated() {
            if token == "--resume", index + 1 < tokens.count {
                return cleanID(tokens[index + 1])
            }

            if token.hasPrefix("--resume=") {
                return cleanID(String(token.dropFirst("--resume=".count)))
            }
        }

        return nil
    }

    private func resumeID(from command: String) -> String? {
        fullResumeID(from: command).map { String($0.prefix(8)) }
    }

    private func cleanID(_ value: String) -> String? {
        let cleaned = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        guard !cleaned.isEmpty else {
            return nil
        }

        return cleaned
    }

    private func displayName(forPath path: String) -> String? {
        let ignoredPrefixes = [
            "/",
            "/Applications",
            "/System",
            "/Library"
        ]

        if ignoredPrefixes.contains(path) {
            return nil
        }

        if path.contains("/Library/Application Support/") {
            return nil
        }

        let components = path
            .split(separator: "/")
            .map(String.init)

        if let worktreeIndex = components.lastIndex(of: "worktrees"),
           components.indices.contains(worktreeIndex + 1) {
            return sanitize(components[worktreeIndex + 1])
        }

        guard let last = components.last else {
            return nil
        }

        return sanitize(last)
    }

    private func sanitize(_ value: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- "))
        let cleaned = String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        })
        .trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))

        guard !cleaned.isEmpty else {
            return nil
        }

        return String(cleaned.prefix(34))
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
}
