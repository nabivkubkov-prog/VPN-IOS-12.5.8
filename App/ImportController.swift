import UIKit

final class ImportController: UIViewController, UITextViewDelegate {
    private let input = UITextView()
    private let status = Theme.label("VLESS Reality · VMess · Trojan · Shadowsocks · SOCKS5 · HTTP", size: 12, color: Theme.muted)
    private var loader: SubscriptionLoader?
    private var save: UIButton!
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Добавить сервер"; view.backgroundColor = Theme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(close))
        input.backgroundColor = Theme.panel; input.textColor = .white; input.tintColor = Theme.accent
        input.font = UIFont(name: "Menlo-Regular", size: 13) ?? .systemFont(ofSize: 13)
        input.autocorrectionType = .no; input.autocapitalizationType = .none; input.keyboardType = .URL
        input.layer.cornerRadius = 18; input.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        input.heightAnchor.constraint(equalToConstant: 200).isActive = true
        input.accessibilityLabel = "Ссылка сервера или HTTPS-подписки"; input.delegate = self
        let paste = Theme.button("Вставить ссылку", action: #selector(pasteLink), target: self)
        let qr = Theme.button("Сканировать QR", action: #selector(scan), target: self)
        let actions = Theme.stack([paste, qr], axis: .horizontal); actions.distribution = .fillEqually
        save = Theme.button("Добавить профиль", action: #selector(importProfiles), target: self)
        save.backgroundColor = Theme.accent; save.setTitleColor(Theme.background, for: .normal); save.layer.cornerRadius = 17
        save.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let title = Theme.label("Одно соединение.\nМного возможностей.", size: 26, weight: .bold)
        let explanation = Theme.label("Вставьте ссылку сервера, несколько ссылок по одной на строку или HTTPS-адрес подписки.", size: 13, color: Theme.muted)
        let stack = Theme.stack([title, explanation, input, actions, save, status], spacing: 18)
        let scroll = UIScrollView(); view.addSubview(scroll); scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        scroll.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -36), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)])
    }
    @objc private func pasteLink() { input.text = UIPasteboard.general.string ?? "" }
    @objc private func scan() {
        let scanner = QRController()
        scanner.onCode = { [weak self] value in self?.input.text = value; self?.status.text = "QR-код считан. Нажмите «Добавить профиль»." }
        navigationController?.pushViewController(scanner, animated: true)
    }
    @objc private func importProfiles() {
        input.resignFirstResponder()
        let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("https://"), !text.contains(where: { $0.isWhitespace }) {
            guard let url = URL(string: text), url.host != nil else { status.text = "Некорректный адрес подписки."; return }
            save.isEnabled = false; status.text = "Загружаем подписку…"
            let loader = SubscriptionLoader(); self.loader = loader
            loader.fetch(url) { [weak self] result in
                guard let self = self else { return }; self.save.isEnabled = true; self.loader = nil
                switch result { case .success(let text): self.store(text); case .failure(let error): self.status.text = error.localizedDescription }
            }
        } else { store(text) }
    }
    private func store(_ text: String) {
        do {
            let profiles = try ProfileParser.parseBatch(text)
            let before = ProfileStore.shared.profiles.count
            try ProfileStore.shared.add(profiles)
            let added = ProfileStore.shared.profiles.count - before
            status.text = added == 0 ? "Эти профили уже добавлены." : "Добавлено профилей: \(added)."
            if added > 0 { input.text = ""; dismiss(animated: true) }
        } catch { status.text = error.localizedDescription }
    }
    @objc private func close() { loader?.cancel(); dismiss(animated: true) }
    deinit { loader?.cancel() }
}

final class SubscriptionLoader: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var bytes = Data()
    private var completion: ((Result<String, Error>) -> Void)?
    func fetch(_ url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["User-Agent": "INCY-iOS12/1.0", "Accept": "text/plain"]
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        session?.dataTask(with: url).resume()
    }
    func cancel() { finish(.failure(ProfileError.invalid("Загрузка отменена."))) }
    private func finish(_ result: Result<String, Error>) {
        guard let callback = completion else { return }
        completion = nil; session?.invalidateAndCancel(); session = nil; bytes = Data(); callback(result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.expectedContentLength <= 1_048_576 else {
            completionHandler(.cancel); finish(.failure(ProfileError.invalid("Подписка недоступна или превышает 1 МБ."))); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else { completionHandler(nil); finish(.failure(ProfileError.invalid("Подписка должна использовать HTTPS."))); return }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= 1_048_576 else { finish(.failure(ProfileError.invalid("Подписка превышает 1 МБ."))); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { finish(.failure(error)); return }
        guard let text = String(data: bytes, encoding: .utf8) else { finish(.failure(ProfileError.invalid("Подписка должна быть текстом UTF-8."))); return }
        finish(.success(text))
    }
}

