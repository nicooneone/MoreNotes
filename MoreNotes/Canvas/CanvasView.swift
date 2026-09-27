import SwiftUI
import PencilKit

/// SwiftUI wrapper around `PKCanvasView` with a template image behind the ink and
/// a findings overlay on top. Supports Apple Pencil (1st and 2nd gen), Bluetooth
/// styluses that present as pencil input, and optional finger drawing.
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let template: PageTemplate
    let paper: PaperColor
    let pageSize: CGSize
    let tools: ToolState
    /// Changes whenever any tool setting changes; makes SwiftUI re-run updateUIView.
    let toolSignature: String
    let allowFingerDrawing: Bool
    let findings: [FindingsOverlayView.Item]
    let selectedFindingID: UUID?

    /// Fires (debounced by the caller) whenever strokes change.
    var onDrawingChanged: (PKDrawing) -> Void
    /// Fires when the pencil lifts after a stroke, used for idle detection.
    var onStrokeEnded: () -> Void
    var onFindingTapped: (UUID) -> Void
    /// Gives the parent a handle for undo/redo/clear.
    var onCanvasReady: (PKCanvasView) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        canvas.minimumZoomScale = 0.5
        canvas.maximumZoomScale = 5
        canvas.bouncesZoom = true
        canvas.contentSize = pageSize
        canvas.contentInset = UIEdgeInsets(top: 24, left: 24, bottom: 200, right: 24)
        canvas.tool = tools.pkTool
        canvas.isRulerActive = tools.rulerActive
        canvas.drawingPolicy = allowFingerDrawing ? .anyInput : .pencilOnly

        // Template behind the ink, inside the scroll content so it zooms with the page.
        let templateView = UIImageView(frame: CGRect(origin: .zero, size: pageSize))
        templateView.image = TemplateRenderer.shared.image(template: template, paper: paper, size: pageSize)
        templateView.isUserInteractionEnabled = false
        templateView.layer.shadowColor = UIColor.black.cgColor
        templateView.layer.shadowOpacity = 0.15
        templateView.layer.shadowRadius = 8
        templateView.layer.shadowOffset = CGSize(width: 0, height: 2)
        canvas.insertSubview(templateView, at: 0)
        context.coordinator.templateView = templateView

        let overlay = FindingsOverlayView(frame: CGRect(origin: .zero, size: pageSize))
        let coordinator = context.coordinator
        overlay.onTap = { [weak coordinator] id in coordinator?.parent.onFindingTapped(id) }
        canvas.addSubview(overlay)
        context.coordinator.overlay = overlay

        // Pencil double-tap (2nd gen) toggles between the current brush and the eraser.
        let interaction = UIPencilInteraction()
        interaction.delegate = context.coordinator
        canvas.addInteraction(interaction)

        // Center the page horizontally when it is narrower than the view.
        DispatchQueue.main.async {
            context.coordinator.centerContent(canvas)
            onCanvasReady(canvas)
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self

        if canvas.drawing != drawing, !context.coordinator.isApplyingLocalChange {
            canvas.drawing = drawing
        }
        canvas.tool = tools.pkTool
        canvas.isRulerActive = tools.rulerActive
        canvas.drawingPolicy = allowFingerDrawing ? .anyInput : .pencilOnly

        let key = "\(template.rawValue)|\(paper.rawValue)|\(pageSize)"
        if context.coordinator.templateKey != key {
            context.coordinator.templateKey = key
            context.coordinator.templateView?.image = TemplateRenderer.shared.image(template: template, paper: paper, size: pageSize)
            context.coordinator.templateView?.frame = CGRect(origin: .zero, size: pageSize)
            context.coordinator.overlay?.frame = CGRect(origin: .zero, size: pageSize)
            canvas.contentSize = pageSize
        }
        context.coordinator.overlay?.items = findings
        context.coordinator.overlay?.selectedID = selectedFindingID
        // Keep overlay above the ink.
        if let overlay = context.coordinator.overlay { canvas.bringSubviewToFront(overlay) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var parent: CanvasView
        weak var templateView: UIImageView?
        weak var overlay: FindingsOverlayView?
        var templateKey = ""
        var isApplyingLocalChange = false

        init(parent: CanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            isApplyingLocalChange = true
            parent.drawing = canvasView.drawing
            parent.onDrawingChanged(canvasView.drawing)
            DispatchQueue.main.async { self.isApplyingLocalChange = false }
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            parent.onStrokeEnded()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
        }

        func centerContent(_ scrollView: UIScrollView) {
            let bounds = scrollView.bounds.size
            let content = CGSize(width: scrollView.contentSize.width * scrollView.zoomScale,
                                 height: scrollView.contentSize.height * scrollView.zoomScale)
            let horizontal = max(0, (bounds.width - content.width) / 2)
            var inset = scrollView.contentInset
            inset.left = horizontal
            inset.right = horizontal
            scrollView.contentInset = inset
        }

        // Apple Pencil 2 double-tap. Pencil 1 (iPad 8th gen) has no gesture; harmless there.
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            let tools = parent.tools
            switch UIPencilInteraction.preferredTapAction {
            case .switchEraser:
                tools.mode = tools.mode == .erase ? .draw : .erase
            case .switchPrevious, .showColorPalette, .showInkAttributes:
                tools.mode = tools.mode == .erase ? .draw : .erase
            default:
                break
            }
        }
    }
}
