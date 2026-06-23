import Foundation

struct LSOFRow: Hashable, Sendable {
    let command: String
    let pid: Int
    let user: String
    let name: String
    let listener: PortListener
}

enum ServiceParsers {
    static func parseLSOF(_ output: String) -> [LSOFRow] {
        output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line in
                let parts = line.split(maxSplits: 8, whereSeparator: \.isWhitespace).map(String.init)
                guard parts.count >= 9, let pid = Int(parts[1]) else { return nil }
                guard let listener = parseListenerName(parts[8]) else { return nil }
                return LSOFRow(command: parts[0], pid: pid, user: parts[2], name: parts[8], listener: listener)
            }
    }

    static func parsePS(_ output: String) -> [Int: ProcessInfoSnapshot] {
        var snapshots: [Int: ProcessInfoSnapshot] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            if let snapshot = parseEnrichedProcessLine(String(line)) ?? parseLegacyProcessLine(String(line)) {
                snapshots[snapshot.pid] = snapshot
            }
        }
        return snapshots
    }

    private static func parseEnrichedProcessLine(_ line: String) -> ProcessInfoSnapshot? {
        let parts = line.split(maxSplits: 11, whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 12,
              let pid = Int(parts[0]),
              let parentPID = Int(parts[1]),
              let rssKilobytes = Int(parts[9])
        else { return nil }

        let status = parts[3]
        let dateString = "\(parts[4]) \(parts[5]) \(parts[6]) \(parts[7]) \(parts[8])"
        let cpuPercent = Double(parts[10])
        return ProcessInfoSnapshot(
            pid: pid,
            parentPID: parentPID,
            user: parts[2],
            status: status,
            startDate: DateFormatters.processStart.date(from: dateString),
            command: parts[11],
            cwd: nil,
            resourceUsage: ResourceUsage.fromPS(
                cpuPercent: cpuPercent,
                residentMemoryKilobytes: rssKilobytes,
                status: status
            )
        )
    }

    private static func parseLegacyProcessLine(_ line: String) -> ProcessInfoSnapshot? {
        let parts = line.split(maxSplits: 9, whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 10,
              let pid = Int(parts[0]),
              let parentPID = Int(parts[1])
        else { return nil }

        let status = parts[3]
        let dateString = "\(parts[4]) \(parts[5]) \(parts[6]) \(parts[7]) \(parts[8])"
        return ProcessInfoSnapshot(
            pid: pid,
            parentPID: parentPID,
            user: parts[2],
            status: status,
            startDate: DateFormatters.processStart.date(from: dateString),
            command: parts[9],
            cwd: nil,
            resourceUsage: .unavailable
        )
    }

    static func parseCWD(_ output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line -> String? in
                let parts = line.split(maxSplits: 8, whereSeparator: \.isWhitespace).map(String.init)
                guard parts.count >= 9, parts[3] == "cwd" else { return nil }
                return parts[8]
            }
            .first
    }

    static func parseDockerPS(_ output: String) -> [DockerContainerSnapshot] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 4, !parts[0].isEmpty else { return nil }
                return DockerContainerSnapshot(id: parts[0], name: parts[1], ports: parts[2], status: parts[3])
            }
    }

    static func parseOllamaPS(_ output: String) -> [OllamaModelSnapshot] {
        output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line in
                let parts = line.split(maxSplits: 4, whereSeparator: \.isWhitespace).map(String.init)
                guard parts.count >= 5 else { return nil }
                return OllamaModelSnapshot(name: parts[0], id: parts[1], size: parts[2], processor: parts[3], until: parts[4])
            }
    }

    static func parseListenerName(_ name: String) -> PortListener? {
        let cleanedName = name.split(separator: " ", maxSplits: 1).first.map(String.init) ?? name
        guard let separator = cleanedName.lastIndex(of: ":") else { return nil }
        var portText = String(cleanedName[cleanedName.index(after: separator)...])
        if let arrow = portText.firstIndex(of: "-") {
            portText = String(portText[..<arrow])
        }
        guard let port = Int(portText) else { return nil }
        let address = String(cleanedName[..<separator])
        return PortListener(address: address, port: port, rawName: cleanedName)
    }
}
