import SwiftUI
import PencilKit

/// Which family of tool is active.
enum ToolMode: String, CaseIterable, Codable {
    case draw, erase, lasso
}

/// Brush styles exposed to the user. Each maps to a PencilKit ink type.
enum BrushKind: String, CaseIterable, Identifiable, Codable {
    case pen, pencil, marker, monoline, fountainPen, watercolor, crayon

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pen: return "Ballpoint Pen"
        case .pencil: return "Pencil"
        case .marker: return "Highlighter"
        case .monoline: return "Monoline"
        case .fountainPen: return "Fountain Pen"
        case .watercolor: return "Watercolor"
        case .crayon: return "Crayon"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .monoline: return "scribble"
        case .fountainPen: return "pencil.and.outline"
        case .watercolor: return "paintbrush.pointed"
        case .crayon: return "paintbrush"
        }
    }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .pen: return .pen
        case .pencil: return .pencil
        case .marker: return .marker
        case .monoline: return .monoline
        case .fountainPen: return .fountainPen
        case .watercolor: return .watercolor
        case .crayon: return .crayon
        }
    }

    /// Width range PencilKit accepts for this ink.
    var widthRange: ClosedRange<CGFloat> {
        let r = inkType.validWidthRange
        return r.lowerBound...r.upperBound
    }

    var defaultWidth: CGFloat {
        switch self {
        case .pen: return 3
        case .pencil: return 4
        case .marker: return 18
        case .monoline: return 3
        case .fountainPen: return 4
        case .watercolor: return 14
        case .crayon: return 8
        }
    }

    var defaultOpacity: Double {
        switch self {
        case .marker: return 0.55
        case .watercolor: return 0.7
        default: return 1
        }
    }
}

enum EraserKind: String, CaseIterable, Identifiable, Codable {
    /// Removes whole strokes.
    case stroke
    /// Erases only the pixels under the eraser (bitmap).
    case pixel
    /// Bitmap eraser whose width does not scale with zoom.
    case fixedPixel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stroke: return "Stroke Eraser"
        case .pixel: return "Pixel Eraser"
        case .fixedPixel: return "Precise Eraser"
        }
    }

    var systemImage: String {
        switch self {
        case .stroke: return "eraser.line.dashed"
        case .pixel: return "eraser"
        case .fixedPixel: return "eraser.fill"
        }
    }

    var eraserType: PKEraserTool.EraserType {
        switch self {
        case .stroke: return .vector
        case .pixel: return .bitmap
        case .fixedPixel: return .fixedWidthBitmap
        }
    }
}

/// A saved favorite: brush + color + width + opacity, like the pen presets in GoodNotes.
struct BrushPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var brush: BrushKind
    var colorHex: String
    var width: Double
    var opacity: Double
}

/// The complete drawing tool configuration. Observed by the palette and the canvas.
@Observable
final class ToolState {
    var mode: ToolMode = .draw
    var brush: BrushKind = .pen
    var color: Color = .black
    var width: CGFloat = 3
    var opacity: Double = 1
    var eraser: EraserKind = .pixel
    var eraserWidth: CGFloat = 20
    var rulerActive = false
    var presets: [BrushPreset] = BrushPreset.defaults

    /// Per-brush remembered widths so switching between pen and highlighter
    /// keeps each one's size.
    private var rememberedWidths: [BrushKind: CGFloat] = [:]
    private var rememberedOpacity: [BrushKind: Double] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: "MoreNotes.presets"),
           let saved = try? JSONDecoder().decode([BrushPreset].self, from: data) {
            presets = saved
        }
    }

    func select(brush newBrush: BrushKind) {
        rememberedWidths[brush] = width
        rememberedOpacity[brush] = opacity
        brush = newBrush
        width = rememberedWidths[newBrush] ?? newBrush.defaultWidth
        opacity = rememberedOpacity[newBrush] ?? newBrush.defaultOpacity
        mode = .draw
    }

    func apply(preset: BrushPreset) {
        brush = preset.brush
        color = Color(hex: preset.colorHex) ?? .black
        width = CGFloat(preset.width)
        opacity = preset.opacity
        mode = .draw
    }

    func saveCurrentAsPreset() {
        let preset = BrushPreset(brush: brush, colorHex: color.hexString, width: Double(width), opacity: opacity)
        presets.append(preset)
        persistPresets()
    }

    func removePreset(_ preset: BrushPreset) {
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: "MoreNotes.presets")
        }
    }

    /// The PencilKit tool for the current state.
    var pkTool: PKTool {
        switch mode {
        case .draw:
            let clamped = min(max(width, brush.widthRange.lowerBound), brush.widthRange.upperBound)
            let uiColor = UIColor(color).withAlphaComponent(CGFloat(opacity))
            return PKInkingTool(brush.inkType, color: uiColor, width: clamped)
        case .erase:
            return PKEraserTool(eraser.eraserType, width: eraserWidth)
        case .lasso:
            return PKLassoTool()
        }
    }
}

extension BrushPreset {
    static let defaults: [BrushPreset] = [
        BrushPreset(brush: .pen, colorHex: "#000000", width: 3, opacity: 1),
        BrushPreset(brush: .pen, colorHex: "#1F4FD8", width: 3, opacity: 1),
        BrushPreset(brush: .pen, colorHex: "#D62828", width: 3, opacity: 1),
        BrushPreset(brush: .fountainPen, colorHex: "#1B2A41", width: 4, opacity: 1),
        BrushPreset(brush: .marker, colorHex: "#FFE733", width: 18, opacity: 0.55),
        BrushPreset(brush: .marker, colorHex: "#5CE1A5", width: 18, opacity: 0.55),
        BrushPreset(brush: .pencil, colorHex: "#444444", width: 4, opacity: 1),
    ]
}

/// Default swatches shown in the palette.
enum Swatches {
    static let all: [String] = [
        "#000000", "#3A3A3C", "#1F4FD8", "#0FA3B1", "#2E8B57",
        "#D62828", "#F77F00", "#9B5DE5", "#FF66B3", "#8B5A2B",
        "#FFE733", "#5CE1A5", "#7FD3FF", "#FFB3C1", "#FFFFFF",
    ]
}

// MARK: - Color helpers

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}
