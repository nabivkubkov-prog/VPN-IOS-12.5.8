import Foundation

public enum ProfileError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public struct Profile: Codable, Equatable {
    public var id = UUID().uuidString
    public var name: String
    public var kind: String
    public var host: String
    public var port: Int
    public var credential: String
    public var username = ""
    public var method = ""
    public var security = "none"
    public var sni = ""
    public var publicKey = ""
    public var shortID = ""
    public var fingerprint = "chrome"
    public var alpn = [String]()
    public var spiderX = "/"
    public var flow = ""
    public var transport = "tcp"
    public var path = "/"
    public var hostHeader = ""
    public var serviceName = ""
    public var alterID = 0

    public init(name: String, kind: String, host: String, port: Int, credential: String) {
        self.name = name; self.kind = kind; self.host = host
        self.port = port; self.credential = credential
    }

    public var badge: String {
        kind == "vless" && security == "reality" ? "VLESS · REALITY" : kind.uppercased()
    }
    public var endpoint: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }

    public func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ProfileError.invalid(message) }
        }
        try require(["vless", "vmess", "trojan", "ss", "socks", "http"].contains(kind), "Протокол не поддерживается.")
        try require(!host.isEmpty && host.utf8.count <= 253 && !host.contains(where: { $0.isWhitespace }) && !host.contains("/") && !host.contains("@"), "Некорректный адрес сервера.")
        try require((1...65535).contains(port), "Порт должен быть от 1 до 65535.")
        try require(["tcp", "ws", "grpc", "h2"].contains(transport), "Поддерживаются TCP, WebSocket, gRPC и HTTP/2.")
        try require(["none", "tls", "reality"].contains(security), "Тип шифрования не поддерживается.")
        try require(["chrome", "firefox", "safari", "ios", "android", "edge", "random", "randomized"].contains(fingerprint), "Неизвестный TLS fingerprint.")
        if kind == "vless" || kind == "vmess" {
            try require(UUID(uuidString: credential) != nil, "Укажите корректный UUID.")
        }
        if kind == "vmess" { try require(alterID == 0, "Поддерживается только VMess AEAD (alterId=0).") }
        if kind == "trojan" || kind == "ss" {
            try require(!credential.isEmpty, "Не указан пароль.")
        }
        if kind == "trojan" { try require(security == "tls", "Trojan требует TLS.") }
        if kind == "ss" {
            try require(["aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305"].contains(method), "Метод Shadowsocks не поддерживается.")
            if method.hasPrefix("2022-") {
                let length = method == "2022-blake3-aes-128-gcm" ? 16 : 32
                try require(credential.split(separator: ":", omittingEmptySubsequences: false).allSatisfy { Data(base64Encoded: String($0))?.count == length }, "SS2022: неверный размер base64-ключа.")
            }
        }
        if ["ss", "socks", "http"].contains(kind) {
            try require(transport == "tcp", "Этот протокол использует TCP.")
            try require(security != "reality", "Reality доступен только для VLESS.")
        }
        if security == "reality" {
            try require(kind == "vless" && transport == "tcp", "Reality поддерживается для VLESS TCP.")
            try require(!sni.isEmpty, "Reality: отсутствует serverName (sni).")
            try require(publicKey.count == 43 && publicKey.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } && ProfileParser.decodeBase64(publicKey)?.count == 32, "Reality: public key должен содержать 32 байта в base64url без padding.")
            try require(shortID.count <= 16 && shortID.count % 2 == 0 && shortID.allSatisfy { $0.isHexDigit }, "Reality: shortId — до 16 шестнадцатеричных символов, чётная длина.")
        }
        try require(flow.isEmpty || (kind == "vless" && transport == "tcp" && security != "none" && flow == "xtls-rprx-vision"), "Flow поддерживается только xtls-rprx-vision с VLESS TCP TLS/Reality.")
        try require(alpn.allSatisfy { ["h2", "http/1.1"].contains($0) }, "Поддерживаются ALPN h2 и http/1.1.")
        try require(spiderX.hasPrefix("/"), "Reality: spiderX должен начинаться с /.")
        try require(name.utf8.count <= 256 && credential.utf8.count <= 4096, "Слишком длинное имя или пароль.")
    }
}

public enum ProfileParser {
    public static func decodeBase64(_ value: String) -> Data? {
        var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }

