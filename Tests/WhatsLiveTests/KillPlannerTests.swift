import XCTest
@testable import WhatsLive

final class KillPlannerTests: XCTestCase {
    func testSafeDevServerUsesTermWithoutConfirmation() {
        let service = service(kind: .node, safety: .safe, pid: 123)

        let plan = KillPlanner.plan(for: service)

        XCTAssertEqual(plan.action, .processTERM(pid: 123))
        XCTAssertFalse(plan.requiresConfirmation)
        XCTAssertTrue(plan.allowsForceStop)
    }

    func testProtectedServiceIsUnavailable() {
        let service = service(kind: .database, safety: .protected, pid: 456)

        let plan = KillPlanner.plan(for: service)

        XCTAssertEqual(plan.action, .unavailable)
        XCTAssertTrue(plan.requiresConfirmation)
        XCTAssertFalse(plan.allowsForceStop)
    }

    func testDockerUsesDockerStop() {
        var service = service(kind: .docker, safety: .confirm, pid: nil)
        service = RunningService(
            id: service.id,
            title: service.title,
            kind: service.kind,
            pid: service.pid,
            parentPID: service.parentPID,
            user: service.user,
            command: service.command,
            cwd: service.cwd,
            ports: service.ports,
            startDate: service.startDate,
            httpProbe: service.httpProbe,
            dockerContainerID: "abc123",
            dockerStatus: "Up",
            classificationReason: service.classificationReason,
            staleReasons: service.staleReasons,
            safety: service.safety,
            status: service.status,
            killHistory: service.killHistory
        )

        let plan = KillPlanner.plan(for: service)

        XCTAssertEqual(plan.action, .dockerStop(containerID: "abc123"))
        XCTAssertTrue(plan.requiresConfirmation)
    }

    func testForceStopUsesSigkillAndConfirms() {
        let service = service(kind: .python, safety: .safe, pid: 789)

        let plan = KillPlanner.plan(for: service, force: true)

        XCTAssertEqual(plan.action, .processKILL(pid: 789))
        XCTAssertTrue(plan.requiresConfirmation)
        XCTAssertFalse(plan.allowsForceStop)
    }

    private func service(kind: ServiceKind, safety: SafetyLevel, pid: Int?) -> RunningService {
        RunningService(
            id: "test",
            title: "test",
            kind: kind,
            pid: pid,
            parentPID: nil,
            user: NSUserName(),
            command: "test",
            cwd: nil,
            ports: [],
            startDate: Date(),
            httpProbe: nil,
            dockerContainerID: nil,
            dockerStatus: nil,
            classificationReason: "test",
            staleReasons: [],
            safety: safety,
            status: safety == .protected ? .protected : .running,
            killHistory: []
        )
    }
}
