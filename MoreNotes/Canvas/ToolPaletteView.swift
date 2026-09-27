import SwiftUI
import PencilKit

/// The floating toolbar: brushes, eraser, lasso, ruler, colors, size/opacity,
/// presets, undo/redo. Designed for a 10.2" iPad in either orientation.
struct ToolPaletteView: View {
    @Bindable var tools: ToolState
    var canUndo: Bool
    var canRedo: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClearPage: () -> Void

    @State private var showBrushPicker = false
    @State private var showEraserPicker = false
    @State private var showSizePicker = false
    @State private var showPresets = false
    @State private var confirmClear = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!canUndo)
                Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!canRedo)
            }
            .buttonStyle(PaletteButtonStyle(active: false))

            Divider().frame(height: 26)

            // Brush
            Button {
                if tools.mode == .draw { showBrushPicker.toggle() } else { tools.mode = .draw }
            } label: {
                Image(systemName: tools.brush.systemImage)
            }
            .buttonStyle(PaletteButtonStyle(active: tools.mode == .draw))
            .popover(isPresented: $showBrushPicker, arrowEdge: .top) { brushPicker }

            // Eraser
            Button {
                if tools.mode == .erase { showEraserPicker.toggle() } else { tools.mode = .erase }
            } label: {
                Image(systemName: tools.eraser.systemImage)
            }
            .buttonStyle(PaletteButtonStyle(active: tools.mode == .erase))
            .popover(isPresented: $showEraserPicker, arrowEdge: .top) { eraserPicker }

            // Lasso
            Button { tools.mode = .lasso } label: { Image(systemName: "lasso") }
                .buttonStyle(PaletteButtonStyle(active: tools.mode == .lasso))

            // Ruler
            Button { tools.rulerActive.toggle() } label: { Image(systemName: "ruler") }
                .buttonStyle(PaletteButtonStyle(active: tools.rulerActive))

            Divider().frame(height: 26)

            // Size / opacity
            Button { showSizePicker.toggle() } label: {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.08))
                    Circle()
                        .fill(tools.mode == .erase ? Color.secondary : tools.color.opacity(tools.opacity))
                        .frame(width: sizeDotDiameter, height: sizeDotDiameter)
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(PaletteButtonStyle(active: false))
            .popover(isPresented: $showSizePicker, arrowEdge: .top) { sizePicker }

            // Color swatches (compact)
            ForEach(quickSwatches, id: \.self) { hex in
                let c = Color(hex: hex) ?? .black
                Button {
                    tools.color = c
                    if tools.mode != .draw { tools.mode = .draw }
                } label: {
                    Circle()
                        .fill(c)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                        .overlay {
                            if tools.color.hexString == hex && tools.mode == .draw {
                                Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-3)
                            }
                        }
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            ColorPicker("", selection: $tools.color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28)

            Divider().frame(height: 26)

            // Presets
            Button { showPresets.toggle() } label: { Image(systemName: "star") }
                .buttonStyle(PaletteButtonStyle(active: false))
                .popover(isPresented: $showPresets, arrowEdge: .top) { presetPicker }

            Menu {
                Button(role: .destructive) { confirmClear = true } label: {
                    Label("Clear Page", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .confirmationDialog("Clear all ink on this page?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Page", role: .destructive, action: onClearPage)
        }
    }

    private var quickSwatches: [String] {
        Array(Swatches.all.prefix(6))
    }

    private var sizeDotDiameter: CGFloat {
        let w = tools.mode == .erase ? tools.eraserWidth : tools.width
        return min(22, max(4, w * 0.9))
    }

    // MARK: - Popovers

    private var brushPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Brush").font(.headline)
            ForEach(BrushKind.allCases) { kind in
                Button {
                    tools.select(brush: kind)
                } label: {
                    HStack {
                        Image(systemName: kind.systemImage).frame(width: 24)
                        Text(kind.displayName)
                        Spacer()
                        if tools.brush == kind { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
            sizeControls
        }
        .padding()
        .frame(width: 280)
    }

    private var eraserPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eraser").font(.headline)
            ForEach(EraserKind.allCases) { kind in
                Button { tools.eraser = kind } label: {
                    HStack {
                        Image(systemName: kind.systemImage).frame(width: 24)
                        Text(kind.displayName)
                        Spacer()
                        if tools.eraser == kind { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if tools.eraser != .stroke {
                Divider()
                LabeledContent("Size") {
                    Slider(value: Binding(get: { Double(tools.eraserWidth) }, set: { tools.eraserWidth = CGFloat($0) }),
                           in: 4...80)
                }
                Text("\(Int(tools.eraserWidth)) pt").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var sizePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tools.mode == .erase ? "Eraser Size" : "Stroke").font(.headline)
            if tools.mode == .erase {
                Slider(value: Binding(get: { Double(tools.eraserWidth) }, set: { tools.eraserWidth = CGFloat($0) }), in: 4...80)
            } else {
                sizeControls
                Divider()
                Text("Colors").font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 8), spacing: 8) {
                    ForEach(Swatches.all, id: \.self) { hex in
                        let c = Color(hex: hex) ?? .black
                        Button { tools.color = c } label: {
                            Circle().fill(c)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .frame(width: 300)
    }

    private var sizeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            let range = tools.brush.widthRange
            LabeledContent("Width") {
                Slider(value: Binding(get: { Double(tools.width) }, set: { tools.width = CGFloat($0) }),
                       in: Double(range.lowerBound)...Double(range.upperBound))
            }
            LabeledContent("Opacity") {
                Slider(value: $tools.opacity, in: 0.1...1)
            }
            // Live stroke preview
            StrokePreview(color: tools.color.opacity(tools.opacity), width: tools.width)
                .frame(height: 36)
        }
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Favorites").font(.headline)
                Spacer()
                Button { tools.saveCurrentAsPreset() } label: { Label("Save current", systemImage: "plus") }
                    .font(.caption)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 6), spacing: 8) {
                ForEach(tools.presets) { preset in
                    Button { tools.apply(preset: preset) } label: {
                        VStack(spacing: 2) {
                            Image(systemName: preset.brush.systemImage)
                                .foregroundStyle(Color(hex: preset.colorHex) ?? .black)
                            Text("\(Int(preset.width))").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .frame(width: 40, height: 40)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { tools.removePreset(preset) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
        }
        .padding()
        .frame(width: 320)
    }
}

/// A wavy line drawn with the current width/color so the user can see the stroke before drawing.
struct StrokePreview: View {
    var color: Color
    var width: CGFloat

    var body: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height
                p.move(to: CGPoint(x: 8, y: h * 0.6))
                p.addCurve(to: CGPoint(x: w - 8, y: h * 0.5),
                           control1: CGPoint(x: w * 0.3, y: -h * 0.2),
                           control2: CGPoint(x: w * 0.7, y: h * 1.2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: min(width, 30), lineCap: .round))
        }
    }
}

struct PaletteButtonStyle: ButtonStyle {
    var active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .frame(width: 36, height: 36)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(active ? Color.accentColor : Color.primary.opacity(configuration.isPressed ? 0.12 : 0),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
    }
}
