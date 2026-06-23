import Darwin
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
                        cwd: cwd,
                        resourceUsage: $0.resourceUsage
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
        let currentPID = Int(ProcessInfo.processInfo.processIdentifier)
        if !services.contains(where: { $0.pid == currentPID }) {
            services.append(classifier.whatsLiveService(process: processMap[currentPID]))
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
        let result = try await runner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,user=,stat=,lstart=,rss=,%cpu=,command="])
        return ServiceParsers.parsePS(result.stdout)
    }

    private func loadCWD(pid: Int) async throws -> String? {
        let result = try await runner.run("/usr/sbin/lsof", arguments: ["-nP", "-a", "-p", "\(pid)", "-d", "cwd"])
        guard result.status == 0 else { return nil }
        return ServiceParsers.parseCWD(result.stdout)
    }

    private func probeHTTP(ports: [PortListener]) async -> String? {
        for listener in ports where listener.address == "127.0.0.1" || listener.address == "localhost" || listener.address == "*" {
            if let status = await HTTPHeadProbe.statusCode(port: listener.port) {
                return "HTTP \(status)"
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
        let usageByID = await loadDockerStats(dockerPath: dockerPath)
        let containers = ServiceParsers.parseDockerPS(result.stdout).map { container in
            DockerContainerSnapshot(
                id: container.id,
                name: container.name,
                ports: container.ports,
                status: container.status,
                resourceUsage: usageByID[container.id] ?? .unavailable
            )
        }
        return containers.map(classifier.dockerService(from:))
    }

    private func loadDockerStats(dockerPath: String) async -> [String: ResourceUsage] {
        guard let result = try? await runner.run(
            dockerPath,
            arguments: ["stats", "--no-stream", "--format", "{{.ID}}\t{{.CPUPerc}}\t{{.MemUsage}}"]
        ),
            result.status == 0
        else { return [:] }
        return ServiceParsers.parseDockerStats(result.stdout)
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

private enum HTTPHeadProbe {
    static func statusCode(port: Int) async -> Int? {
        await Task.detached(priority: .utility) {
            let descriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard descriptor >= 0 else { return nil }
            defer { close(descriptor) }

            var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(port).bigEndian
            inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)

            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard connected == 0 else { return nil }

            let request = "HEAD / HTTP/1.0\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
            let sent = request.withCString { bytes in
                send(descriptor, bytes, strlen(bytes), 0)
            }
            guard sent > 0 else { return nil }

            var buffer = [UInt8](repeating: 0, count: 128)
            let received = recv(descriptor, &buffer, buffer.count, 0)
            guard received > 0,
                  let response = String(bytes: buffer.prefix(received), encoding: .utf8)
            else { return nil }

            let parts = response.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { return nil }
            return Int(parts[1])
        }.value
    }
}
