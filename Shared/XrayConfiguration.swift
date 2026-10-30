import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum XrayConfiguration {
    public static let socksPort = 10808
    // HEV uses AF_INET6 sockets. Native IPv6 loopback avoids iOS 12
    // NetworkExtension rejecting IPv4-mapped loopback with EADDRNOTAVAIL.
    public static let bridgeAddress = "::1"
    public static func make(profile p: Profile, dns: String = "1.1.1.1", upstreamIP: String? = nil) throws -> Data {
        try p.validate()
        guard ["1.1.1.1", "8.8.8.8", "9.9.9.9"].contains(dns) else { throw ProfileError.invalid("Выберите DNS из списка.") }
        if let ip = upstreamIP, !isIPAddress(ip) { throw ProfileError.invalid("Не удалось определить IP сервера.") }
        // Resolve the dial address before installing VPN DNS/routes. Keep the
        // original profile for certificate names and transport virtual hosts.
        let address = upstreamIP ?? p.host
        var settings: [String: Any]
        let protocolName: String
        switch p.kind {
        case "vless", "vmess":
            protocolName = p.kind
            var user: [String: Any] = ["id": p.credential, "level": 0]
            if p.kind == "vless" { user["encryption"] = "none"; if !p.flow.isEmpty { user["flow"] = p.flow } }
            else { user["security"] = "auto"; user["alterId"] = 0 }
            settings = ["vnext": [["address": address, "port": p.port, "users": [user]]]]
        case "trojan", "ss":
            protocolName = p.kind == "ss" ? "shadowsocks" : "trojan"
            var server: [String: Any] = ["address": address, "port": p.port, "password": p.credential, "level": 0]
            if p.kind == "ss" { server["method"] = p.method }
            settings = ["servers": [server]]
        default:
            protocolName = p.kind
            var server: [String: Any] = ["address": address, "port": p.port]
            if !p.username.isEmpty { server["users"] = [["user": p.username, "pass": p.credential]] }
            settings = ["servers": [server]]
        }
        let network = p.transport == "h2" ? "http" : p.transport
        var stream: [String: Any] = ["network": network, "security": p.security]
        if p.security == "reality" {
            stream["realitySettings"] = ["serverName": p.sni, "fingerprint": p.fingerprint, "publicKey": p.publicKey, "shortId": p.shortID, "spiderX": p.spiderX]
        } else if p.security == "tls" {
            stream["tlsSettings"] = ["serverName": p.sni.isEmpty ? p.host : p.sni, "allowInsecure": false, "fingerprint": p.fingerprint]
            if !p.alpn.isEmpty {
                var tls = stream["tlsSettings"] as! [String: Any]; tls["alpn"] = p.alpn; stream["tlsSettings"] = tls
            }
        }
        if p.transport == "ws" {
            var host = p.hostHeader
            if host.isEmpty && address != p.host {
                let defaultPort = p.security == "tls" ? 443 : 80
                host = p.port == defaultPort ? (p.host.contains(":") ? "[\(p.host)]" : p.host) : p.endpoint
            }
            stream["wsSettings"] = ["path": p.path, "headers": host.isEmpty ? [:] : ["Host": host]]
        }
        if p.transport == "grpc" {
            var grpc: [String: Any] = ["serviceName": p.serviceName, "multiMode": p.grpcMultiMode ?? false]
            if let authority = p.grpcAuthority, !authority.isEmpty { grpc["authority"] = authority }
            else if address != p.host && p.security != "tls" {
                // Xray 1.8.24 uses the domain alone without security, and the
                // original dial endpoint as gRPC's default with REALITY.
                grpc["authority"] = p.security == "reality" ? p.endpoint : p.host
            }
            stream["grpcSettings"] = grpc
        }
        if p.transport == "h2" { stream["httpSettings"] = ["path": p.path, "host": [p.hostHeader.isEmpty ? p.host : p.hostHeader]] }
        // Only one outbound: DNS packets and all destinations go through the selected proxy.
        // No direct fallback is added when the proxy fails.
        var j: [String: Any] = [
            "log": ["loglevel": "none"],
            "inbounds": [
                ["tag": "tun-socks", "listen": "127.0.0.1", "port": socksPort, "protocol": "socks", "settings": ["auth": "noauth", "udp": true, "ip": "127.0.0.1"], "sniffing": ["enabled": false]],
                ["tag": "tun-socks-v6", "listen": bridgeAddress, "port": socksPort, "protocol": "socks", "settings": ["auth": "noauth", "udp": true, "ip": bridgeAddress], "sniffing": ["enabled": false]]
            ],
            "outbounds": [["tag": "proxy", "protocol": protocolName, "settings": settings, "streamSettings": stream, "mux": ["enabled": false]]],
            "policy": ["levels": ["0": ["handshake": 8, "connIdle": 120, "uplinkOnly": 2, "downlinkOnly": 2, "bufferSize": 4]]]
        ]
        if p.kind == "http" {
            // HTTP CONNECT cannot carry UDP. Resolve A/AAAA using proxied DoH;
            // other DNS queries use TCP through the same HTTP outbound.
            let doh = dns == "8.8.8.8" ? "https://dns.google/dns-query" : dns == "9.9.9.9" ? "https://dns.quad9.net/dns-query" : "https://1.1.1.1/dns-query"
            j["dns"] = ["servers": [doh], "disableCache": true, "tag": "dns-query"]
            var outbounds = j["outbounds"] as! [[String: Any]]
            outbounds.append(["tag": "dns-out", "protocol": "dns", "settings": ["network": "tcp", "address": dns, "port": 53, "nonIPQuery": "skip"], "proxySettings": ["tag": "proxy"]])
            j["outbounds"] = outbounds
            j["routing"] = ["domainStrategy": "AsIs", "rules": [["type": "field", "inboundTag": ["tun-socks", "tun-socks-v6"], "port": "53", "outboundTag": "dns-out"]]]
        }
        return try JSONSerialization.data(withJSONObject: j, options: [.sortedKeys])
    }

    public static func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr(); var ipv6 = in6_addr()
        return value.withCString { inet_pton(AF_INET, $0, &ipv4) == 1 || inet_pton(AF_INET6, $0, &ipv6) == 1 }
    }
}

