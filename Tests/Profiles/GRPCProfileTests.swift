import XCTest
@testable import IncyProfiles

final class GRPCProfileTests: XCTestCase {
    private let base = "vless://11111111-1111-4111-8111-111111111111@192.0.2.10:443?security=tls&sni=www.example.com&type=grpc&serviceName=vpn%2Fedge&authority=grpc.example.invalid:443"

    private func stream(_ profile: Profile) throws -> [String: Any] {
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: XrayConfiguration.make(profile: profile)) as? [String: Any])
        let outbound = try XCTUnwrap((config["outbounds"] as? [[String: Any]])?.first)
        return try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
    }

    private func emit(_ profile: Profile, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["INCY_CONFIG_OUTPUT"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try XrayConfiguration.make(profile: profile).write(to: url.appendingPathComponent(name + ".json"))
    }

    func testURIModesPreserveServiceAndAuthorityInTheCoreConfiguration() throws {
        for mode in ["gun", "multi"] {
            let profile = try ProfileParser.parse(base + "&mode=" + mode)
            let settings = try stream(profile)
            let grpc = try XCTUnwrap(settings["grpcSettings"] as? [String: Any])
            XCTAssertEqual(grpc["multiMode"] as? Bool, mode == "multi")
            XCTAssertEqual(grpc["serviceName"] as? String, "vpn/edge")
            XCTAssertEqual(grpc["authority"] as? String, "grpc.example.invalid:443")
            XCTAssertEqual((settings["tlsSettings"] as? [String: Any])?["serverName"] as? String, "www.example.com")
            XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile)), profile)
            try emit(profile, name: "grpc-" + mode)
        }
    }

    func testDefaultModeAndProfilesSavedBeforeGRPCFieldsWereAdded() throws {
        for suffix in ["", "&mode="] {
            let profile = try ProfileParser.parse(base + suffix)
            XCTAssertEqual((try stream(profile)["grpcSettings"] as? [String: Any])?["multiMode"] as? Bool, false)
        }
        let recent = try ProfileParser.parse(base + "&mode=multi")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recent)) as? [String: Any])
        old.removeValue(forKey: "grpcMultiMode"); old.removeValue(forKey: "grpcAuthority")
        let restored = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(restored.grpcMultiMode); XCTAssertNil(restored.grpcAuthority)
        let grpc = try XCTUnwrap(try stream(restored)["grpcSettings"] as? [String: Any])
        XCTAssertEqual(grpc["multiMode"] as? Bool, false)
        XCTAssertNil(grpc["authority"])
    }

    func testModeIsOnlyInterpretedForGRPC() throws {
        let tcp = try ProfileParser.parse(base.replacingOccurrences(of: "type=grpc", with: "type=tcp") + "&mode=auto")
        XCTAssertEqual(tcp.transport, "tcp")
        XCTAssertNil(try stream(tcp)["grpcSettings"])
        XCTAssertThrowsError(try ProfileParser.parse(base.replacingOccurrences(of: "type=grpc", with: "type=xhttp") + "&mode=auto")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Транспорт xhttp"))
            XCTAssertFalse(error.localizedDescription.contains("mode=gun"))
        }
    }

    func testVMessGRPCMultiModeAndAuthority() throws {
        let config: [String: Any] = ["add": "192.0.2.11", "port": 443, "id": "11111111-1111-4111-8111-111111111111", "aid": 0,
                                     "net": "grpc", "type": "multi", "tls": "tls", "sni": "www.example.com",
                                     "host": "grpc.example.invalid", "path": "vmess-vpn"]
        let profile = try ProfileParser.parse("vmess://" + JSONSerialization.data(withJSONObject: config).base64EncodedString())
        let grpc = try XCTUnwrap(try stream(profile)["grpcSettings"] as? [String: Any])
        XCTAssertEqual(grpc["multiMode"] as? Bool, true)
        XCTAssertEqual(grpc["authority"] as? String, "grpc.example.invalid")
        XCTAssertEqual(grpc["serviceName"] as? String, "vmess-vpn")
        try emit(profile, name: "grpc-vmess-multi")
    }

    func testVLESSRealityOverGRPCPreservesItsSecuritySettings() throws {
        let key = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"
        let link = base.replacingOccurrences(of: "security=tls", with: "security=reality") + "&mode=multi&pbk=" + key + "&sid=abcd&fp=chrome"
        let profile = try ProfileParser.parse(link)
        let settings = try stream(profile)
        XCTAssertEqual(settings["security"] as? String, "reality")
        XCTAssertEqual((settings["realitySettings"] as? [String: Any])?["publicKey"] as? String, key)
        XCTAssertEqual((settings["grpcSettings"] as? [String: Any])?["multiMode"] as? Bool, true)
        XCTAssertThrowsError(try ProfileParser.parse(link + "&flow=xtls-rprx-vision"))
        try emit(profile, name: "grpc-reality")
    }

    func testUnknownGRPCModeAndMalformedAuthorityAreRejected() {
        XCTAssertThrowsError(try ProfileParser.parse(base + "&mode=private-mode-token")) { error in
            XCTAssertTrue(error.localizedDescription.contains("mode=multi"))
            XCTAssertFalse(error.localizedDescription.contains("private-mode-token"))
        }
        XCTAssertThrowsError(try ProfileParser.parse(base.replacingOccurrences(of: "authority=grpc.example.invalid:443", with: "authority=grpc.example.invalid%0A")))
    }
}
