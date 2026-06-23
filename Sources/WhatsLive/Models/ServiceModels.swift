import Foundation

enum ServiceKind: String, CaseIterable, Sendable {
    case node = "Node"
    case python = "Python"
    case rust = "Rust"
    case model = "Model"
    case docker = "Docker"
    case simulator = "Simulator"
    case database = "Database"
    case system = "System"
    case unknown = "Unknown"

    var symbolName: String {
        switch self {
        case .node: "hexagon"
        case .python: "curlybraces"
        case .rust: "hammer"
        case .model: "cpu"
        case .docker: "shippingbox"
        case .simulator: "iphone"
        case .database: "cylinder.split.1x2"
        case .system: "gearshape"
        case .unknown: "questionmark.circle"
        }
    }

    var compactLabel: String {
        switch self {
        case .node: "Node"
        case .python: "Py"
        case .rust: "Rust"
        case .model: "Model"
        case .docker: "Docker"
        case .simulator: "Sim"
        case .database: "DB"
        case .system: "Sys"
        case .unknown: "Other"
        }
    }

    var summaryPriority: Int {
        switch self {
        case .python: 0
        case .node: 1
        case .rust: 2
        case .model: 3
        case .docker: 4
        case .simulator: 5
        case .unknown: 6
        case .database: 7
        case .system: 8
        }
    }
}

enum SafetyLevel: String, Sendable {
    case safe = "Safe"
    case confirm = "Confirm"
    case protected = "Protected"
}

enum ServiceStatus: String, Sendable {
    case running = "Running"
    case stale = "Stale"
    case protected = "Protected"
    case stopped = "Stopped"
}

struct PortListener: Hashable, Identifiable, Sendable {
    var id: String { "\(address):\(port)" }
    let address: String
    let port: Int
    let rawName: String

    var displayAddress: String {
        if address == "*" || address == "[::]" {
            return "all"
        }
        return address
    }
}

struct ProcessInfoSnapshot: Hashable, Sendable {
    let pid: Int
    let parentPID: Int
    let user: String
    let status: String
    let startDate: Date?
    let command: String
    let cwd: String?
}

struct DockerContainerSnapshot: Hashable, Sendable {
    let id: String
    let name: String
    let ports: String
    let status: String
}

struct OllamaModelSnapshot: Hashable, Sendable {
    let name: String
    let id: String
    let size: String
    let processor: String
    let until: String
}

struct RunningService: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: ServiceKind
    let pid: Int?
    let parentPID: Int?
    let user: String
    let command: String
    let cwd: String?
    let ports: [PortListener]
    let startDate: Date?
    let httpProbe: String?
    let dockerContainerID: String?
    let dockerStatus: String?
    let classificationReason: String
    let staleReasons: [String]
    let safety: SafetyLevel
    var status: ServiceStatus
    var killHistory: [KillEvent]

    var isStale: Bool {
        status == .stale
    }

    var age: TimeInterval? {
        guard let startDate else { return nil }
        return Date().timeIntervalSince(startDate)
    }

    var portSummary: String {
        guard !ports.isEmpty else { return "no port" }
        return ports.map { "\($0.port)" }.sorted().joined(separator: ", ")
    }

    var projectHint: String {
        guard let cwd, !cwd.isEmpty else { return "cwd unavailable" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

struct KillEvent: Hashable, Sendable {
    let date: Date
    let message: String
}

struct ServiceSnapshot: Sendable {
    let services: [RunningService]
    let lastUpdated: Date?
    let isScanning: Bool
    let errorMessage: String?

    static let empty = ServiceSnapshot(
        services: [],
        lastUpdated: nil,
        isScanning: false,
        errorMessage: nil
    )

    var visibleDevServices: [RunningService] {
        services.filter { $0.kind != .system && $0.kind != .database }
    }

    var staleCount: Int {
        visibleDevServices.filter(\.isStale).count
    }

    var protectedCount: Int {
        services.filter { $0.safety == .protected || $0.status == .protected }.count
    }

    var liveKindCounts: [(kind: ServiceKind, count: Int)] {
        Dictionary(grouping: visibleDevServices, by: \.kind)
            .map { (kind: $0.key, count: $0.value.count) }
            .filter { $0.count > 0 }
            .sorted {
                if $0.kind.summaryPriority != $1.kind.summaryPriority {
                    return $0.kind.summaryPriority < $1.kind.summaryPriority
                }
                return $0.kind.rawValue < $1.kind.rawValue
            }
    }

    func compactKindSummary(limit: Int = 2) -> String {
        let counts = liveKindCounts
        guard !counts.isEmpty else { return "Live 0" }
        let visible = counts.prefix(limit).map { "\($0.kind.compactLabel) \($0.count)" }
        let remaining = counts.dropFirst(limit).reduce(0) { $0 + $1.count }
        if remaining > 0 {
            return (visible + ["+\(remaining)"]).joined(separator: " · ")
        }
        return visible.joined(separator: " · ")
    }

    var fullKindSummary: String {
        let counts = liveKindCounts
        guard !counts.isEmpty else { return "No developer services" }
        return counts
            .map { "\($0.count) \($0.kind.rawValue)" }
            .joined(separator: " · ")
    }
}

enum WindowID {
    static let details = "details"
}
