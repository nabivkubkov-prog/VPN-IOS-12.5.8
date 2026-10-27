import UIKit

final class SettingsController: UITableViewController {
    private let dnsServers = ["1.1.1.1", "8.8.8.8", "9.9.9.9"]
    private let protocols = ["VLESS · Reality / TLS / TCP / WS / gRPC / H2", "VMess AEAD · TCP / WS / gRPC / H2", "Trojan · TLS / TCP / WS / gRPC / H2", "Shadowsocks · AEAD и SS2022", "SOCKS5 · TCP и UDP", "HTTP · TCP CONNECT"]
    init() { super.init(style: .grouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Настройки"; tableView.backgroundColor = Theme.background; tableView.separatorColor = Theme.line
        tableView.estimatedRowHeight = 55; tableView.rowHeight = UITableView.automaticDimension
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(close))
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 : section == 1 ? protocols.count : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { ["DNS", "ПРОТОКОЛЫ ЯДРА", "INCY LEGACY"][section] }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "DNS-запросы идут через VPN. Для изменения сначала отключите соединение. HTTP CONNECT использует DNS-over-HTTPS для A/AAAA; другой UDP-трафик этим протоколом не передаётся." }
        if section == 1 { return "Совместимость зависит от параметров сервера. WireGuard, OpenVPN, Hysteria2, TUIC и XHTTP в эту версию не включены." }
        return "Версия 1.0 · iPhone 6 · iOS 12.5.8\nКлючи хранятся в Keychain. Телеметрии и рекламы нет. Подключение означает запуск туннеля; доступность сервера проверяется реальным трафиком."
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.panel; cell.textLabel?.textColor = .white; cell.detailTextLabel?.textColor = Theme.muted
        cell.textLabel?.font = .systemFont(ofSize: 14); cell.textLabel?.numberOfLines = 0
        if indexPath.section == 0 { cell.textLabel?.text = dnsServers[indexPath.row]; cell.accessoryType = ProfileStore.shared.dns == dnsServers[indexPath.row] ? .checkmark : .none; cell.tintColor = Theme.accent }
        else if indexPath.section == 1 { cell.textLabel?.text = protocols[indexPath.row]; cell.selectionStyle = .none }
        else { cell.textLabel?.text = "Xray-core 1.8.24 + HEV tun2socks"; cell.detailTextLabel?.text = "UIKit · NetworkExtension · arm64"; cell.selectionStyle = .none }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else { return }
        if VPNController.shared.isBusy {
            let alert = UIAlertController(title: "INCY", message: "Сначала отключите VPN.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Понятно", style: .default)); present(alert, animated: true); return
        }
        ProfileStore.shared.dns = dnsServers[indexPath.row]; tableView.reloadData()
    }
    @objc private func close() { dismiss(animated: true) }
}

