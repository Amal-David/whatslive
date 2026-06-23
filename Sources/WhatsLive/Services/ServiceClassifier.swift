import Foundation

struct ScannerOptions: Sendable {
    let staleThreshold: TimeInterval
    let includeAllListeners: Bool
    let ignoredPorts: Set<Int>
    let protectedNames: Set<String>
    let enableDockerProbe: Bool
    let enableOllamaProbe: Bool
}

struct ServiceClassifier: Sendable {
    func classify(
        pid: Int,
        lsofCommand: String,
        process: ProcessInfoSnapshot?,
        ports: [PortListener],
        httpProbe: String?,
        options: ScannerOptions
    ) -> RunningService? {
        let command = process?.command ?? lsofCommand
        let lowerCommand = command.lowercased()
        let lowerName = lsofCommand.lowercased()
        let cwd = process?.cwd
        let kind = kindFor(command: lowerCommand, lsofCommand: lowerName, ports: ports)
        let title = titleFor(kind: kind, command: command, lsofCommand: lsofCommand)
        let isDeveloperService = [.node, .python, .rust, .model, .docker, .simulator, .unknown].contains(kind)

        if !options.includeAllListeners, !isDeveloperService {
            return nil
        }
        if !options.ignoredPorts.isEmpty, ports.allSatisfy({ options.ignoredPorts.contains($0.port) }) {
            return nil
        }

        let protected = options.protectedNames.contains { token in
            lowerCommand.contains(token) || lowerName.contains(token)
        }
        let safety: SafetyLevel = protected || kind == .system || kind == .database ? .protected : safetyFor(kind: kind)
        let staleReasons = staleReasonsFor(
            kind: kind,
            process: process,
            cwd: cwd,
            command: lowerCommand,
            threshold: options.staleThreshold
        )
        let status: ServiceStatus
        if safety == .protected {
            status = .protected
        } else if staleReasons.isEmpty {
            status = .running
        } else {
            status = .stale
        }

        return RunningService(
            id: "process-\(pid)",
            title: title,
            kind: kind,
            pid: pid,
            parentPID: process?.parentPID,
            user: process?.user ?? NSUserName(),
            command: command,
            cwd: cwd,
            ports: ports.sorted { $0.port < $1.port },
            startDate: process?.startDate,
            httpProbe: httpProbe,
            dockerContainerID: nil,
            dockerStatus: nil,
            resourceUsage: process?.resourceUsage ?? .unavailable,
            classificationReason: classificationReason(kind: kind, command: command, httpProbe: httpProbe),
            staleReasons: staleReasons,
            safety: safety,
            status: status,
            killHistory: []
        )
    }

    func whatsLiveService(process: ProcessInfoSnapshot?) -> RunningService {
        let pid = process?.pid ?? Int(ProcessInfo.processInfo.processIdentifier)
        let command = process?.command ?? Bundle.main.executablePath ?? "WhatsLive"
        return RunningService(
            id: "process-\(pid)",
            title: "What's Live",
            kind: .monitor,
            pid: pid,
            parentPID: process?.parentPID,
            user: process?.user ?? NSUserName(),
            command: command,
            cwd: Bundle.main.bundlePath,
            ports: [],
            startDate: process?.startDate,
            httpProbe: nil,
            dockerContainerID: nil,
            dockerStatus: nil,
            resourceUsage: process?.resourceUsage ?? .unavailable,
            classificationReason: "Background menu bar monitor process.",
            staleReasons: [],
            safety: .protected,
            status: .running,
            killHistory: []
        )
    }

    func dockerService(from container: DockerContainerSnapshot) -> RunningService {
        RunningService(
            id: "docker-\(container.id)",
            title: container.name,
            kind: .docker,
            pid: nil,
            parentPID: nil,
            user: NSUserName(),
            command: "docker container \(container.name)",
            cwd: nil,
            ports: dockerPorts(container.ports),
            startDate: nil,
            httpProbe: nil,
            dockerContainerID: container.id,
            dockerStatus: container.status,
            resourceUsage: .unavailable,
            classificationReason: "Docker container from docker ps.",
            staleReasons: [],
            safety: .confirm,
            status: .running,
            killHistory: []
        )
    }

