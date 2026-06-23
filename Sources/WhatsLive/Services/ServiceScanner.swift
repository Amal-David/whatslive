import Foundation

struct ServiceScanner: Sendable {
    private let runner: CommandRunner
    private let classifier: ServiceClassifier

    init(runner: CommandRunner = CommandRunner(), classifier: ServiceClassifier = ServiceClassifier()) {
        self.runner = runner
        self.classifier = classifier
    }

    func scan(options: ScannerOptions) async throws -> [RunningService] {
        async let lsofRows = loadLSOF()
        async let psRows = loadPS()

        let (rows, processMap) = try await (lsofRows, psRows)
        let grouped = Dictionary(grouping: rows, by: \.pid)
        var services: [RunningService] = []

        for (pid, group) in grouped {
            var process = processMap[pid]
            if let cwd = try? await loadCWD(pid: pid) {
                process = process.map {
                    ProcessInfoSnapshot(
                        pid: $0.pid,
                        parentPID: $0.parentPID,
                        user: $0.user,
                        status: $0.status,
                        startDate: $0.startDate,
                        command: $0.command,
                        cwd: cwd
                    )
                }
            }
            let ports = Array(Set(group.map(\.listener))).sorted { $0.port < $1.port }
            let probe = await probeHTTP(ports: ports)
            if let service = classifier.classify(
                pid: pid,
                lsofCommand: group.first?.command ?? "process",
                process: process,
                ports: ports,
                httpProbe: probe,
                options: options
            ) {
                services.append(service)
            }
        }

        if options.enableDockerProbe {
            services.append(contentsOf: await loadDockerServices())
        }
        if options.enableOllamaProbe {
            services.append(contentsOf: await loadOllamaServices())
        }

        return services.sorted { lhs, rhs in
            if lhs.isStale != rhs.isStale { return lhs.isStale && !rhs.isStale }
            if lhs.safety == .protected, rhs.safety != .protected { return false }
            if lhs.safety != .protected, rhs.safety == .protected { return true }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func loadLSOF() async throws -> [LSOFRow] {
        let result = try await runner.run("/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"])
        return ServiceParsers.parseLSOF(result.stdout)
    }

    private func loadPS() async throws -> [Int: ProcessInfoSnapshot] {
        let result = try await runner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,user=,stat=,lstart=,command="])
        return ServiceParsers.parsePS(result.stdout)
    }

    private func loadCWD(pid: Int) async throws -> String? {
        let result = try await runner.run("/usr/sbin/lsof", arguments: ["-nP", "-a", "-p", "\(pid)", "-d", "cwd"])
        guard result.status == 0 else { return nil }
        return ServiceParsers.parseCWD(result.stdout)
    }

    private func probeHTTP(ports: [PortListener]) async -> String? {
        for listener in ports where listener.address == "127.0.0.1" || listener.address == "localhost" || listener.address == "*" {
            guard let url = URL(string: "http://127.0.0.1:\(listener.port)") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 0.6)
            request.httpMethod = "HEAD"
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    return "HTTP \(http.statusCode)"
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func loadDockerServices() async -> [RunningService] {
        guard FileManager.default.fileExists(atPath: "/usr/local/bin/docker")
                || FileManager.default.fileExists(atPath: "/opt/homebrew/bin/docker")
        else { return [] }
        let dockerPath = FileManager.default.fileExists(atPath: "/usr/local/bin/docker") ? "/usr/local/bin/docker" : "/opt/homebrew/bin/docker"
        guard let result = try? await runner.run(dockerPath, arguments: ["ps", "--format", "{{.ID}}\t{{.Names}}\t{{.Ports}}\t{{.Status}}"]),
              result.status == 0
        else { return [] }
        return ServiceParsers.parseDockerPS(result.stdout).map(classifier.dockerService(from:))
    }

    private func loadOllamaServices() async -> [RunningService] {
        guard FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama")
                || FileManager.default.fileExists(atPath: "/usr/local/bin/ollama")
        else { return [] }
        let ollamaPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama") ? "/opt/homebrew/bin/ollama" : "/usr/local/bin/ollama"
        guard let result = try? await runner.run(ollamaPath, arguments: ["ps"]),
              result.status == 0
        else { return [] }
        return ServiceParsers.parseOllamaPS(result.stdout).map(classifier.ollamaService(from:))
    }
}
