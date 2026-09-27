import UIKit

/// A transparent UIKit layer that sits inside the PencilKit canvas (so it scrolls
/// and zooms with the page) and draws the tutor's findings as highlighted regions
/// with a tappable badge. Touches outside badges fall through to the canvas so
/// the pencil keeps working.
final class FindingsOverlayView: UIView {
    struct Item {
        let id: UUID
        let rect: CGRect          // in page points
        let severity: FindingSeverity
    }

    var items: [Item] = [] { didSet { setNeedsDisplay() } }
    var onTap: ((UUID) -> Void)?
    var selectedID: UUID? { didSet { setNeedsDisplay() } }

    private let badgeSize: CGFloat = 26

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Only intercept taps on a badge; everything else reaches the canvas.
        for item in items where badgeRect(for: item).insetBy(dx: -6, dy: -6).contains(point) {
            return self
        }
        return nil
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: self)
        if let item = items.first(where: { badgeRect(for: $0).insetBy(dx: -6, dy: -6).contains(p) }) {
            onTap?(item.id)
        }
    }

    private func badgeRect(for item: Item) -> CGRect {
        CGRect(x: item.rect.maxX - badgeSize / 2, y: item.rect.minY - badgeSize / 2, width: badgeSize, height: badgeSize)
    }

    private func color(for severity: FindingSeverity) -> UIColor {
        switch severity {
        case .error: return UIColor.systemRed
        case .warning: return UIColor.systemOrange
        case .hint: return UIColor.systemBlue
        case .praise: return UIColor.systemGreen
        }
    }

    private func symbol(for severity: FindingSeverity) -> String {
        switch severity {
        case .error: return "xmark"
        case .warning: return "exclamationmark"
        case .hint: return "lightbulb"
        case .praise: return "checkmark"
        }
    }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        for item in items {
            let c = color(for: item.severity)
            let selected = item.id == selectedID
            let path = UIBezierPath(roundedRect: item.rect.insetBy(dx: -4, dy: -4), cornerRadius: 8)
            cg.setStrokeColor(c.withAlphaComponent(selected ? 0.95 : 0.7).cgColor)
            cg.setFillColor(c.withAlphaComponent(selected ? 0.16 : 0.08).cgColor)
            cg.setLineWidth(selected ? 2.5 : 1.5)
            cg.setLineDash(phase: 0, lengths: item.severity == .praise ? [] : [6, 4])
            cg.addPath(path.cgPath)
            cg.drawPath(using: .fillStroke)
            cg.setLineDash(phase: 0, lengths: [])

            let badge = badgeRect(for: item)
            cg.setFillColor(c.cgColor)
            cg.fillEllipse(in: badge)
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(2)
            cg.strokeEllipse(in: badge)

            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            if let glyph = UIImage(systemName: symbol(for: item.severity), withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let size = glyph.size
                glyph.draw(in: CGRect(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2,
                                      width: size.width, height: size.height))
            }
        }
    }
}
