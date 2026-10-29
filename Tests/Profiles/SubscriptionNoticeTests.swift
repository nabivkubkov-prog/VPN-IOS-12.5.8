import XCTest
@testable import IncyProfiles

final class SubscriptionNoticeTests: XCTestCase {
    private func notice(_ name: String) -> String {
        let tag = name.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)!
        return "vless://00000000-0000-0000-0000-000000000000@0.0.0.0:1?encryption=none&type=tcp#\(tag)"
    }

    func testEncodedUnsupportedClientNoticeCannotBecomeAServer() {
        let body = Data(notice("App not supported").utf8).base64EncodedString()
        XCTAssertThrowsError(try ProfileParser.parseBatch(body)) { error in
            XCTAssertTrue(error.localizedDescription.contains("App not supported"))
        }
    }

    func testPreviouslySavedNoticeCannotStartTheCore() {
        let profile = Profile(name: "App not supported", kind: "vless", host: "0.0.0.0", port: 1,
                              credential: "00000000-0000-0000-0000-000000000000")
        XCTAssertThrowsError(try XrayConfiguration.make(profile: profile)) { error in
            XCTAssertTrue(error.localizedDescription.contains("App not supported"))
        }
    }

    func testDeviceLimitAndAccountNoticesAreExplained() {
        for tag in ["Limit of devices reached", "Subscription expired", "Subscription disabled"] {
            XCTAssertThrowsError(try ProfileParser.parseBatch(notice(tag))) { error in
                XCTAssertFalse(error.localizedDescription.contains("00000000"))
                XCTAssertFalse(error.localizedDescription.contains("Неизвестная"))
            }
        }
    }

    func testHTTP200ServiceRejectionHeadersAreNotAcceptedAsSubscriptions() throws {
        for flag in ["x-hwid-not-supported", "x-hwid-max-devices-reached"] {
            let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.invalid/subscription/private-token")!,
                                                       statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [flag: "true"]))
            XCTAssertThrowsError(try SubscriptionResponse.validate(response)) { error in
                XCTAssertFalse(error.localizedDescription.contains("private-token"))
                XCTAssertFalse(error.localizedDescription.contains("1 МБ"))
            }
        }
    }
}
