import Foundation

enum ServiceKind: String, CaseIterable, Sendable {
    case monitor = "What's Live"
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
        case .monitor: "waveform.path.ecg"
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
        case .monitor: "App"
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
        case .monitor: 9
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

enum HeatLevel: String, Sendable {
    case cool = "Cool"
    case warm = "Warm"
    case hot = "Hot"
    case unknown = "Unknown"

    static func estimate(cpuPercent: Double?, status: String) -> HeatLevel {
        guard let cpuPercent else { return .unknown }
        if cpuPercent >= 75 { return .hot }
        if cpuPercent >= 20 { return .warm }
        if status.contains("R"), cpuPercent >= 5 { return .warm }
        return .cool
    }
}

struct ResourceUsage: Hashable, Sendable {
    let cpuPercent: Double?
    let residentMemoryBytes: Int64?
    let heat: HeatLevel

    static let unavailable = ResourceUsage(cpuPercent: nil, residentMemoryBytes: nil, heat: .unknown)

    static func fromPS(cpuPercent: Double?, residentMemoryKilobytes: Int?, status: String) -> ResourceUsage {
        let bytes = residentMemoryKilobytes.map { Int64($0) * 1_024 }
        return ResourceUsage(
            cpuPercent: cpuPercent,
            residentMemoryBytes: bytes,
            heat: HeatLevel.estimate(cpuPercent: cpuPercent, status: status)
        )
    }

    var cpuText: String {
        guard let cpuPercent else { return "CPU --" }
        return String(format: "CPU %.1f%%", cpuPercent)
    }

    var memoryText: String {
        guard let residentMemoryBytes else { return "Mem --" }
        let mebibytes = Double(residentMemoryBytes) / 1_048_576
        if mebibytes >= 1_024 {
            return String(format: "%.1f GB", mebibytes / 1_024)
        }
        if mebibytes >= 100 {
            return "\(Int(mebibytes.rounded())) MB"
        }
        return String(format: "%.1f MB", mebibytes)
    }

    var heatText: String {
        heat == .unknown ? "Heat --" : "Heat \(heat.rawValue)"
    }

    var compactSummary: String {
        "\(cpuText) - \(memoryText) - \(heatText)"
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
    let resourceUsage: ResourceUsage

    init(
        pid: Int,
        parentPID: Int,
        user: String,
        status: String,
        startDate: Date?,
        command: String,
        cwd: String?,
        resourceUsage: ResourceUsage = .unavailable
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.user = user
        self.status = status
        self.startDate = startDate
        self.command = command
        self.cwd = cwd
        self.resourceUsage = resourceUsage
    }
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
    let resourceUsage: ResourceUsage
    let classificationReason: String
    let staleReasons: [String]
    let safety: SafetyLevel
    var status: ServiceStatus
    var killHistory: [KillEvent]

    init(
        id: String,
        title: String,
        kind: ServiceKind,
        pid: Int?,
        parentPID: Int?,
        user: String,
        command: String,
        cwd: String?,
        ports: [PortListener],
        startDate: Date?,
        httpProbe: String?,
        dockerContainerID: String?,
        dockerStatus: String?,
        resourceUsage: ResourceUsage = .unavailable,
        classificationReason: String,
        staleReasons: [String],
        safety: SafetyLevel,
        status: ServiceStatus,
        killHistory: [KillEvent]
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.pid = pid
        self.parentPID = parentPID
        self.user = user
        self.command = command
        self.cwd = cwd
        self.ports = ports
        self.startDate = startDate
        self.httpProbe = httpProbe
        self.dockerContainerID = dockerContainerID
        self.dockerStatus = dockerStatus
        self.resourceUsage = resourceUsage
        self.classificationReason = classificationReason
        self.staleReasons = staleReasons
        self.safety = safety
        self.status = status
        self.killHistory = killHistory
    }

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
        services.filter { $0.kind != .system && $0.kind != .database && $0.kind != .monitor }
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
