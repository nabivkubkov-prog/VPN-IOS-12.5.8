import UIKit

enum Theme {
    static let background = UIColor(red: 0.035, green: 0.045, blue: 0.08, alpha: 1)
    static let panel = UIColor(red: 0.07, green: 0.08, blue: 0.125, alpha: 1)
    static let accent = UIColor(red: 0.65, green: 0.48, blue: 1, alpha: 1)
    static let mint = UIColor(red: 0.39, green: 0.93, blue: 0.79, alpha: 1)
    static let muted = UIColor(red: 0.54, green: 0.56, blue: 0.64, alpha: 1)
    static let line = UIColor.white.withAlphaComponent(0.07)
    static func label(_ text: String, size: CGFloat = 14, weight: UIFont.Weight = .regular, color: UIColor = .white) -> UILabel {
        let label = UILabel(); label.text = text
        label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color
        label.numberOfLines = 0; return label
    }
    static func stack(_ views: [UIView], axis: NSLayoutConstraint.Axis = .vertical, spacing: CGFloat = 8) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views); stack.axis = axis; stack.spacing = spacing; return stack
    }
    static func button(_ title: String, action: Selector, target: Any) -> UIButton {
        let button = UIButton(type: .system); button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.setTitleColor(accent, for: .normal); button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }
    static func modal(_ controller: UIViewController, from presenter: UIViewController) {
        let nav = UINavigationController(rootViewController: controller)
        nav.navigationBar.barStyle = .black; nav.navigationBar.barTintColor = background
        nav.navigationBar.tintColor = accent; nav.navigationBar.isTranslucent = false
        nav.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        presenter.present(nav, animated: true)
    }
}

final class Card: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.panel; layer.cornerRadius = 22
        layer.borderWidth = 1; layer.borderColor = Theme.line.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func fill(_ child: UIView, inset: CGFloat = 20) {
        addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset), child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset), child.topAnchor.constraint(equalTo: topAnchor, constant: inset), child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)])
    }
}

final class Glyph: UIView {
    enum Kind { case power, plus, gear, servers, shield, up, down, chevron }
    let kind: Kind
    var tint: UIColor { didSet { setNeedsDisplay() } }
    init(_ kind: Kind, color: UIColor = Theme.accent, size: CGFloat = 24) {
        self.kind = kind; self.tint = color; super.init(frame: .zero)
        backgroundColor = .clear; isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState(); ctx.scaleBy(x: rect.width / 24, y: rect.height / 24)
        tint.setStroke(); let p = UIBezierPath(); p.lineWidth = 1.7; p.lineCapStyle = .round; p.lineJoinStyle = .round
        func line(_ a: CGPoint, _ b: CGPoint) { p.move(to: a); p.addLine(to: b) }
        switch kind {
        case .power:
            p.addArc(withCenter: CGPoint(x: 12, y: 13), radius: 8, startAngle: -.pi / 2 + 0.6, endAngle: 3 * .pi / 2 - 0.6, clockwise: true)
            line(CGPoint(x: 12, y: 2), CGPoint(x: 12, y: 12))
        case .plus: line(CGPoint(x: 12, y: 5), CGPoint(x: 12, y: 19)); line(CGPoint(x: 5, y: 12), CGPoint(x: 19, y: 12))
        case .up, .down:
            let y: CGFloat = kind == .up ? 5 : 19; let end: CGFloat = kind == .up ? 19 : 5; let wing: CGFloat = kind == .up ? 10 : 14
            line(CGPoint(x: 12, y: end), CGPoint(x: 12, y: y)); line(CGPoint(x: 7, y: wing), CGPoint(x: 12, y: y)); line(CGPoint(x: 12, y: y), CGPoint(x: 17, y: wing))
        case .chevron: p.move(to: CGPoint(x: 9, y: 6)); p.addLine(to: CGPoint(x: 15, y: 12)); p.addLine(to: CGPoint(x: 9, y: 18))
        case .servers:
            p.append(UIBezierPath(roundedRect: CGRect(x: 3, y: 4, width: 18, height: 7), cornerRadius: 2))
            p.append(UIBezierPath(roundedRect: CGRect(x: 3, y: 14, width: 18, height: 7), cornerRadius: 2))
            line(CGPoint(x: 7, y: 7.5), CGPoint(x: 8, y: 7.5)); line(CGPoint(x: 7, y: 17.5), CGPoint(x: 8, y: 17.5))
        case .shield:
            p.move(to: CGPoint(x: 12, y: 2)); p.addLine(to: CGPoint(x: 21, y: 6)); p.addQuadCurve(to: CGPoint(x: 12, y: 22), controlPoint: CGPoint(x: 21, y: 17)); p.addQuadCurve(to: CGPoint(x: 3, y: 6), controlPoint: CGPoint(x: 3, y: 17)); p.close()
            line(CGPoint(x: 8, y: 12), CGPoint(x: 11, y: 15)); line(CGPoint(x: 11, y: 15), CGPoint(x: 16, y: 9))
        case .gear:
            p.append(UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 14, height: 14)))
            p.append(UIBezierPath(ovalIn: CGRect(x: 9, y: 9, width: 6, height: 6)))
            for i in 0..<8 { let a = CGFloat(i) * .pi / 4; line(CGPoint(x: 12 + cos(a) * 8, y: 12 + sin(a) * 8), CGPoint(x: 12 + cos(a) * 10, y: 12 + sin(a) * 10)) }
        }
        p.stroke(); ctx.restoreGState()
    }
}

