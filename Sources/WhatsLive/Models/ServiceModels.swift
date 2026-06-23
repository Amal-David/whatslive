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
}

enum WindowID {
    static let details = "details"
}
