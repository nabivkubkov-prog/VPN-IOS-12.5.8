import Foundation
import NetworkExtension

final class VPNController {
    static let shared = VPNController()
    private(set) var manager: NETunnelProviderManager?
    private(set) var configuring = false
    private var statusObserver: NSObjectProtocol?
    var status: NEVPNStatus { configuring ? .connecting : (manager?.connection.status ?? .disconnected) }
    var isBusy: Bool { [.connecting, .connected, .reasserting, .disconnecting].contains(status) }
    private init() {
        statusObserver = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] _ in self?.changed() }
        load { _ in }
    }
    private var providerID: String { (Bundle.main.bundleIdentifier ?? "app.incy.legacy") + ".PacketTunnel" }
    private func load(_ completion: @escaping (Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            DispatchQueue.main.async {
                if error == nil { self.manager = managers?.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.providerID } }
                self.changed(); completion(error)
            }
        }
    }
    func toggle() {
        guard !configuring else { return }
        if isBusy { manager?.connection.stopVPNTunnel(); return }
        guard let p = ProfileStore.shared.selected else { report("Сначала добавьте профиль сервера."); return }
        configuring = true; changed()
        load { error in
            if let error = error { self.finish(error); return }
            let manager = self.manager ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = self.providerID
            proto.serverAddress = p.host
            proto.providerConfiguration = ["profileID": p.id, "dns": ProfileStore.shared.dns]
            proto.disconnectOnSleep = false
            manager.protocolConfiguration = proto
            manager.localizedDescription = "INCY · \(p.name)"
            manager.isEnabled = true
            manager.isOnDemandEnabled = false
            manager.saveToPreferences { error in
                if let error = error { DispatchQueue.main.async { self.finish(error) }; return }
                manager.loadFromPreferences { error in
                    DispatchQueue.main.async {
                        if let error = error { self.finish(error); return }
                        self.manager = manager
                        do { try manager.connection.startVPNTunnel(); self.finish(nil) }
                        catch { self.finish(error) }
                    }
                }
            }
        }
    }
    func statistics(_ completion: @escaping (UInt64, UInt64) -> Void) {
        guard status == .connected, let session = manager?.connection as? NETunnelProviderSession else { completion(0, 0); return }
        do {
            try session.sendProviderMessage(Data("stats".utf8)) { data in
                let values = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: NSNumber] }
                DispatchQueue.main.async { completion(values?["upload"]?.uint64Value ?? 0, values?["download"]?.uint64Value ?? 0) }
            }
        } catch { completion(0, 0) }
    }
    private func finish(_ error: Error?) {
        configuring = false; changed()
        if let error = error { report(VPNErrorMessage.describe(error)) }
    }
    private func changed() { NotificationCenter.default.post(name: .vpnChanged, object: nil) }
    private func report(_ message: String) { NotificationCenter.default.post(name: .vpnError, object: message) }
}

