import XCTest
@testable import IncyProfiles

final class SubscriptionFormatTests: XCTestCase {
    private let key = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"
    private var link: String {
        "vless://11111111-1111-4111-8111-111111111111@node.example.invalid:443?encryption=none&security=reality&sni=www.example.com&fp=chrome&pbk=\(key)&sid=abcd&flow=xtls-rprx-vision&type=tcp#Server"
    }

    func testLargeEncodedSubscriptionImportsIndividualServers() throws {
        let links = (1...200).map { link.replacingOccurrences(of: "node.example.invalid", with: "node\($0).example.invalid") }
        let encoded = Data(links.joined(separator: "\n").utf8).base64EncodedString()
        XCTAssertGreaterThan(encoded.utf8.count, 32768)
        XCTAssertLessThan(encoded.utf8.count, SubscriptionResponse.maximumBytes)
        let profiles = try ProfileParser.parseBatch(encoded)
        XCTAssertEqual(profiles.count, 200)
        XCTAssertEqual(profiles.first?.host, "node1.example.invalid")
        XCTAssertEqual(profiles.last?.host, "node200.example.invalid")
    }

    func testFullJSONIsReportedAsAFormatErrorBeforeTheLinkSizeLimit() {
        let body = "[{\"outbounds\":[],\"private-token\":\"" + String(repeating: "a", count: 40000) + "\"}]"
        for text in [body, Data(body.utf8).base64EncodedString()] {
            XCTAssertThrowsError(try ProfileParser.parseBatch(text)) { error in
                XCTAssertTrue(error.localizedDescription.contains("JSON"))
                XCTAssertFalse(error.localizedDescription.contains("слишком длинная"))
                XCTAssertFalse(error.localizedDescription.contains("private-token"))
            }
        }
    }

    func testWebPageIsExplainedForPlainAndEncodedResponses() {
        let page = "<!DOCTYPE html><html><body>https://example.invalid/private-token" + String(repeating: "a", count: 40000) + "</body></html>"
        for text in [page, Data(page.utf8).base64EncodedString()] {
            XCTAssertThrowsError(try ProfileParser.parseBatch(text)) { error in
                XCTAssertTrue(error.localizedDescription.contains("веб-страницу"))
                XCTAssertFalse(error.localizedDescription.contains("слишком длинная"))
                XCTAssertFalse(error.localizedDescription.contains("private-token"))
            }
        }
    }

    func testAnOversizedIndividualLinkIsStillRejected() {
        let oversized = link + String(repeating: "a", count: 32768)
        XCTAssertThrowsError(try ProfileParser.parseBatch(oversized)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Ссылка слишком длинная"))
        }
    }
}