    func ollamaService(from model: OllamaModelSnapshot) -> RunningService {
        RunningService(
            id: "ollama-\(model.id)",
            title: model.name,
            kind: .model,
            pid: nil,
            parentPID: nil,
            user: NSUserName(),
            command: "ollama model \(model.name)",
            cwd: nil,
            ports: [],
            startDate: nil,
            httpProbe: nil,
            dockerContainerID: nil,
            dockerStatus: "\(model.processor), until \(model.until)",
            resourceUsage: .unavailable,
            classificationReason: "Running Ollama model.",
            staleReasons: [],
            safety: .confirm,
            status: .running,
            killHistory: []
        )
    }

    private func kindFor(command: String, lsofCommand: String, ports: [PortListener]) -> ServiceKind {
        let text = "\(command) \(lsofCommand)"
        if text.contains("postgres") || text.contains("mongod") || text.contains("redis") || text.contains("mysql") {
            return .database
        }
        if text.contains("ollama") || text.contains("mlx") || text.contains("lm studio") || text.contains("llama") || text.contains("gguf") {
            return .model
        }
        if text.contains("simulator") || text.contains("emulator") || text.contains("adb") {
            return .simulator
        }
        if text.contains("node") || text.contains("npm") || text.contains("pnpm") || text.contains("bun") || text.contains("vite") || text.contains("next") {
            return .node
        }
        if text.contains("python") || text.contains("uvicorn") || text.contains("fastapi") || text.contains("flask") || text.contains("django") || text.contains("gradio") {
            return .python
        }
        if text.contains("cargo") || text.contains("target/debug") || text.contains("rust") {
            return .rust
        }
        if text.contains("/system/library") || text.contains("/usr/libexec") || text.contains("rapportd") {
            return .system
        }
        if ports.contains(where: { [3000, 3001, 4173, 4343, 5000, 5173, 7860, 8000, 8080, 8081].contains($0.port) }) {
            return .unknown
        }
        return .system
    }

    private func safetyFor(kind: ServiceKind) -> SafetyLevel {
        switch kind {
        case .monitor:
            return .protected
        case .node, .python, .rust:
            return .safe
        case .model, .docker, .simulator, .unknown:
            return .confirm
        case .database, .system:
            return .protected
        }
    }

    private func staleReasonsFor(
        kind: ServiceKind,
        process: ProcessInfoSnapshot?,
        cwd: String?,
        command: String,
        threshold: TimeInterval
    ) -> [String] {
        guard [.node, .python, .rust, .model, .unknown].contains(kind) else { return [] }
        var reasons: [String] = []
        if let startDate = process?.startDate, Date().timeIntervalSince(startDate) >= threshold {
            reasons.append("older than \(TimeFormatters.duration(threshold))")
        }
        if let cwd, !FileManager.default.fileExists(atPath: cwd) {
            reasons.append("cwd no longer exists")
        }
        if let process, process.parentPID == 1, reasons.isEmpty == false {
            reasons.append("detached parent")
        }
        if cwd == nil, reasons.isEmpty == false {
            reasons.append("cwd unavailable")
        }
        if command.contains("/tmp/") && reasons.isEmpty == false {
            reasons.append("running from temp path")
        }
        return reasons
    }

    private func classificationReason(kind: ServiceKind, command: String, httpProbe: String?) -> String {
        if let httpProbe {
            return "\(kind.rawValue) service; HTTP probe returned \(httpProbe)."
        }
        return "\(kind.rawValue) service from command: \(short(command, limit: 90))."
    }

    private func titleFor(kind: ServiceKind, command: String, lsofCommand: String) -> String {
        let candidates = command.split(separator: " ").map(String.init)
        if let moduleIndex = candidates.firstIndex(of: "-m"), candidates.indices.contains(candidates.index(after: moduleIndex)) {
            return candidates[candidates.index(after: moduleIndex)]
        }
        if let script = candidates.first(where: { $0.hasSuffix(".py") || $0.hasSuffix(".js") || $0.hasSuffix(".ts") }) {
            return URL(fileURLWithPath: script).lastPathComponent
        }
        if let binary = candidates.first {
            return URL(fileURLWithPath: binary).lastPathComponent
        }
        return kind == .unknown ? lsofCommand : kind.rawValue
    }

    private func dockerPorts(_ text: String) -> [PortListener] {
        let pieces = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return pieces.compactMap { piece in
            guard let separator = piece.lastIndex(of: ":") else { return nil }
            let tail = piece[piece.index(after: separator)...]
            let portText = tail.split(separator: "-").first.map(String.init) ?? String(tail)
            guard let port = Int(portText.filter(\.isNumber)) else { return nil }
            return PortListener(address: "docker", port: port, rawName: piece)
        }
    }

    private func short(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "..."
    }
}
