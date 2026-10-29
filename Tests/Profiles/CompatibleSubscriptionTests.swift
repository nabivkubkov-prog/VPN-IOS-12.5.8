import XCTest
@testable import IncyProfiles

final class CompatibleSubscriptionTests: XCTestCase {
    private let compatible = "vless://11111111-1111-4111-8111-111111111111@192.0.2.10:443?security=tls&sni=example.com&type=grpc&mode=multi&serviceName=vpn"
    private var unsupported: String { compatible.replacingOccurrences(of: "type=grpc&mode=multi", with: "type=xhttp&mode=auto") }

    func testMixedSubscriptionImportsSupportedServersAndReportsOmissions() throws {
        let second = compatible.replacingOccurrences(of: "192.0.2.10", with: "192.0.2.11")
        let text = Data((unsupported + "\n" + compatible + "\n" + second).utf8).base64EncodedString()
        let parsed = try ProfileParser.parseSubscription(text)
        XCTAssertEqual(parsed.profiles.map { $0.host }, ["192.0.2.10", "192.0.2.11"])
        XCTAssertEqual(parsed.omissions.count, 1)
        XCTAssertTrue(parsed.omissions[0].contains("Строка 1"))
        XCTAssertTrue(parsed.omissions[0].contains("Транспорт xhttp"))
        XCTAssertFalse(parsed.omissions[0].contains("11111111"))
    }

    func testStrictBatchParsingAndMalformedRowsRemainAtomic() {
        XCTAssertThrowsError(try ProfileParser.parseBatch(unsupported + "\n" + compatible))
        XCTAssertThrowsError(try ProfileParser.parseSubscription(compatible + "\nnot-a-profile"))
    }

    func testServiceRejectionCannotBeSkippedAsAnUnsupportedServer() {
        let notice = "vless://00000000-0000-0000-0000-000000000000@0.0.0.0:1#App%20not%20supported"
        XCTAssertThrowsError(try ProfileParser.parseSubscription(compatible + "\n" + notice)) { error in
            XCTAssertTrue(error.localizedDescription.contains("App not supported"))
        }
    }

    func testAllUnsupportedServersExplainTheNeedForACompatibleTransport() {
        XCTAssertThrowsError(try ProfileParser.parseSubscription(unsupported)) { error in
            XCTAssertTrue(error.localizedDescription.contains("нет совместимых серверов"))
            XCTAssertTrue(error.localizedDescription.contains("Транспорт xhttp"))
            XCTAssertFalse(error.localizedDescription.contains("11111111"))
        }
    }

    func testSubscriptionLimitsAreCheckedBeforeFilteringRows() {
        XCTAssertThrowsError(try ProfileParser.parseSubscription(String(repeating: "a", count: 1_048_577)))
        XCTAssertThrowsError(try ProfileParser.parseSubscription(Array(repeating: unsupported, count: 257).joined(separator: "\n")))
    }
}
