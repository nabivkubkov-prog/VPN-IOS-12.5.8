import XCTest
@testable import IncyProfiles

final class SubscriptionRequestTests: XCTestCase {
    func testDeviceRegistrationIsStableAcrossRequestsAndAccountErrors() throws {
        let suite = "INCY.tests.subscription.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = SubscriptionRequest.deviceID(in: defaults)
        let headers = SubscriptionRequest.headers(deviceID: first, osVersion: "12.5.8", model: "iPhone")
        let hwid = try XCTUnwrap(headers["x-hwid"])
        XCTAssertNotNil(hwid.range(of: "^[a-zA-Z0-9=-]{10,64}$", options: .regularExpression))
        XCTAssertEqual(headers["x-device-os"], "iOS")
        XCTAssertEqual(headers["x-ver-os"], "12.5.8")

        let rejection = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.invalid/subscription")!,
                                                    statusCode: 200, httpVersion: "HTTP/1.1",
                                                    headerFields: ["x-hwid-max-devices-reached": "true"]))
        XCTAssertThrowsError(try SubscriptionResponse.validate(rejection))
        let recreatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(SubscriptionRequest.deviceID(in: recreatedDefaults), first)
    }

    func testSeparateInstallationsUseSeparateRegistrationIdentities() throws {
        let firstSuite = "INCY.tests.subscription.\(UUID().uuidString)"
        let secondSuite = "INCY.tests.subscription.\(UUID().uuidString)"
        let first = try XCTUnwrap(UserDefaults(suiteName: firstSuite))
        let second = try XCTUnwrap(UserDefaults(suiteName: secondSuite))
        defer {
            first.removePersistentDomain(forName: firstSuite)
            second.removePersistentDomain(forName: secondSuite)
        }
        XCTAssertNotEqual(SubscriptionRequest.deviceID(in: first), SubscriptionRequest.deviceID(in: second))
    }
}
