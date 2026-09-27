import UIKit

/// Draws a page template (lines, grids, Cornell layout ...) into a UIImage so it
/// can sit behind the PencilKit canvas. Rendering is cached by (template, paper, size, scale).
final class TemplateRenderer {
    static let shared = TemplateRenderer()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 32
    }

    func image(template: PageTemplate, paper: PaperColor, size: CGSize, scale: CGFloat = UIScreen.main.scale) -> UIImage {
        let key = "\(template.rawValue)|\(paper.rawValue)|\(Int(size.width))x\(Int(size.height))|\(scale)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            Self.draw(template: template, paper: paper, in: cg, size: size)
        }
        cache.setObject(image, forKey: key)
        return image
    }

    // MARK: - Drawing

    static func draw(template: PageTemplate, paper: PaperColor, in cg: CGContext, size: CGSize) {
        let bg = paper.rgb
        cg.setFillColor(red: bg.r, green: bg.g, blue: bg.b, alpha: 1)
        cg.fill(CGRect(origin: .zero, size: size))

        let g = paper.guideRGB
        let guide = CGColor(red: g.r, green: g.g, blue: g.b, alpha: g.a)
        let faint = CGColor(red: g.r, green: g.g, blue: g.b, alpha: g.a * 0.45)
        let strong = CGColor(red: g.r, green: g.g, blue: g.b, alpha: min(1, g.a * 1.8))
        let margin: CGFloat = 40
        let topInset: CGFloat = 72

        switch template {
        case .blank:
            break

        case .ruledNarrow, .ruledCollege, .ruledWide:
            horizontalLines(cg, size: size, pitch: template.pitch, top: topInset, color: guide)
            // red left margin like a real notebook page
            cg.setStrokeColor(red: 0.90, green: 0.35, blue: 0.35, alpha: paper.isDark ? 0.5 : 0.6)
            cg.setLineWidth(1)
            cg.move(to: CGPoint(x: margin + 30, y: 0))
            cg.addLine(to: CGPoint(x: margin + 30, y: size.height))
            cg.strokePath()

        case .gridSmall, .gridMedium, .gridLarge:
            grid(cg, size: size, pitch: template.pitch, color: guide)

        case .engineering:
            grid(cg, size: size, pitch: template.pitch, color: faint)
            grid(cg, size: size, pitch: template.pitch * 5, color: strong)

        case .dotted:
            dots(cg, size: size, pitch: template.pitch, color: strong)

        case .cornell:
            // Cue column (left ~30%), notes area, summary box at the bottom.
            let cueWidth = size.width * 0.30
            let summaryHeight = size.height * 0.20
            let headerHeight: CGFloat = 60
            cg.setStrokeColor(strong)
            cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: 0, y: headerHeight)); cg.addLine(to: CGPoint(x: size.width, y: headerHeight))
            cg.move(to: CGPoint(x: cueWidth, y: headerHeight)); cg.addLine(to: CGPoint(x: cueWidth, y: size.height - summaryHeight))
            cg.move(to: CGPoint(x: 0, y: size.height - summaryHeight)); cg.addLine(to: CGPoint(x: size.width, y: size.height - summaryHeight))
            cg.strokePath()
            horizontalLines(cg, size: CGSize(width: size.width, height: size.height - summaryHeight),
                            pitch: 26, top: headerHeight + 26, color: faint, fromX: cueWidth + 8)
            label(cg, "Cues", at: CGPoint(x: 12, y: headerHeight + 8), color: strong)
            label(cg, "Notes", at: CGPoint(x: cueWidth + 12, y: headerHeight + 8), color: strong)
            label(cg, "Summary", at: CGPoint(x: 12, y: size.height - summaryHeight + 8), color: strong)

        case .graphAxes:
            grid(cg, size: size, pitch: 20, color: faint)
            cg.setStrokeColor(strong)
            cg.setLineWidth(2)
            let cx = (size.width / 2).rounded(), cy = (size.height / 2).rounded()
            cg.move(to: CGPoint(x: 0, y: cy)); cg.addLine(to: CGPoint(x: size.width, y: cy))
            cg.move(to: CGPoint(x: cx, y: 0)); cg.addLine(to: CGPoint(x: cx, y: size.height))
            cg.strokePath()

        case .isometric:
            isometric(cg, size: size, pitch: template.pitch, color: guide)

        case .musicStaff:
            let staffGap: CGFloat = 9
            let staffHeight = staffGap * 4
            let blockPitch: CGFloat = 90
            var y = topInset
            cg.setStrokeColor(strong)
            cg.setLineWidth(1)
            while y + staffHeight < size.height - margin {
                for i in 0..<5 {
                    let ly = y + CGFloat(i) * staffGap
                    cg.move(to: CGPoint(x: margin, y: ly)); cg.addLine(to: CGPoint(x: size.width - margin, y: ly))
                }
                cg.strokePath()
                y += blockPitch
            }

        case .checklist:
            let pitch: CGFloat = 34
            horizontalLines(cg, size: size, pitch: pitch, top: topInset, color: faint)
            cg.setStrokeColor(strong)
            cg.setLineWidth(1.2)
            var y = topInset - pitch + 8
            while y + 18 < size.height - margin {
                cg.stroke(CGRect(x: margin, y: y, width: 18, height: 18), width: 1.2)
                y += pitch
            }

        case .dailyPlanner:
            let header: CGFloat = 70
            cg.setStrokeColor(strong); cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: 0, y: header)); cg.addLine(to: CGPoint(x: size.width, y: header)); cg.strokePath()
            label(cg, "Date:", at: CGPoint(x: 16, y: 24), color: strong)
            let hourPitch: CGFloat = 44
            var y = header + hourPitch
            var hour = 7
            let leftColumn = size.width * 0.62
            cg.setStrokeColor(strong)
            cg.move(to: CGPoint(x: leftColumn, y: header)); cg.addLine(to: CGPoint(x: leftColumn, y: size.height)); cg.strokePath()
            label(cg, "Priorities", at: CGPoint(x: leftColumn + 12, y: header + 10), color: strong)
            while y < size.height - 10 && hour <= 22 {
                cg.setStrokeColor(faint); cg.setLineWidth(1)
                cg.move(to: CGPoint(x: 0, y: y)); cg.addLine(to: CGPoint(x: leftColumn, y: y)); cg.strokePath()
                label(cg, String(format: "%02d:00", hour), at: CGPoint(x: 12, y: y - hourPitch + 6), color: strong)
                y += hourPitch; hour += 1
            }
            horizontalLines(cg, size: size, pitch: 30, top: header + 60, color: faint, fromX: leftColumn + 8)
        }
    }

    // MARK: - Primitives

    private static func horizontalLines(_ cg: CGContext, size: CGSize, pitch: CGFloat, top: CGFloat, color: CGColor, fromX: CGFloat = 0) {
        cg.setStrokeColor(color)
        cg.setLineWidth(1)
        var y = top
        while y < size.height {
            cg.move(to: CGPoint(x: fromX, y: y))
            cg.addLine(to: CGPoint(x: size.width, y: y))
            y += pitch
        }
        cg.strokePath()
    }

    private static func grid(_ cg: CGContext, size: CGSize, pitch: CGFloat, color: CGColor) {
        cg.setStrokeColor(color)
        cg.setLineWidth(1)
        var x: CGFloat = 0
        while x <= size.width { cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x, y: size.height)); x += pitch }
        var y: CGFloat = 0
        while y <= size.height { cg.move(to: CGPoint(x: 0, y: y)); cg.addLine(to: CGPoint(x: size.width, y: y)); y += pitch }
        cg.strokePath()
    }

    private static func dots(_ cg: CGContext, size: CGSize, pitch: CGFloat, color: CGColor) {
        cg.setFillColor(color)
        let r: CGFloat = 1.2
        var y = pitch
        while y < size.height {
            var x = pitch
            while x < size.width {
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                x += pitch
            }
            y += pitch
        }
    }

    private static func isometric(_ cg: CGContext, size: CGSize, pitch: CGFloat, color: CGColor) {
        cg.setStrokeColor(color)
        cg.setLineWidth(1)
        // vertical lines
        var x: CGFloat = 0
        while x <= size.width { cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x, y: size.height)); x += pitch }
        // 30-degree diagonals both directions
        let dy = pitch * 2 * 0.57735 // tan(30°)
        let span = size.width + size.height * 2
        var start: CGFloat = -size.height * 2
        while start < span {
            cg.move(to: CGPoint(x: start, y: 0)); cg.addLine(to: CGPoint(x: start + size.height / 0.57735, y: size.height))
            cg.move(to: CGPoint(x: start, y: size.height)); cg.addLine(to: CGPoint(x: start + size.height / 0.57735, y: 0))
            start += dy
        }
        cg.strokePath()
    }

    private static func label(_ cg: CGContext, _ text: String, at point: CGPoint, color: CGColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor(cgColor: color),
        ]
        UIGraphicsPushContext(cg)
        (text as NSString).draw(at: point, withAttributes: attrs)
        UIGraphicsPopContext()
    }
}
