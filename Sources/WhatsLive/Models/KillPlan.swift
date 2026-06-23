import Foundation

enum KillActionKind: Equatable, Sendable {
    case processTERM(pid: Int)
    case processKILL(pid: Int)
    case dockerStop(containerID: String)
    case unavailable
}

struct KillPlan: Equatable, Sendable {
    let action: KillActionKind
    let requiresConfirmation: Bool
    let reason: String
    let allowsForceStop: Bool
}

struct KillPlanner: Sendable {
    static func plan(for service: RunningService, force: Bool = false) -> KillPlan {
        if service.safety == .protected {
            return KillPlan(
                action: .unavailable,
                requiresConfirmation: true,
                reason: "Protected services are not stopped from What's Live.",
                allowsForceStop: false
            )
        }

        if let containerID = service.dockerContainerID {
            return KillPlan(
                action: .dockerStop(containerID: containerID),
                requiresConfirmation: true,
                reason: "Docker containers are stopped through docker stop.",
                allowsForceStop: false
            )
        }

        guard let pid = service.pid else {
            return KillPlan(
                action: .unavailable,
                requiresConfirmation: true,
                reason: "No process id is available.",
                allowsForceStop: false
            )
        }

        let action: KillActionKind = force ? .processKILL(pid: pid) : .processTERM(pid: pid)
        let riskyKinds: Set<ServiceKind> = [.database, .model, .simulator, .system, .unknown]
        let requiresConfirmation = service.safety != .safe || riskyKinds.contains(service.kind) || force
        let reason = force ? "Force stop sends SIGKILL." : "Stop sends SIGTERM first."

        return KillPlan(
            action: action,
            requiresConfirmation: requiresConfirmation,
            reason: reason,
            allowsForceStop: !force
        )
    }
}
