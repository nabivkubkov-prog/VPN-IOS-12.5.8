import XCTest
@testable import IncyProfiles

final class ProfileTests: XCTestCase {
    func testExamplesAndEmitConfigsForNativeValidation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Examples/profiles.txt"), encoding: .utf8)
        let profiles = try ProfileParser.parseBatch(text)
        XCTAssertEqual(profiles.count, 7)
        for (index, p) in profiles.enumerated() {
            let data = try XrayConfiguration.make(profile: p)
            XCTAssertTrue(data.count > 0)
            if let directory = ProcessInfo.processInfo.environment["INCY_CONFIG_OUTPUT"] {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try data.write(to: url.appendingPathComponent("\(index)-\(p.kind).json"))
            }
        }
    }
    private let key = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"
    private var reality: String { "vless://11111111-1111-4111-8111-111111111111@192.0.2.1:443?security=reality&sni=www.example.com&fp=chrome&pbk=\(key)&sid=abcd&flow=xtls-rprx-vision&type=tcp#Reality" }
    func testRealityParametersAndNoDirectFallback() throws {
        let p = try ProfileParser.parse(reality)
        XCTAssertEqual(p.publicKey, key); XCTAssertEqual(p.shortID, "abcd")
        XCTAssertEqual(p.flow, "xtls-rprx-vision"); XCTAssertEqual(p.badge, "VLESS · REALITY")
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: XrayConfiguration.make(profile: p)) as? [String: Any])
        let outbounds = try XCTUnwrap(j["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.count, 1); XCTAssertEqual(outbounds[0]["protocol"] as? String, "vless")
        let stream = try XCTUnwrap(outbounds[0]["streamSettings"] as? [String: Any])
        XCTAssertEqual(stream["security"] as? String, "reality")
        XCTAssertNil(j["routing"])
    }
    func testNativeIPv6LoopbackAndHTTPDNSRouting() throws {
        let p = try ProfileParser.parse("http://192.0.2.1:8080#HTTP")
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: XrayConfiguration.make(profile: p)) as? [String: Any])
        let inbounds = try XCTUnwrap(j["inbounds"] as? [[String: Any]])
        XCTAssertEqual(inbounds.count, 2)
        XCTAssertEqual(Set(inbounds.compactMap { $0["listen"] as? String }), ["127.0.0.1", "::1"])
        for inbound in inbounds {
            let settings = try XCTUnwrap(inbound["settings"] as? [String: Any])
            XCTAssertEqual(settings["ip"] as? String, inbound["listen"] as? String)
            XCTAssertEqual(settings["udp"] as? Bool, true)
        }
        let routing = try XCTUnwrap(j["routing"] as? [String: Any])
        let rules = try XCTUnwrap(routing["rules"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(rules.first?["inboundTag"] as? [String])),
                       Set(inbounds.compactMap { $0["tag"] as? String }))
    }
    func testInvalidRealityAndInsecureTLSRejected() {
        XCTAssertThrowsError(try ProfileParser.parse(reality.replacingOccurrences(of: key, with: "invalid")))
        XCTAssertThrowsError(try ProfileParser.parse(reality.replacingOccurrences(of: "sid=abcd", with: "sid=abc")))
        XCTAssertThrowsError(try ProfileParser.parse(reality.replacingOccurrences(of: "type=tcp", with: "type=ws")))
        XCTAssertThrowsError(try ProfileParser.parse(reality.replacingOccurrences(of: "security=reality", with: "security=reality&security=tls")))
        XCTAssertThrowsError(try ProfileParser.parse("trojan://password@example.com:443?allowInsecure=1"))
    }
    func testIPv6AndEscapedPasswords() throws {
        let p = try ProfileParser.parse("trojan://pa%3Ass%40word@[2001:db8::1]:443?sni=example.com#Test%20IPv6")
        XCTAssertEqual(p.host, "2001:db8::1"); XCTAssertEqual(p.credential, "pa:ss@word")
        XCTAssertEqual(p.name, "Test IPv6"); XCTAssertEqual(p.security, "tls")
    }
    func testShadowsocksSIP002AndLegacy() throws {
        let credentials = Data("aes-128-gcm:pa:ss@word".utf8).base64EncodedString()
        let p = try ProfileParser.parse("ss://\(credentials)@192.0.2.2:8388#SS")
        XCTAssertEqual(p.method, "aes-128-gcm"); XCTAssertEqual(p.credential, "pa:ss@word")
        let legacy = Data("aes-128-gcm:password@192.0.2.2:8388".utf8).base64EncodedString()
        XCTAssertEqual(try ProfileParser.parse("ss://\(legacy)").port, 8388)
        XCTAssertThrowsError(try ProfileParser.parse("ss://\(credentials)@192.0.2.2:8388?plugin=v2ray-plugin"))
    }
    func testVMessAEADAndEncodedSubscription() throws {
        let json = "{\"add\":\"192.0.2.1\",\"port\":443,\"id\":\"11111111-1111-4111-8111-111111111111\",\"aid\":0,\"net\":\"ws\",\"tls\":\"tls\",\"path\":\"/ws\"}"
        let link = "vmess://" + Data(json.utf8).base64EncodedString()
        XCTAssertEqual(try ProfileParser.parse(link).transport, "ws")
        let text = Data((reality + "\n" + link).utf8).base64EncodedString()
        XCTAssertEqual(try ProfileParser.parseBatch(text).count, 2)
        let legacy = "vmess://" + Data(json.replacingOccurrences(of: "\"aid\":0", with: "\"aid\":64").utf8).base64EncodedString()
        XCTAssertThrowsError(try ProfileParser.parse(legacy))
    }
    func testBatchIsAtomicAndBounded() {
        XCTAssertThrowsError(try ProfileParser.parseBatch(reality + "\nnot-a-profile"))
        XCTAssertThrowsError(try ProfileParser.parseBatch(String(repeating: "a", count: 1_048_577)))
        XCTAssertThrowsError(try ProfileParser.parseBatch(Array(repeating: reality, count: 257).joined(separator: "\n")))
    }
    func testJSONEscapingAndTLSValidation() throws {
        var p = try ProfileParser.parse("trojan://password@192.0.2.1:443?sni=example.com")
        p.credential = "a\"b\\c\n"
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: XrayConfiguration.make(profile: p)) as? [String: Any])
        let out = try XCTUnwrap((j["outbounds"] as? [[String: Any]])?.first)
        let settings = try XCTUnwrap(out["settings"] as? [String: Any])
        let server = try XCTUnwrap((settings["servers"] as? [[String: Any]])?.first)
        XCTAssertEqual(server["password"] as? String, p.credential)
        let stream = try XCTUnwrap(out["streamSettings"] as? [String: Any])
        let tls = try XCTUnwrap(stream["tlsSettings"] as? [String: Any])
        XCTAssertEqual(tls["allowInsecure"] as? Bool, false)
    }
}

