import XCTest
@testable import WhatsLive

final class ParserTests: XCTestCase {
    func testParsesLsofRows() {
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node    1234 amal   12u  IPv4 0xabc      0t0  TCP 127.0.0.1:3000 (LISTEN)
        python  4321 amal    6u  IPv4 0xdef      0t0  TCP *:7860 (LISTEN)
        """

        let rows = ServiceParsers.parseLSOF(output)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].pid, 1234)
        XCTAssertEqual(rows[0].listener.port, 3000)
        XCTAssertEqual(rows[1].listener.address, "*")
    }

    func testParsesProcessRows() {
        let output = "1234 1 amal S Mon Jun 22 10:15:30 2026 node server.js\n"

        let rows = ServiceParsers.parsePS(output)

        XCTAssertEqual(rows[1234]?.parentPID, 1)
        XCTAssertEqual(rows[1234]?.user, "amal")
        XCTAssertEqual(rows[1234]?.command, "node server.js")
        XCTAssertNotNil(rows[1234]?.startDate)
    }

    func testParsesProcessResourceUsage() {
        let output = "1234 1 amal R Mon Jun 22 10:15:30 2026 20480 25.5 python app.py\n"

        let rows = ServiceParsers.parsePS(output)

        XCTAssertEqual(rows[1234]?.resourceUsage.cpuPercent, 25.5)
        XCTAssertEqual(rows[1234]?.resourceUsage.residentMemoryBytes, 20_971_520)
        XCTAssertEqual(rows[1234]?.resourceUsage.heat, .warm)
        XCTAssertEqual(rows[1234]?.command, "python app.py")
    }

    func testParsesDockerRows() {
        let rows = ServiceParsers.parseDockerPS("abc123\tapi\t0.0.0.0:8080->80/tcp\tUp 2 hours\n")

        XCTAssertEqual(rows.first?.id, "abc123")
        XCTAssertEqual(rows.first?.name, "api")
        XCTAssertEqual(rows.first?.ports, "0.0.0.0:8080->80/tcp")
    }

    func testParsesDockerStatsRows() {
        let rows = ServiceParsers.parseDockerStats("abc123\t4.50%\t128.5MiB / 7.7GiB\n")

        XCTAssertEqual(rows["abc123"]?.cpuPercent, 4.5)
        XCTAssertEqual(rows["abc123"]?.residentMemoryBytes, 134_742_016)
        XCTAssertEqual(rows["abc123"]?.heat, .cool)
    }

    func testParsesOllamaRows() {
        let output = """
        NAME ID SIZE PROCESSOR UNTIL
        llama3 abc 4.7 GB 100% GPU 4 minutes from now
        """

        let rows = ServiceParsers.parseOllamaPS(output)

        XCTAssertEqual(rows.first?.name, "llama3")
        XCTAssertEqual(rows.first?.id, "abc")
    }
}
