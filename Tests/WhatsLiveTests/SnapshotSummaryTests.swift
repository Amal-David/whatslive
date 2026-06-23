import XCTest
@testable import WhatsLive

final class SnapshotSummaryTests: XCTestCase {
    func testCompactSummaryPrioritizesPythonThenNode() {
        let snapshot = ServiceSnapshot(
            services: [
                service(kind: .node),
                service(kind: .python),
                service(kind: .python),
                service(kind: .rust)
            ],
            lastUpdated: nil,
            isScanning: false,
            errorMessage: nil
        )

        XCTAssertEqual(snapshot.compactKindSummary(), "Py 2 · Node 1 · +1")
        XCTAssertEqual(snapshot.fullKindSummary, "2 Python · 1 Node · 1 Rust")
    }

    func testSummaryIgnoresDatabaseAndSystem() {
        let snapshot = ServiceSnapshot(
            services: [
                service(kind: .database),
                service(kind: .system),
                service(kind: .monitor)
            ],
            lastUpdated: nil,
            isScanning: false,
            errorMessage: nil
        )

        XCTAssertEqual(snapshot.compactKindSummary(), "Live 0")
        XCTAssertEqual(snapshot.fullKindSummary, "No developer services")
    }

    private func service(kind: ServiceKind) -> RunningService {
        RunningService(
            id: UUID().uuidString,
            title: kind.rawValue,
            kind: kind,
            pid: 1,
            parentPID: nil,
            user: "amal",
            command: kind.rawValue,
            cwd: nil,
            ports: [],
            startDate: nil,
            httpProbe: nil,
            dockerContainerID: nil,
            dockerStatus: nil,
            classificationReason: "test",
            staleReasons: [],
            safety: .safe,
            status: .running,
            killHistory: []
        )
    }
}
