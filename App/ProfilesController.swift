import UIKit

final class ProfilesController: UITableViewController {
    private var observer: NSObjectProtocol?
    init() { super.init(style: .grouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Серверы"
        tableView.backgroundColor = Theme.background; tableView.separatorColor = Theme.line; tableView.rowHeight = 80
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
        observer = NotificationCenter.default.addObserver(forName: .profilesChanged, object: nil, queue: .main) { [weak self] _ in self?.tableView.reloadData() }
    }
    deinit { if let observer = observer { NotificationCenter.default.removeObserver(observer) } }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(1, ProfileStore.shared.profiles.count) }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.panel; cell.textLabel?.textColor = .white; cell.detailTextLabel?.textColor = Theme.muted
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        let profiles = ProfileStore.shared.profiles
        if profiles.isEmpty { cell.textLabel?.text = "Добавить первый сервер"; cell.detailTextLabel?.text = "Ссылка, QR-код или подписка"; cell.accessoryType = .disclosureIndicator }
        else {
            let p = profiles[indexPath.row]; cell.textLabel?.text = p.name
            cell.detailTextLabel?.text = "\(p.badge)   ·   \(p.endpoint)"
            cell.accessoryType = ProfileStore.shared.selected?.id == p.id ? .checkmark : .none; cell.tintColor = Theme.accent
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "ВАШИ ПРОФИЛИ" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "Проведите по профилю влево, чтобы переименовать или удалить. Для смены сервера сначала отключите VPN." }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if ProfileStore.shared.profiles.isEmpty { add(); return }
        guard !VPNController.shared.isBusy else { alert("Отключите VPN перед сменой сервера."); return }
        ProfileStore.shared.select(ProfileStore.shared.profiles[indexPath.row]); close()
    }
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { !ProfileStore.shared.profiles.isEmpty && !VPNController.shared.isBusy }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !ProfileStore.shared.profiles.isEmpty else { return nil }
        let p = ProfileStore.shared.profiles[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Удалить") { [weak self] _, _, done in
            guard !VPNController.shared.isBusy else { done(false); return }
            do { try ProfileStore.shared.delete(p); done(true) } catch { self?.alert(error.localizedDescription); done(false) }
        }
        let rename = UIContextualAction(style: .normal, title: "Имя") { [weak self] _, _, done in
            let dialog = UIAlertController(title: "Имя сервера", message: nil, preferredStyle: .alert)
            dialog.addTextField { $0.text = p.name }
            dialog.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            dialog.addAction(UIAlertAction(title: "Сохранить", style: .default) { _ in
                do { try ProfileStore.shared.rename(p, to: dialog.textFields?.first?.text ?? "") } catch { self?.alert(error.localizedDescription) }
            })
            self?.present(dialog, animated: true); done(true)
        }
        rename.backgroundColor = Theme.accent
        let actions = UISwipeActionsConfiguration(actions: [delete, rename]); actions.performsFirstActionWithFullSwipe = false; return actions
    }
    private func alert(_ message: String) {
        let dialog = UIAlertController(title: "INCY", message: message, preferredStyle: .alert)
        dialog.addAction(UIAlertAction(title: "Понятно", style: .default)); present(dialog, animated: true)
    }
    @objc private func add() { navigationController?.pushViewController(ImportController(), animated: true) }
    @objc private func close() { dismiss(animated: true) }
}