final class PowerButton: UIControl {
    private let gradient = CAGradientLayer()
    private let ring = CAShapeLayer()
    private let inner = UIView()
    private let glyph = Glyph(.power, color: .white, size: 42)
    private let caption = Theme.label("ВКЛЮЧИТЬ", size: 10, weight: .semibold, color: Theme.muted)
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true; accessibilityLabel = "Подключить VPN"; accessibilityTraits = .button
        gradient.colors = [Theme.accent.cgColor, UIColor(red: 0.36, green: 0.40, blue: 0.96, alpha: 1).cgColor, Theme.mint.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1)
        ring.fillColor = UIColor.clear.cgColor; ring.strokeColor = UIColor.white.cgColor; ring.lineWidth = 3
        gradient.mask = ring; layer.addSublayer(gradient)
        inner.backgroundColor = Theme.panel; inner.isUserInteractionEnabled = false; addSubview(inner)
        caption.textAlignment = .center
        let stack = Theme.stack([glyph, caption], spacing: 13); stack.alignment = .center; stack.isUserInteractionEnabled = false
        inner.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: inner.centerXAnchor), stack.centerYAnchor.constraint(equalTo: inner.centerYAnchor)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews(); gradient.frame = bounds
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).cgPath
        inner.frame = bounds.insetBy(dx: 12, dy: 12); inner.layer.cornerRadius = inner.bounds.width / 2
    }
    func update(connected: Bool, busy: Bool) {
        glyph.tint = connected ? Theme.mint : .white
        caption.text = connected ? "ОТКЛЮЧИТЬ" : busy ? "ОЖИДАНИЕ" : "ВКЛЮЧИТЬ"
        accessibilityLabel = connected ? "Отключить VPN" : "Подключить VPN"
        gradient.opacity = connected ? 1 : 0.65
        if busy {
            if layer.animation(forKey: "pulse") == nil {
                let pulse = CABasicAnimation(keyPath: "opacity"); pulse.fromValue = 1; pulse.toValue = 0.5; pulse.duration = 0.8; pulse.autoreverses = true; pulse.repeatCount = .infinity
                layer.add(pulse, forKey: "pulse")
            }
        } else { layer.removeAnimation(forKey: "pulse") }
    }
}

