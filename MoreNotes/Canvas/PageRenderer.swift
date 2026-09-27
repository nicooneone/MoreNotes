import UIKit
import PencilKit

/// Turns drawings into images for thumbnails, on-device OCR, and Claude vision.
enum PageRenderer {
    /// Ink composited over a plain white background, sized for vision models.
    /// White (not the template) keeps OCR and Claude focused on the handwriting.
    static func imageForAI(drawing: PKDrawing, pageSize: CGSize, maxDimension: CGFloat = 1568) -> UIImage {
        let scale = min(1, maxDimension / max(pageSize.width, pageSize.height))
        let target = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
            let ink = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: scale)
            ink.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Full-fidelity thumbnail with the template underneath, for the page grid.
    static func thumbnail(drawing: PKDrawing, template: PageTemplate, paper: PaperColor,
                          pageSize: CGSize, maxDimension: CGFloat = 400) -> UIImage {
        let scale = min(1, maxDimension / max(pageSize.width, pageSize.height))
        let target = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.saveGState()
            cg.scaleBy(x: scale, y: scale)
            TemplateRenderer.draw(template: template, paper: paper, in: cg, size: pageSize)
            cg.restoreGState()
            let ink = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: scale)
            ink.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Exports a page as it looks on screen at 2x.
    static func export(drawing: PKDrawing, template: PageTemplate, paper: PaperColor, pageSize: CGSize) -> UIImage {
        thumbnail(drawing: drawing, template: template, paper: paper, pageSize: pageSize, maxDimension: max(pageSize.width, pageSize.height) * 2)
    }

    static func jpegBase64(_ image: UIImage, quality: CGFloat = 0.8) -> String? {
        image.jpegData(compressionQuality: quality)?.base64EncodedString()
    }
}
