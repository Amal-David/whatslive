import Darwin
import Foundation

enum ServiceStopError: LocalizedError {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .failed(let message):
            return message
        }
    }
}

struct ServiceStopper: Sendable {
    private let runner: CommandRunner

    init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    func stop(using plan: KillPlan) async throws {
        switch plan.action {
        case .processTERM(let pid):
            try signal(pid: pid, signal: SIGTERM)
        case .processKILL(let pid):
            try signal(pid: pid, signal: SIGKILL)
        case .dockerStop(let containerID):
            try await dockerStop(containerID)
        case .unavailable:
            throw ServiceStopError.unavailable(plan.reason)
        }
    }

    private func signal(pid: Int, signal: Int32) throws {
        guard kill(pid_t(pid), signal) == 0 else {
            throw ServiceStopError.failed(String(cString: strerror(errno)))
        }
    }

    private func dockerStop(_ containerID: String) async throws {
        let dockerPath: String
        if FileManager.default.fileExists(atPath: "/usr/local/bin/docker") {
            dockerPath = "/usr/local/bin/docker"
        } else if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/docker") {
            dockerPath = "/opt/homebrew/bin/docker"
        } else {
            throw ServiceStopError.unavailable("docker CLI is not installed.")
        }
        let result = try await runner.run(dockerPath, arguments: ["stop", containerID])
        guard result.status == 0 else {
            throw ServiceStopError.failed(result.stderr.isEmpty ? "docker stop failed." : result.stderr)
        }
    }
}
