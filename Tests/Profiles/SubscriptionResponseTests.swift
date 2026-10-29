import XCTest
@testable import IncyProfiles

final class SubscriptionResponseTests: XCTestCase {
    private func response(_ status: Int, length: Int? = nil) throws -> HTTPURLResponse {
        let headers = length.map { ["Content-Length": String($0)] }
        return try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.invalid/subscription/private-token")!,
                                            statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
    }

    func testHTTPFailuresReportStatusWithoutClaimingSizeOrExposingURL() throws {
        for status in [401, 403, 404, 429, 503] {
            let reply = try response(status, length: SubscriptionResponse.maximumBytes + 1)
            XCTAssertThrowsError(try SubscriptionResponse.validate(reply)) { error in
                XCTAssertTrue(error.localizedDescription.contains("HTTP \(status)"))
                XCTAssertFalse(error.localizedDescription.contains("1 МБ"))
                XCTAssertFalse(error.localizedDescription.contains("private-token"))
            }
        }
    }

    func testUnknownAndAllowedContentLengthsAreAccepted() throws {
        XCTAssertNoThrow(try SubscriptionResponse.validate(response(200)))
        XCTAssertNoThrow(try SubscriptionResponse.validate(response(200, length: SubscriptionResponse.maximumBytes)))
    }

    func testAnnouncedOversizedSuccessfulResponseIsRejected() throws {
        let reply = try response(200, length: SubscriptionResponse.maximumBytes + 1)
        XCTAssertThrowsError(try SubscriptionResponse.validate(reply)) { error in
            XCTAssertTrue(error.localizedDescription.contains("1 МБ"))
        }
    }

    func testStreamedLimitKeepsBufferUnchangedAfterOversizedChunk() throws {
        var bytes = Data(repeating: 65, count: SubscriptionResponse.maximumBytes - 1)
        XCTAssertThrowsError(try SubscriptionResponse.append(Data([66, 67]), to: &bytes))
        XCTAssertEqual(bytes.count, SubscriptionResponse.maximumBytes - 1)
        try SubscriptionResponse.append(Data([68]), to: &bytes)
        XCTAssertEqual(bytes.count, SubscriptionResponse.maximumBytes)
        XCTAssertEqual(bytes.last, 68)
        XCTAssertThrowsError(try SubscriptionResponse.append(Data([69]), to: &bytes))
        XCTAssertEqual(bytes.last, 68)
    }

    func testNonHTTPResponseIsNotReportedAsOversized() {
        let reply = URLResponse(url: URL(string: "https://example.invalid")!, mimeType: nil,
                                expectedContentLength: SubscriptionResponse.maximumBytes + 1, textEncodingName: nil)
        XCTAssertThrowsError(try SubscriptionResponse.validate(reply)) { error in
            XCTAssertTrue(error.localizedDescription.contains("HTTP"))
            XCTAssertFalse(error.localizedDescription.contains("1 МБ"))
        }
    }
}
