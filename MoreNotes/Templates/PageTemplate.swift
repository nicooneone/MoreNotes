import Foundation
import CoreGraphics

/// Paper templates, similar to what GoodNotes / Notability offer.
enum PageTemplate: String, CaseIterable, Identifiable, Codable {
    case blank
    case ruledNarrow
    case ruledCollege
    case ruledWide
    case gridSmall
    case gridMedium
    case gridLarge
    case dotted
    case cornell
    case graphAxes
    case isometric
    case musicStaff
    case checklist
    case dailyPlanner
    case engineering

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: return "Blank"
        case .ruledNarrow: return "Narrow Ruled"
        case .ruledCollege: return "College Ruled"
        case .ruledWide: return "Wide Ruled"
        case .gridSmall: return "Grid 5 mm"
        case .gridMedium: return "Grid 7.5 mm"
        case .gridLarge: return "Grid 10 mm"
        case .dotted: return "Dot Grid"
        case .cornell: return "Cornell Notes"
        case .graphAxes: return "Graph with Axes"
        case .isometric: return "Isometric"
        case .musicStaff: return "Music Staff"
        case .checklist: return "Checklist"
        case .dailyPlanner: return "Daily Planner"
        case .engineering: return "Engineering"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: return "rectangle"
        case .ruledNarrow, .ruledCollege, .ruledWide: return "text.justify"
        case .gridSmall, .gridMedium, .gridLarge: return "grid"
        case .dotted: return "circle.grid.3x3"
        case .cornell: return "rectangle.split.2x2"
        case .graphAxes: return "chart.xyaxis.line"
        case .isometric: return "cube"
        case .musicStaff: return "music.note"
        case .checklist: return "checklist"
        case .dailyPlanner: return "calendar"
        case .engineering: return "ruler"
        }
    }

    /// Spacing in points where the template has a regular pitch.
    var pitch: CGFloat {
        switch self {
        case .ruledNarrow: return 20
        case .ruledCollege: return 26
        case .ruledWide: return 34
        case .gridSmall: return 14.2      // 5 mm at 72 dpi
        case .gridMedium: return 21.3     // 7.5 mm
        case .gridLarge: return 28.3      // 10 mm
        case .dotted: return 20
        case .isometric: return 24
        case .engineering: return 14.2
        default: return 26
        }
    }
}

/// Paper background colors.
enum PaperColor: String, CaseIterable, Identifiable, Codable {
    case white, cream, yellow, gray, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: return "White"
        case .cream: return "Cream"
        case .yellow: return "Legal Yellow"
        case .gray: return "Light Gray"
        case .dark: return "Dark"
        }
    }

    /// RGB 0...1
    var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .white: return (1.00, 1.00, 1.00)
        case .cream: return (0.99, 0.97, 0.91)
        case .yellow: return (1.00, 0.97, 0.78)
        case .gray: return (0.94, 0.94, 0.95)
        case .dark: return (0.11, 0.11, 0.13)
        }
    }

    /// Line color for template guides.
    var guideRGB: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        switch self {
        case .dark: return (1, 1, 1, 0.18)
        case .yellow: return (0.35, 0.55, 0.85, 0.55)
        default: return (0.45, 0.60, 0.85, 0.45)
        }
    }

    var isDark: Bool { self == .dark }
}

/// Logical page sizes in points (72 dpi).
enum PageSize: String, CaseIterable, Identifiable, Codable {
    case letter, a4, ipad, square, wide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .letter: return "US Letter"
        case .a4: return "A4"
        case .ipad: return "iPad Screen"
        case .square: return "Square"
        case .wide: return "Landscape"
        }
    }

    var size: CGSize {
        switch self {
        case .letter: return CGSize(width: 612, height: 792)
        case .a4: return CGSize(width: 595, height: 842)
        case .ipad: return CGSize(width: 810, height: 1080)
        case .square: return CGSize(width: 800, height: 800)
        case .wide: return CGSize(width: 1080, height: 810)
        }
    }
}