    public static func parse(_ text: String) throws -> Profile {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.utf8.count <= 32768 else { throw ProfileError.invalid("Ссылка слишком длинная.") }
        if raw.lowercased().hasPrefix("vmess://") { return try vmess(raw) }
        if raw.lowercased().hasPrefix("ss://") { return try shadowsocks(raw) }
        guard let c = URLComponents(string: raw), let originalScheme = c.scheme else {
            throw ProfileError.invalid("Вставьте ссылку vless://, vmess://, trojan://, ss://, socks:// или http://.")
        }
        let kind = originalScheme.lowercased() == "socks5" ? "socks" : originalScheme.lowercased()
        guard ["vless", "trojan", "socks", "http"].contains(kind), let urlHost = c.host else {
            throw ProfileError.invalid("Неизвестная или неполная ссылка.")
        }
        var query = [String: String]()
        for item in c.queryItems ?? [] {
            guard query[item.name] == nil else { throw ProfileError.invalid("Повторяющийся параметр: \(item.name).") }
            query[item.name] = item.value ?? ""
        }
        for key in ["allowInsecure", "insecure", "skip-cert-verify"] {
            if let v = query[key], v != "0" && v != "false" { throw ProfileError.invalid("Отключение проверки TLS-сертификата не поддерживается.") }
        }
        if let encryption = query["encryption"], kind == "vless", encryption != "none" {
            throw ProfileError.invalid("VLESS: поддерживается encryption=none.")
        }
        if let header = query["headerType"], header != "none" { throw ProfileError.invalid("TCP headerType не поддерживается.") }
        if let mode = query["mode"], mode != "gun" { throw ProfileError.invalid("Поддерживается gRPC mode=gun.") }
        if query["plugin"] != nil || query["ech"] != nil { throw ProfileError.invalid("Plugin/ECH не поддерживаются этим ядром.") }
        if query["ed"] != nil || query["packetEncoding"] != nil { throw ProfileError.invalid("WS early data и нестандартный packetEncoding не поддерживаются.") }
        let host = urlHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        var p = Profile(name: c.fragment.flatMap { $0.isEmpty ? nil : $0 } ?? host,
                        kind: kind, host: host, port: c.port ?? (kind == "socks" ? 1080 : 443),
                        credential: kind == "socks" || kind == "http" ? (c.password ?? "") : (c.user ?? ""))
        p.username = kind == "socks" || kind == "http" ? (c.user ?? "") : ""
        p.security = query["security"] ?? (kind == "trojan" ? "tls" : "none")
        p.sni = query["sni"] ?? query["serverName"] ?? ""
        p.publicKey = query["pbk"] ?? ""; p.shortID = query["sid"] ?? ""
        p.fingerprint = query["fp"] ?? "chrome"; p.flow = query["flow"] ?? ""
        p.alpn = (query["alpn"] ?? "").split(separator: ",").map(String.init)
        p.spiderX = query["spx"] ?? "/"
        p.transport = query["type"] ?? "tcp"
        if p.transport == "http" { p.transport = "h2" }
        p.path = query["path"] ?? "/"; p.hostHeader = query["host"] ?? ""
        p.serviceName = query["serviceName"] ?? ""
        try p.validate(); return p
    }

    private static func vmess(_ raw: String) throws -> Profile {
        guard let data = decodeBase64(String(raw.dropFirst(8))),
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProfileError.invalid("VMess: некорректный base64 JSON.")
        }
        func string(_ key: String, _ fallback: String = "") -> String {
            if let s = j[key] as? String { return s }; if let n = j[key] as? NSNumber { return n.stringValue }; return fallback
        }
        guard let port = Int(string("port")) else { throw ProfileError.invalid("VMess: отсутствует порт.") }
        guard ["auto", "", "aes-128-gcm", "chacha20-poly1305"].contains(string("scy")) else { throw ProfileError.invalid("VMess: поддерживается scy=auto или AEAD.") }
        guard ["", "none"].contains(string("type")), !["true", "1"].contains(string("allowInsecure")) else { throw ProfileError.invalid("VMess: нестандартные заголовки или insecure TLS не поддерживаются.") }
        var p = Profile(name: string("ps", string("add")), kind: "vmess", host: string("add"), port: port, credential: string("id"))
        guard let aid = Int(string("aid", "0")) else { throw ProfileError.invalid("VMess: некорректный alterId.") }
        p.alterID = aid; p.transport = string("net", "tcp")
        if p.transport == "http" { p.transport = "h2" }
        p.security = string("tls").isEmpty ? "none" : string("tls")
        p.sni = string("sni", string("host")); p.hostHeader = string("host")
        p.path = string("path", "/"); p.serviceName = string("path")
        p.fingerprint = string("fp", "chrome")
        p.alpn = string("alpn").split(separator: ",").map(String.init)
        try p.validate(); return p
    }

    private static func shadowsocks(_ raw: String) throws -> Profile {
        var body = String(raw.dropFirst(5))
        let pieces = body.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let name = pieces.count == 2 ? (String(pieces[1]).removingPercentEncoding ?? String(pieces[1])) : "Shadowsocks"
        body = String(pieces[0])
        guard !body.contains("?plugin="), !body.contains("&plugin=") else { throw ProfileError.invalid("Shadowsocks plugins не поддерживаются.") }
        body = String(body.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        if !body.contains("@") {
            guard let data = decodeBase64(body), let decoded = String(data: data, encoding: .utf8) else { throw ProfileError.invalid("Некорректная ссылка Shadowsocks.") }
            body = decoded
        }
        guard let at = body.lastIndex(of: "@"), let endpoint = URLComponents(string: "ss://" + body[body.index(after: at)...]),
              let urlHost = endpoint.host, let port = endpoint.port else { throw ProfileError.invalid("Shadowsocks: отсутствует сервер или порт.") }
        let user = String(body[..<at]).removingPercentEncoding ?? String(body[..<at])
        let credentials: String
        if user.contains(":") { credentials = user }
        else if let data = decodeBase64(user), let decoded = String(data: data, encoding: .utf8) { credentials = decoded }
        else { throw ProfileError.invalid("Shadowsocks: неверные учётные данные.") }
        guard let colon = credentials.firstIndex(of: ":") else { throw ProfileError.invalid("Shadowsocks: отсутствует метод.") }
        var p = Profile(name: name, kind: "ss", host: urlHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")), port: port,
                        credential: String(credentials[credentials.index(after: colon)...]))
        p.method = String(credentials[..<colon]); try p.validate(); return p
    }

    public static func parseBatch(_ text: String) throws -> [Profile] {
        guard text.utf8.count <= 1_048_576 else { throw ProfileError.invalid("Подписка больше 1 МБ.") }
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.contains("://"), let data = decodeBase64(input.filter { !$0.isWhitespace }), let decoded = String(data: data, encoding: .utf8) { input = decoded }
        let lines = input.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !lines.isEmpty, lines.count <= 256 else { throw ProfileError.invalid("Подписка должна содержать от 1 до 256 ссылок.") }
        return try lines.enumerated().map { offset, line in
            do { return try parse(line) } catch { throw ProfileError.invalid("Строка \(offset + 1): \(error.localizedDescription)") }
        }
    }
}

