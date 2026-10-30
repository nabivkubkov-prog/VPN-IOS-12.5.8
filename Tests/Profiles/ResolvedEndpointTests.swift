import XCTest
@testable import IncyProfiles

final class ResolvedEndpointTests: XCTestCase {
    private let uuid = "11111111-1111-4111-8111-111111111111"
    private let key = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"
    private let ip = "192.0.2.17"

    private func configuration(_ profile: Profile, emit name: String? = nil) throws -> [String: Any] {
        let data = try XrayConfiguration.make(profile: profile, upstreamIP: ip)
        if let name = name, let directory = ProcessInfo.processInfo.environment["INCY_CONFIG_OUTPUT"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try data.write(to: url.appendingPathComponent(name + ".json"))
        }
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.count, 1)
        let outbound = try XCTUnwrap(outbounds.first)
        let settings = try XCTUnwrap(outbound["settings"] as? [String: Any])
        let servers = try XCTUnwrap((settings["vnext"] ?? settings["servers"]) as? [[String: Any]])
        XCTAssertEqual(servers.first?["address"] as? String, ip)
        return try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
    }

    func testTLSNameUsesOriginalHostAndSavedProfileIsUnchanged() throws {
        var p = try ProfileParser.parse("vless://\(uuid)@vpn.example.invalid:443?security=tls")
        let saved = try JSONEncoder().encode(p)
        var stream = try configuration(p, emit: "resolved-tls")
        XCTAssertEqual((stream["tlsSettings"] as? [String: Any])?["serverName"] as? String, "vpn.example.invalid")
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: saved), p)
        XCTAssertEqual(p.host, "vpn.example.invalid")
        p.sni = "cert.example.invalid"
        stream = try configuration(p)
        XCTAssertEqual((stream["tlsSettings"] as? [String: Any])?["serverName"] as? String, p.sni)
        XCTAssertEqual((stream["tlsSettings"] as? [String: Any])?["allowInsecure"] as? Bool, false)
    }

    func testWebSocketDefaultAndExplicitHostWithBothPortConventions() throws {
        for security in ["none", "tls"] {
            let defaultPort = security == "tls" ? 443 : 80
            for port in [defaultPort, 8443] {
                var p = try ProfileParser.parse("vless://\(uuid)@vpn.example.invalid:\(port)?security=\(security)&type=ws&path=%2Fvpn")
                let stream = try configuration(p, emit: security == "tls" && port == 8443 ? "resolved-ws" : nil)
                let ws = try XCTUnwrap(stream["wsSettings"] as? [String: Any])
                XCTAssertEqual((ws["headers"] as? [String: String])?["Host"], port == defaultPort ? p.host : p.endpoint)
                XCTAssertEqual(ws["path"] as? String, "/vpn")
                p.hostHeader = "front.example.invalid"
                let explicit = try XCTUnwrap(try configuration(p)["wsSettings"] as? [String: Any])
                XCTAssertEqual((explicit["headers"] as? [String: String])?["Host"], p.hostHeader)
            }
        }
    }

    func testGRPCDefaultsRetainTheOriginalAuthorityForEachSecurityMode() throws {
        for security in ["none", "tls", "reality"] {
            var p = try ProfileParser.parse("vless://\(uuid)@vpn.example.invalid:8443?type=grpc&mode=multi&serviceName=edge&security=\(security)"
                + (security == "reality" ? "&sni=cert.example.invalid&pbk=\(key)&sid=abcd" : ""))
            let stream = try configuration(p, emit: "resolved-grpc-" + security)
            let grpc = try XCTUnwrap(stream["grpcSettings"] as? [String: Any])
            XCTAssertEqual(grpc["multiMode"] as? Bool, true)
            XCTAssertEqual(grpc["serviceName"] as? String, "edge")
            if security == "tls" {
                XCTAssertNil(grpc["authority"])
                XCTAssertEqual((stream["tlsSettings"] as? [String: Any])?["serverName"] as? String, p.host)
            } else {
                XCTAssertEqual(grpc["authority"] as? String, security == "reality" ? p.endpoint : p.host)
            }
            if security == "reality" {
                let reality = try XCTUnwrap(stream["realitySettings"] as? [String: Any])
                XCTAssertEqual(reality["serverName"] as? String, p.sni)
                XCTAssertEqual(reality["publicKey"] as? String, key)
            }
            p.grpcAuthority = "front.example.invalid:443"
            let explicit = try XCTUnwrap(try configuration(p)["grpcSettings"] as? [String: Any])
            XCTAssertEqual(explicit["authority"] as? String, p.grpcAuthority)
        }
    }

    func testHTTP2HostAndOtherProtocolsKeepTheirCredentials() throws {
        var h2 = try ProfileParser.parse("vless://\(uuid)@vpn.example.invalid:443?security=tls&type=h2&path=%2Fedge")
        let stream = try configuration(h2, emit: "resolved-h2")
        XCTAssertEqual((stream["httpSettings"] as? [String: Any])?["host"] as? [String], [h2.host])
        h2.hostHeader = "front.example.invalid"
        XCTAssertEqual((try configuration(h2)["httpSettings"] as? [String: Any])?["host"] as? [String], [h2.hostHeader])
        for link in ["trojan://password@vpn.example.invalid:443", "socks://user:password@vpn.example.invalid:1080",
                     "ss://" + Data("aes-128-gcm:password".utf8).base64EncodedString() + "@vpn.example.invalid:8388"] {
            let p = try ProfileParser.parse(link)
            let saved = p
            _ = try configuration(p)
            XCTAssertEqual(p, saved)
        }
    }

    func testOnlyNumericDialOverridesAreAccepted() throws {
        let p = try ProfileParser.parse("vless://\(uuid)@vpn.example.invalid:443?security=tls")
        for address in ["192.0.2.17", "2001:db8::17", "::1"] {
            XCTAssertTrue(XrayConfiguration.isIPAddress(address))
            XCTAssertNoThrow(try XrayConfiguration.make(profile: p, upstreamIP: address))
        }
        for address in ["", "second.example.invalid", "192.0.2.999", "192.0.2.1:443", "[2001:db8::1]", "192.0.2.1\n"] {
            XCTAssertFalse(XrayConfiguration.isIPAddress(address))
            XCTAssertThrowsError(try XrayConfiguration.make(profile: p, upstreamIP: address))
        }
    }
}
