import UIKit
import AVFoundation

final class QRController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let cameraQueue = DispatchQueue(label: "incy.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private let message = Theme.label("Наведите камеру на QR-код сервера", size: 15, weight: .medium)
    private var didScan = false
    override func viewDidLoad() {
        super.viewDidLoad(); title = "QR-код"; view.backgroundColor = Theme.background
        message.textAlignment = .center; view.addSubview(message); message.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), message.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32)])
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            guard let self = self else { return }
            if allowed { self.configure() }
            else { DispatchQueue.main.async { self.message.text = "Разрешите доступ к камере в настройках iPhone." } }
        }
    }
    private func configure() {
        cameraQueue.async {
            do {
                guard let camera = AVCaptureDevice.default(for: .video) else { throw ProfileError.invalid("Камера недоступна.") }
                let input = try AVCaptureDeviceInput(device: camera)
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddInput(input), self.session.canAddOutput(output) else { throw ProfileError.invalid("Не удалось включить камеру.") }
                self.session.beginConfiguration(); self.session.sessionPreset = .medium
                self.session.addInput(input); self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    guard self.view.window != nil else { return }
                    let preview = AVCaptureVideoPreviewLayer(session: self.session); preview.videoGravity = .resizeAspectFill
                    preview.frame = self.view.bounds; self.view.layer.insertSublayer(preview, at: 0); self.preview = preview
                    self.cameraQueue.async { self.session.startRunning() }
                }
            } catch { DispatchQueue.main.async { self.message.text = error.localizedDescription } }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); cameraQueue.async { self.session.stopRunning() } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didScan, let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let value = code.stringValue else { return }
        didScan = true; onCode?(value); navigationController?.popViewController(animated: true)
    }
}

