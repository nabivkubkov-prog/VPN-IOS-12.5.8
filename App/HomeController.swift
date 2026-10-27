import UIKit
import NetworkExtension

final class HomeController: UIViewController {
    private let power = PowerButton(frame: .zero)
    private let statusLabel = Theme.label("Не подключено", size: 22, weight: .semibold)
    private let hint = Theme.label("Ваше пространство. Ваше соединение.", size: 12, color: Theme.muted)
    private let serverName = Theme.label("Добавьте сервер", size: 17, weight: .semibold)
    private let endpoint = Theme.label("Импортируйте ссылку или QR-код", size: 12, color: Theme.muted)
    private let badge = Theme.label("ПРОФИЛЬ НЕ ВЫБРАН", size: 10, weight: .semibold, color: Theme.accent)
    private let uploadLabel = Theme.label("0 Б", size: 18, weight: .medium)
    private let downloadLabel = Theme.label("0 Б", size: 18, weight: .medium)
    private let dnsLabel = Theme.label("1.1.1.1", size: 13, weight: .medium)
    private let timerLabel = Theme.label("00:00:00", size: 12, color: Theme.muted)
    private var observers = [NSObjectProtocol]()
    private var timer: Timer?
    private var statsPending = false
    private var statsRequestedAt: Date?
    private let glow = CAGradientLayer()
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = Theme.background
        glow.colors = [Theme.accent.withAlphaComponent(0.12).cgColor, Theme.background.cgColor]
        glow.startPoint = CGPoint(x: 0.1, y: 0); glow.endPoint = CGPoint(x: 0.8, y: 1)
        view.layer.insertSublayer(glow, at: 0)
        let scroll = UIScrollView(); scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll); scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)])

        let logo = Theme.stack([Theme.label("INCY", size: 29, weight: .heavy), Theme.label("PRIVATE CONNECTION", size: 8, weight: .semibold, color: Theme.muted)], spacing: 2)
        let add = Theme.button("+", action: #selector(openImport), target: self)
        add.titleLabel?.font = .systemFont(ofSize: 28, weight: .light)
        add.backgroundColor = Theme.panel; add.layer.cornerRadius = 15
        NSLayoutConstraint.activate([add.widthAnchor.constraint(equalToConstant: 44), add.heightAnchor.constraint(equalToConstant: 44)])
        add.accessibilityLabel = "Добавить сервер"
        let header = Theme.stack([logo, UIView(), add], axis: .horizontal); header.alignment = .center

        statusLabel.textAlignment = .center; hint.textAlignment = .center; timerLabel.textAlignment = .center
        let powerContainer = UIView(); powerContainer.addSubview(power); power.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([power.centerXAnchor.constraint(equalTo: powerContainer.centerXAnchor), power.topAnchor.constraint(equalTo: powerContainer.topAnchor, constant: 10), power.bottomAnchor.constraint(equalTo: powerContainer.bottomAnchor, constant: -10), power.widthAnchor.constraint(equalToConstant: 144), power.heightAnchor.constraint(equalToConstant: 144)])
        power.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        let connection = Theme.stack([statusLabel, hint, powerContainer, timerLabel], spacing: 8)

        let serverCard = Card()
        let detail = Theme.stack([badge, serverName, endpoint], spacing: 7)
        serverName.lineBreakMode = .byTruncatingTail; serverName.numberOfLines = 1
        endpoint.lineBreakMode = .byTruncatingMiddle; endpoint.numberOfLines = 1
        let serverRow = Theme.stack([Glyph(.servers, size: 30), detail, Glyph(.chevron, color: Theme.muted)], axis: .horizontal, spacing: 16)
        serverRow.alignment = .center; serverCard.fill(serverRow, inset: 16)
        serverCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openProfiles)))
        serverCard.isAccessibilityElement = true; serverCard.accessibilityLabel = "Выбрать сервер"; serverCard.accessibilityTraits = .button

        let trafficCard = Card()
        func traffic(_ glyph: Glyph.Kind, value: UILabel, text: String) -> UIView {
            let left = Theme.stack([Theme.label(text, size: 10, color: Theme.muted), value], spacing: 7)
            let row = Theme.stack([Glyph(glyph, color: glyph == .down ? Theme.mint : Theme.accent), left], axis: .horizontal, spacing: 10); row.alignment = .center; return row
        }
        let trafficRow = Theme.stack([traffic(.down, value: downloadLabel, text: "ПОЛУЧЕНО"), traffic(.up, value: uploadLabel, text: "ОТПРАВЛЕНО")], axis: .horizontal)
        trafficRow.distribution = .fillEqually; trafficCard.fill(trafficRow, inset: 16)

        let privacy = Card()
        let dnsRow = Theme.stack([Glyph(.shield, color: Theme.mint, size: 20), Theme.label("DNS через VPN", size: 12, color: Theme.muted), UIView(), dnsLabel], axis: .horizontal, spacing: 9)
        dnsRow.alignment = .center; privacy.fill(dnsRow, inset: 15)
        let profilesButton = Theme.button("Серверы", action: #selector(openProfiles), target: self)
        let importButton = Theme.button("Импорт", action: #selector(openImport), target: self)
        let settingsButton = Theme.button("Настройки", action: #selector(openSettings), target: self)
        let navigation = Theme.stack([profilesButton, importButton, settingsButton], axis: .horizontal); navigation.distribution = .fillEqually
        navigation.backgroundColor = Theme.background
        view.addSubview(navigation); navigation.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([navigation.heightAnchor.constraint(equalToConstant: 58), navigation.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), navigation.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), navigation.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: navigation.topAnchor)])
        let content = Theme.stack([header, connection, serverCard, trafficCard, privacy], spacing: 14)
        scroll.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12), content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10), content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)])
        for name in [Notification.Name.vpnChanged, .profilesChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .vpnError, object: nil, queue: .main) { [weak self] notification in self?.showError(notification.object as? String ?? "Ошибка подключения.") })
        refresh()
        if let error = ProfileStore.shared.loadError { DispatchQueue.main.async { self.showError(error) } }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); glow.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 350) }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        refresh()
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate(); for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private func refresh() {
        let vpn = VPNController.shared
        switch vpn.status {
        case .connected: statusLabel.text = "Подключено"; statusLabel.textColor = Theme.mint; hint.text = "Трафик направлен через выбранный сервер"
        case .connecting: statusLabel.text = "Подключение…"; statusLabel.textColor = .white; hint.text = "Устанавливаем защищённое соединение"
        case .reasserting: statusLabel.text = "Восстановление…"; statusLabel.textColor = .white; hint.text = "Ожидаем доступ к сети"
        case .disconnecting: statusLabel.text = "Отключение…"; statusLabel.textColor = .white; hint.text = "Завершаем соединение"
        default: statusLabel.text = "Не подключено"; statusLabel.textColor = .white; hint.text = "Ваше пространство. Ваше соединение."
        }
        let connected = vpn.status == .connected
        power.update(connected: connected, busy: vpn.isBusy && !connected)
        power.isEnabled = !vpn.configuring && vpn.status != .disconnecting
        if let p = ProfileStore.shared.selected { serverName.text = p.name; endpoint.text = p.endpoint; badge.text = p.badge }
        else { serverName.text = "Добавьте сервер"; endpoint.text = "Импортируйте ссылку или QR-код"; badge.text = "ПРОФИЛЬ НЕ ВЫБРАН" }
        dnsLabel.text = ProfileStore.shared.dns
        tick()
    }
    private func tick() {
        let vpn = VPNController.shared
        if let started = vpn.manager?.connection.connectedDate, vpn.status == .connected {
            let seconds = max(0, Int(Date().timeIntervalSince(started)))
            timerLabel.text = String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
        } else { timerLabel.text = "00:00:00" }
        if statsPending, let date = statsRequestedAt, Date().timeIntervalSince(date) < 4 { return }
        statsPending = true; statsRequestedAt = Date()
        vpn.statistics { [weak self] up, down in
            guard let self = self else { return }; self.statsPending = false
            let format: (UInt64) -> String = { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .binary) }
            self.uploadLabel.text = format(up); self.downloadLabel.text = format(down)
        }
    }
    @objc private func toggle() {
        if ProfileStore.shared.selected == nil { openImport() } else { VPNController.shared.toggle() }
    }
    @objc private func openProfiles() { Theme.modal(ProfilesController(), from: self) }
    @objc private func openImport() { Theme.modal(ImportController(), from: self) }
    @objc private func openSettings() { Theme.modal(SettingsController(), from: self) }
    func showError(_ message: String) {
        let alert = UIAlertController(title: "INCY", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Понятно", style: .default))
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController { presenter = presented }
        if !(presenter is UIAlertController) { presenter.present(alert, animated: true) }
    }
}

