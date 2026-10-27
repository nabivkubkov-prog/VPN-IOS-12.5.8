import Foundation
import NetworkExtension
import Darwin

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let control = DispatchQueue(label: "incy.tunnel.control")
    private let io = DispatchQueue(label: "incy.tunnel.packets", qos: .userInitiated)
    private let worker = DispatchQueue(label: "incy.tunnel.hev", qos: .userInitiated)
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
            do {
                guard let proto = self.protocolConfiguration as? NETunnelProviderProtocol,
                      let config = proto.providerConfiguration, let id = config["profileID"] as? String else {
                    throw ProfileError.invalid("Выберите профиль в приложении.")
                }
                let profile = try ProfileVault.load(id)
                let dns = config["dns"] as? String ?? "1.1.1.1"
                let data = try XrayConfiguration.make(profile: profile, dns: dns)
                guard let json = String(data: data, encoding: .utf8), let cstring = strdup(json) else {
                    throw ProfileError.invalid("Не удалось подготовить конфигурацию.")
                }
                defer { free(cstring) }
                if let error = IncyXrayStart(cstring) {
                    IncyXrayFree(error)
                    // Core errors may include credentials: never expose their raw text.
                    throw ProfileError.invalid("Сетевое ядро не приняло профиль. Проверьте протокол и параметры сервера.")
                }
                self.engineStarted = true
                let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
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
                // Outbound sockets originate in the provider process and bypass its VPN,
                // as specified by NetworkExtension. No broad server/LAN route exemptions.
                self.setTunnelNetworkSettings(settings) { error in
                    self.control.async {
                        guard self.runID == token && !self.stopping else { return }
                        if let error = error { self.cleanupCore(); self.finishStart(error); return }
                        self.launchBridge(token: token)
                    }
                }
            } catch { self.cleanupCore(); self.finishStart(error) }
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
            packetGeneration = token
            let readSource = DispatchSource.makeReadSource(fileDescriptor: appFD, queue: io)
            readSource.setEventHandler { [weak self] in self?.receivePackets() }
            // Descriptors close after all queued reads finish, avoiding reuse races.
            let localFD = appFD
            readSource.setCancelHandler { Darwin.close(localFD) }
            source = readSource; readSource.resume()
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
            else { cancelTunnelWithError(error) }
        }
        let completions = stopCompletions; stopCompletions.removeAll()
        for completion in completions { completion() }
    }

    private func finishStart(_ error: Error?) {
        let completion = startCompletion; startCompletion = nil
        completion?(error)
    }

    private func readPackets(token: UUID) {
        guard active && packetGeneration == token else { return }
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }
            self.io.async {
                guard self.active && self.packetGeneration == token else { return }
                for (packet, family) in zip(packets, protocols) {
                    let sent = packet.withUnsafeBytes { bytes in
                        incy_send_packet(self.appFD, bytes.baseAddress, bytes.count, family.int32Value)
                    }
                    if sent == 0 { self.upload += UInt64(packet.count) } else { self.dropped += 1 }
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
        }
        if !packets.isEmpty { _ = packetFlow.writePackets(packets, withProtocols: protocols) }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        control.async {
            self.stopping = true
            self.finishStart(ProfileError.invalid("Подключение отменено."))
            self.stopBridge()
            if self.workerRunning {
                self.stopCompletions.append(completionHandler)
                incy_tunnel_stop()
            } else { self.cleanupCore(); completionHandler() }
        }
    }
    private func stopBridge() {
        io.sync { active = false; source?.cancel(); source = nil; appFD = -1 }
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

