import Foundation
import NetworkExtension
import Darwin

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let control = DispatchQueue(label: "incy.tunnel.control")
    private let io = DispatchQueue(label: "incy.tunnel.packets", qos: .userInitiated)
    private let worker = DispatchQueue(label: "incy.tunnel.hev", qos: .userInitiated)
    private let bootstrap = DispatchQueue(label: "incy.tunnel.bootstrap", qos: .userInitiated, attributes: .concurrent)
    private var appFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var active = false
    private var stopping = false
    private var engineStarted = false
    private var runID = UUID()
    private var packetGeneration = UUID()
    private var upload: UInt64 = 0
    private var download: UInt64 = 0
    private var dropped: UInt64 = 0
    private var forwardedIPv4: UInt64 = 0
    private var forwardedIPv6: UInt64 = 0
    private var returnedPackets: UInt64 = 0
    private var writeFailures: UInt64 = 0
    private var largestInput = 0
    private var largestOutput = 0
    private var diagnosticsTimer: DispatchSourceTimer?
    private var workerRunning = false
    private var startCompletion: ((Error?) -> Void)?
    private var stopCompletions = [() -> Void]()

    private final class BridgeContext {
        let provider: PacketTunnelProvider
        let token: UUID
        init(provider: PacketTunnelProvider, token: UUID) {
            self.provider = provider; self.token = token
        }
    }
    private static let onNativeReady: @convention(c) (UnsafeMutableRawPointer?) -> Void = { pointer in
        guard let pointer = pointer else { return }
        let context = Unmanaged<BridgeContext>.fromOpaque(pointer).takeUnretainedValue()
        context.provider.control.async { context.provider.bridgeDidStart(token: context.token) }
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        control.async {
            guard self.startCompletion == nil && !self.engineStarted && !self.workerRunning else {
                completionHandler(ProfileError.invalid("VPN уже запущен.")); return
            }
            self.startCompletion = completionHandler
            self.runID = UUID()
            let token = self.runID
            self.stopping = false
            try? ProfileVault.saveTunnelFailure(nil)
            do {
                guard let proto = self.protocolConfiguration as? NETunnelProviderProtocol,
                      let config = proto.providerConfiguration, let id = config["profileID"] as? String else {
                    throw ProfileError.invalid("Выберите профиль в приложении.")
                }
                let profile = try ProfileVault.load(id)
                let dns = config["dns"] as? String ?? "1.1.1.1"
                try profile.validate()
                NSLog("INCY phase=bootstrap protocol=%@ transport=%@ security=%@", profile.kind, profile.transport, profile.security)
                self.resolveServer(profile: profile, dns: dns, token: token)
            } catch { self.cleanupCore(); self.finishStart(error) }
        }
    }

    private func resolveServer(profile: Profile, dns: String, token: UUID) {
        bootstrap.async {
            let address: String? = profile.host.withCString { pointer in
                guard let host = strdup(pointer) else { return nil }
                defer { free(host) }
                guard let result = IncyXrayResolve(host, Int32(profile.port)) else { return nil }
                defer { IncyXrayFree(result) }
                return String(cString: result)
            }
            self.control.async {
                guard self.runID == token && !self.stopping && self.startCompletion != nil else { return }
                guard let ip = address, XrayConfiguration.isIPAddress(ip) else {
                    let dnsFailed = address == "DNS_FAILED"
                    NSLog("INCY phase=bootstrap-failed dns=%d", dnsFailed ? 1 : 0)
                    self.finishStart(ProfileError.invalid(dnsFailed
                        ? "Не удалось определить адрес VPN-сервера. Проверьте интернет без VPN или выберите другой сервер."
                        : "Не удалось связаться с VPN-сервером. Проверьте интернет без VPN или выберите другой сервер."))
                    return
                }
                do { try self.startCore(profile: profile, dns: dns, ip: ip, token: token) }
                catch { self.cleanupCore(); self.finishStart(error) }
            }
        }
    }

    private func startCore(profile: Profile, dns: String, ip: String, token: UUID) throws {
        let data = try XrayConfiguration.make(profile: profile, dns: dns, upstreamIP: ip)
        guard let json = String(data: data, encoding: .utf8), let cstring = strdup(json) else {
            throw ProfileError.invalid("Не удалось подготовить конфигурацию.")
        }
        defer { free(cstring) }
        if let error = IncyXrayStart(cstring) {
            IncyXrayFree(error)
            // Core errors may include credentials: never expose their raw text.
            throw ProfileError.invalid("Сетевое ядро не приняло профиль. Проверьте протокол и параметры сервера.")
        }
        engineStarted = true
        NSLog("INCY phase=proxy-check")
        bootstrap.async {
            let result = IncyXrayProbe(Int32(XrayConfiguration.socksPort))
            self.control.async {
                guard self.runID == token && !self.stopping && self.engineStarted && self.startCompletion != nil else { return }
                NSLog("INCY phase=proxy-check-finished result=%d", result)
                guard result == 0 else {
                    self.cleanupCore()
                    self.finishStart(ProfileError.invalid("Сервер не передаёт данные через VPN. Выберите другой сервер в подписке или проверьте параметры профиля."))
                    return
                }
                self.applySettings(dns: dns, ip: ip, token: token)
            }
        }
    }

    private func applySettings(dns: String, ip: String, token: UUID) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: ip)
        settings.mtu = 1280
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        let ipv6 = NEIPv6Settings(addresses: ["fd00:1::1"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6
        let dnsSettings = NEDNSSettings(servers: [dns])
        dnsSettings.matchDomains = [""]
        settings.dnsSettings = dnsSettings
        // Provider sockets bypass its own VPN. Only bootstrap DNS and the
        // selected server TCP connection run before routes are installed.
        NSLog("INCY phase=network-settings")
        setTunnelNetworkSettings(settings) { error in
            self.control.async {
                guard self.runID == token && !self.stopping && self.engineStarted else { return }
                if let error = error { self.cleanupCore(); self.finishStart(error); return }
                self.launchBridge(token: token)
            }
        }
    }

    private func launchBridge(token: UUID) {
        var fds: [Int32] = [-1, -1]
        guard incy_socket_pair(&fds) == 0 else {
            cleanupCore(); finishStart(ProfileError.invalid("Не удалось создать канал пакетов.")); return
        }
        guard incy_tunnel_prepare() == 0 else {
            Darwin.close(fds[0]); Darwin.close(fds[1])
            cleanupCore(); finishStart(ProfileError.invalid("Предыдущее соединение ещё завершается.")); return
        }
        appFD = fds[0]
        let descriptor = fds[1]
        io.sync {
            active = true; upload = 0; download = 0; dropped = 0
            forwardedIPv4 = 0; forwardedIPv6 = 0; returnedPackets = 0; writeFailures = 0
            largestInput = 0; largestOutput = 0
            packetGeneration = token
            let readSource = DispatchSource.makeReadSource(fileDescriptor: appFD, queue: io)
            readSource.setEventHandler { [weak self] in self?.receivePackets() }
            // Descriptors close after all queued reads finish, avoiding reuse races.
            let localFD = appFD
            readSource.setCancelHandler { Darwin.close(localFD) }
            source = readSource; readSource.resume()
            let timer = DispatchSource.makeTimerSource(queue: io)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in self?.logPacketCounts() }
            diagnosticsTimer = timer; timer.resume()
        }
        workerRunning = true
        let context = BridgeContext(provider: self, token: token)
        worker.async {
            let yaml = """
            tunnel:
              mtu: 1280
              ipv4: 198.18.0.1
              ipv6: 'fd00:1::1'
            socks5:
              address: 127.0.0.1
              port: \(XrayConfiguration.socksPort)
              udp: 'udp'
            misc:
              task-stack-size: 24576
              tcp-buffer-size: 4096
              udp-recv-buffer-size: 32768
              udp-copy-buffer-nums: 2
              max-session-count: 48
              connect-timeout: 8000
              tcp-read-write-timeout: 120000
              udp-read-write-timeout: 30000
              log-file: null
              log-level: error
            """
            let bytes = Array(yaml.utf8)
            let result = bytes.withUnsafeBufferPointer { buffer in
                incy_tunnel_run(buffer.baseAddress, UInt32(buffer.count), descriptor,
                                PacketTunnelProvider.onNativeReady, Unmanaged.passUnretained(context).toOpaque())
            }
            Darwin.close(descriptor)
            self.control.async { self.bridgeDidFinish(token: token, result: result) }
        }
    }

    private func bridgeDidStart(token: UUID) {
        guard runID == token && !stopping && workerRunning && startCompletion != nil else { return }
        NSLog("INCY phase=bridge-ready")
        io.async {
            guard self.active && self.packetGeneration == token else { return }
            self.readPackets(token: token)
        }
        finishStart(nil)
    }

    private func bridgeDidFinish(token: UUID, result: Int32) {
        guard runID == token else { return }
        workerRunning = false
        stopBridge(); cleanupCore()
        if !stopping {
            let error = ProfileError.invalid("Канал VPN завершился (\(result)).")
            if startCompletion != nil { finishStart(error) }
            else { recordFailure(error); cancelTunnelWithError(error) }
        }
        let completions = stopCompletions; stopCompletions.removeAll()
        for completion in completions { completion() }
    }

    private func finishStart(_ error: Error?) {
        if let error = error, !stopping { recordFailure(error) }
        let completion = startCompletion; startCompletion = nil
        completion?(error)
    }

    private func recordFailure(_ error: Error) {
        NSLog("INCY phase=start-failed")
        try? ProfileVault.saveTunnelFailure(VPNErrorMessage.describe(error))
    }

    private func logPacketCounts() {
        NSLog("INCY packets up=%llu down=%llu dropped=%llu ipv4=%llu ipv6=%llu returned=%llu writeFailures=%llu maxIn=%ld maxOut=%ld",
              upload, download, dropped, forwardedIPv4, forwardedIPv6, returnedPackets, writeFailures, largestInput, largestOutput)
    }

    private func readPackets(token: UUID) {
        guard active && packetGeneration == token else { return }
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }
            self.io.async {
                guard self.active && self.packetGeneration == token else { return }
                for (packet, family) in zip(packets, protocols) {
                    self.largestInput = max(self.largestInput, packet.count)
                    let sent = packet.withUnsafeBytes { bytes in
                        incy_send_packet(self.appFD, bytes.baseAddress, bytes.count, family.int32Value)
                    }
                    if sent == 0 {
                        self.upload += UInt64(packet.count)
                        if family.int32Value == AF_INET { self.forwardedIPv4 += 1 }
                        else if family.int32Value == AF_INET6 { self.forwardedIPv6 += 1 }
                    } else { self.dropped += 1 }
                }
                self.readPackets(token: token)
            }
        }
    }

    private func receivePackets() {
        guard active else { return }
        var buffer = [UInt8](repeating: 0, count: 65536)
        var packets = [Data](); var protocols = [NSNumber]()
        for _ in 0..<64 {
            var family: Int32 = 0
            let count = buffer.withUnsafeMutableBytes { bytes in
                incy_receive_packet(appFD, bytes.baseAddress, bytes.count, &family)
            }
            if count <= 0 { break }
            packets.append(Data(buffer.prefix(Int(count)))); protocols.append(NSNumber(value: family))
            download += UInt64(count)
            returnedPackets += 1; largestOutput = max(largestOutput, Int(count))
        }
        if !packets.isEmpty && !packetFlow.writePackets(packets, withProtocols: protocols) { writeFailures += UInt64(packets.count) }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        control.async {
            self.stopping = true
            NSLog("INCY phase=stop reason=%ld", reason.rawValue)
            self.finishStart(ProfileError.invalid("Подключение отменено."))
            self.stopBridge()
            if self.workerRunning {
                self.stopCompletions.append(completionHandler)
                incy_tunnel_stop()
            } else { self.cleanupCore(); completionHandler() }
        }
    }
    private func stopBridge() {
        io.sync {
            if active { logPacketCounts() }
            active = false; diagnosticsTimer?.cancel(); diagnosticsTimer = nil
            source?.cancel(); source = nil; appFD = -1
        }
    }
    private func cleanupCore() {
        if engineStarted { IncyXrayStop(); engineStarted = false }
    }
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard messageData == Data("stats".utf8) else { completionHandler?(nil); return }
        io.async {
            let payload: [String: UInt64] = ["upload": self.upload, "download": self.download, "dropped": self.dropped]
            completionHandler?(try? JSONSerialization.data(withJSONObject: payload))
        }
    }
}

