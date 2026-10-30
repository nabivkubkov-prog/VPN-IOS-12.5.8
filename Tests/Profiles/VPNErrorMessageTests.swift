import XCTest
@testable import IncyProfiles

final class VPNErrorMessageTests: XCTestCase {
    func testUnderlyingNetworkExtensionPermissionDenialExplainsSigning() {
        let cause = NSError(domain: "NEConfigurationErrorDomain", code: 10)
        let error = NSError(domain: "NEVPNErrorDomain", code: 5,
                            userInfo: [NSUnderlyingErrorKey: cause])
        let message = VPNErrorMessage.describe(error)
        XCTAssertTrue(message.contains("Network Extensions"))
        XCTAssertTrue(message.contains("Бесплатная подпись"))
    }

    func testPOSIXPermissionDeniedExplainsSigning() {
        for code in [1, 13] {
            XCTAssertTrue(VPNErrorMessage.describe(NSError(domain: NSPOSIXErrorDomain, code: code)).contains("Network Extensions"))
        }
    }

    func testUnrelatedConfigurationFailuresKeepTheirActualDescription() {
        let error = NSError(domain: "NEVPNErrorDomain", code: 5,
                            userInfo: [NSLocalizedDescriptionKey: "Недостаточно места для конфигурации."])
        XCTAssertEqual(VPNErrorMessage.describe(error), error.localizedDescription)
        let other = NSError(domain: "OtherDomain", code: 10,
                            userInfo: [NSLocalizedDescriptionKey: "Другая ошибка."])
        XCTAssertEqual(VPNErrorMessage.describe(other), other.localizedDescription)
    }
}
