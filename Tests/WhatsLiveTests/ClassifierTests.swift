import XCTest
@testable import WhatsLive

final class ClassifierTests: XCTestCase {
    private let classifier = ServiceClassifier()

    func testNodeServiceOlderThanThresholdIsStaleAndSafe() {
        let process = ProcessInfoSnapshot(
            pid: 100,
            parentPID: 1,
            user: NSUserName(),
            status: "S",
            startDate: Date().addingTimeInterval(-8 * 3600),
            command: "node server.js",
            cwd: "/tmp"
        )
        let service = classifier.classify(
            pid: 100,
            lsofCommand: "node",
            process: process,
            ports: [PortListener(address: "127.0.0.1", port: 3000, rawName: "127.0.0.1:3000")],
            httpProbe: "HTTP 200",
            options: options()
        )

        XCTAssertEqual(service?.kind, .node)
        XCTAssertEqual(service?.safety, .safe)
        XCTAssertEqual(service?.status, .stale)
        XCTAssertFalse(service?.staleReasons.isEmpty ?? true)
    }

    func testDatabaseIsProtected() {
        let process = ProcessInfoSnapshot(
            pid: 200,
            parentPID: 1,
            user: NSUserName(),
            status: "S",
            startDate: Date(),
            command: "postgres -D data",
            cwd: nil
        )
        let service = classifier.classify(
            pid: 200,
            lsofCommand: "postgres",
            process: process,
            ports: [PortListener(address: "127.0.0.1", port: 5432, rawName: "127.0.0.1:5432")],
            httpProbe: nil,
            options: options(includeAll: true)
        )

        XCTAssertEqual(service?.kind, .database)
        XCTAssertEqual(service?.safety, .protected)
        XCTAssertEqual(service?.status, .protected)
    }

    func testModelServerRequiresConfirmation() {
        let process = ProcessInfoSnapshot(
            pid: 300,
            parentPID: 1,
            user: NSUserName(),
            status: "S",
            startDate: Date().addingTimeInterval(-9 * 3600),
            command: "python -m llama_cpp.server --port 8081",
            cwd: "/tmp"
        )
        let service = classifier.classify(
            pid: 300,
            lsofCommand: "python",
            process: process,
            ports: [PortListener(address: "127.0.0.1", port: 8081, rawName: "127.0.0.1:8081")],
            httpProbe: "HTTP 404",
            options: options()
        )

        XCTAssertEqual(service?.kind, .model)
        XCTAssertEqual(service?.safety, .confirm)
        XCTAssertEqual(service?.status, .stale)
    }

    func testWhatsLiveServiceIsVisibleButProtected() {
        let process = ProcessInfoSnapshot(
            pid: 400,
            parentPID: 1,
            user: NSUserName(),
            status: "S",
            startDate: Date(),
            command: "/Users/amal/Applications/What's Live.app/Contents/MacOS/WhatsLive",
            cwd: nil,
            resourceUsage: ResourceUsage(cpuPercent: 0.2, residentMemoryBytes: 45_000_000, heat: .cool)
        )

        let service = classifier.whatsLiveService(process: process)

        XCTAssertEqual(service.title, "What's Live")
        XCTAssertEqual(service.kind, .monitor)
        XCTAssertEqual(service.safety, .protected)
        XCTAssertEqual(service.status, .running)
        XCTAssertEqual(service.portSummary, "no port")
        XCTAssertEqual(service.resourceUsage.cpuPercent, 0.2)
    }

    private func options(includeAll: Bool = false) -> ScannerOptions {
        ScannerOptions(
            staleThreshold: 6 * 3600,
            includeAllListeners: includeAll,
            ignoredPorts: [],
            protectedNames: ["postgres", "mongod", "redis-server"],
            enableDockerProbe: true,
            enableOllamaProbe: true
        )
    }
}
