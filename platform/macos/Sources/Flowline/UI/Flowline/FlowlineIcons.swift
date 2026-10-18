import SwiftUI

// MARK: - Flowline product icons — official Lucide vectors, brand-normalized.
//
// Source: Lucide official (ISC) — https://github.com/lucide-icons/lucide
// capture<-focus, steps<-list, guide<-file-text, halo<-circle-dot,
// refine<-list-checks, publish<-upload, reader<-book-open, folder<-folder,
// search<-search, check<-check, chevron<-chevron-right, replay<-rotate-ccw,
// cursor<-mouse-pointer-2. Stroke adapted 2 -> 1.75 per brand, 24-grid,
// round caps/joins, currentColor only. Logomark is custom (no official equiv).
// Canonical vectors: shared/assets/brand/flowline/icons/*.svg.
// See shared/assets/brand/flowline-tokens.json for the full token contract.

public enum FlowlineIcon: String, CaseIterable, Hashable {
    case mark
    case capture
    case steps
    case guide
    case halo
    case refine
    case publish
    case reader
    case folder
    case folderSolid
    case search
    case check
    case chevron
    case replay
    case cursor
}

/// Stroke widths from the brand sheet.
public enum FlowlineIconMetrics {
    public static let grid: CGFloat = 24
    public static let stroke: CGFloat = 1.75
    public static let markStroke: CGFloat = 2.25
    public static let minSize: CGFloat = 16
}

// MARK: - SVG strings (web export / parity). Must stay byte-identical in path data to shared SVGs.

public enum FlowlineIconSVG {
    public static let mark = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2.25\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M4 18h5v-5h6V8h5\"/></svg>"
    public static let capture = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"12\" cy=\"12\" r=\"3\" /> <path d=\"M3 7V5a2 2 0 0 1 2-2h2\" /> <path d=\"M17 3h2a2 2 0 0 1 2 2v2\" /> <path d=\"M21 17v2a2 2 0 0 1-2 2h-2\" /> <path d=\"M7 21H5a2 2 0 0 1-2-2v-2\" /></svg>"
    public static let steps = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M3 5h.01\" /> <path d=\"M3 12h.01\" /> <path d=\"M3 19h.01\" /> <path d=\"M8 5h13\" /> <path d=\"M8 12h13\" /> <path d=\"M8 19h13\" /></svg>"
    public static let guide = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z\" /> <path d=\"M14 2v5a1 1 0 0 0 1 1h5\" /> <path d=\"M10 9H8\" /> <path d=\"M16 13H8\" /> <path d=\"M16 17H8\" /></svg>"
    public static let halo = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><circle cx=\"12\" cy=\"12\" r=\"1\" /> <circle cx=\"12\" cy=\"12\" r=\"10\" /></svg>"
    public static let refine = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M13 5h8\" /> <path d=\"M13 12h8\" /> <path d=\"M13 19h8\" /> <path d=\"m3 17 2 2 4-4\" /> <path d=\"m3 7 2 2 4-4\" /></svg>"
    public static let publish = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 3v12\" /> <path d=\"m17 8-5-5-5 5\" /> <path d=\"M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4\" /></svg>"
    public static let reader = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M12 5v16\" /> <path d=\"M20.001 19A2 2 0 0022 17V5a2 2 0 00-1.999-2L16 3.002A5 5 0 0012 5a5 5 0 00-4-2H4a2 2 0 00-2 2v12a2 2 0 001.999 2H8a5 5 0 014 2 5 5 0 014-2z\" /></svg>"
    public static let folder = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z\" /></svg>"
    public static let folderSolid = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\" fill-opacity=\"0.12\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z\" /></svg>"
    public static let search = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"m21 21-4.34-4.34\" /> <circle cx=\"11\" cy=\"11\" r=\"8\" /></svg>"
    public static let check = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M20 6 9 17l-5-5\" /></svg>"
    public static let chevron = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"m9 18 6-6-6-6\" /></svg>"
    public static let replay = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8\" /> <path d=\"M3 3v5h5\" /></svg>"
    public static let cursor = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.75\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M4.037 4.688a.495.495 0 0 1 .651-.651l16 6.5a.5.5 0 0 1-.063.947l-6.124 1.58a2 2 0 0 0-1.438 1.435l-1.579 6.126a.5.5 0 0 1-.947.063z\" /></svg>"

    public static func svg(for icon: FlowlineIcon) -> String {
        switch icon {
        case .mark: return mark
        case .capture: return capture
        case .steps: return steps
        case .guide: return guide
        case .halo: return halo
        case .refine: return refine
        case .publish: return publish
        case .reader: return reader
        case .folder: return folder
        case .folderSolid: return folderSolid
        case .search: return search
        case .check: return check
        case .chevron: return chevron
        case .replay: return replay
        case .cursor: return cursor
        }
    }
}

// MARK: - SwiftUI renderer (stroke scales proportionally, never below 16pt)
// Vectors mirror Lucide official path data (see shared SVGs).
// Complex beziers (guide/reader/folder/cursor) are visually-close
// approximations — SVG files remain the source of truth for export.

public struct FlowlineIconView: View {
    public let icon: FlowlineIcon
    public let size: CGFloat

    public init(_ icon: FlowlineIcon, size: CGFloat = 24) {
        self.icon = icon
        self.size = max(size, FlowlineIconMetrics.minSize)
    }

    private var lineWidth: CGFloat {
        let base = icon == .mark ? FlowlineIconMetrics.markStroke : FlowlineIconMetrics.stroke
        return base * size / FlowlineIconMetrics.grid
    }

    public var body: some View {
        ZStack {
            if icon == .halo {
                haloBody
            } else if icon == .steps {
                strokeBody
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            } else {
                strokeBody
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var scale: CGFloat { size / FlowlineIconMetrics.grid }
    private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }

    private var strokeBody: Path {
        var p = Path()
        switch icon {
        case .mark:
            p.move(to: P(4, 18)); p.addLine(to: P(9, 18)); p.addLine(to: P(9, 13)); p.addLine(to: P(15, 13)); p.addLine(to: P(15, 8)); p.addLine(to: P(20, 8))
        case .capture:
            // Lucide focus — corners + center circle r3
            p.move(to: P(3, 7)); p.addLine(to: P(3, 5)); p.addRelativeArc(center: P(5, 5), radius: 2*scale, startAngle: .degrees(180), delta: .degrees(90))
            p.addLine(to: P(7, 3))
            p.move(to: P(17, 3)); p.addLine(to: P(19, 3)); p.addRelativeArc(center: P(19, 5), radius: 2*scale, startAngle: .degrees(270), delta: .degrees(90))
            p.addLine(to: P(21, 7))
            p.move(to: P(21, 17)); p.addLine(to: P(21, 19)); p.addRelativeArc(center: P(19, 19), radius: 2*scale, startAngle: .degrees(0), delta: .degrees(90))
            p.addLine(to: P(17, 21))
            p.move(to: P(7, 21)); p.addLine(to: P(5, 21)); p.addRelativeArc(center: P(5, 19), radius: 2*scale, startAngle: .degrees(90), delta: .degrees(90))
            p.addLine(to: P(3, 17))
            p.addEllipse(in: CGRect(origin: P(9, 9), size: CGSize(width: 6*scale, height: 6*scale)))
        case .steps:
            // Lucide list — dots as short round-cap strokes + 3 rules
            p.move(to: P(3, 5)); p.addLine(to: P(3.01, 5))
            p.move(to: P(3, 12)); p.addLine(to: P(3.01, 12))
            p.move(to: P(3, 19)); p.addLine(to: P(3.01, 19))
            p.move(to: P(8, 5)); p.addLine(to: P(21, 5))
            p.move(to: P(8, 12)); p.addLine(to: P(21, 12))
            p.move(to: P(8, 19)); p.addLine(to: P(21, 19))
        case .guide:
            // Lucide file-text (approx — outer 2r corners, fold, 3 rules)
            p.move(to: P(15, 2)); p.addLine(to: P(6, 2)); p.addRelativeArc(center: P(6, 4), radius: 2*scale, startAngle: .degrees(270), delta: .degrees(90))
            p.addLine(to: P(4, 20)); p.addRelativeArc(center: P(6, 20), radius: 2*scale, startAngle: .degrees(180), delta: .degrees(90))
            p.addLine(to: P(18, 22)); p.addRelativeArc(center: P(18, 20), radius: 2*scale, startAngle: .degrees(90), delta: .degrees(90))
            p.addLine(to: P(20, 8)); p.addLine(to: P(15, 2)); p.closeSubpath()
            p.move(to: P(14, 2)); p.addLine(to: P(14, 6)); p.addLine(to: P(18, 6))
            p.move(to: P(10, 9)); p.addLine(to: P(8, 9))
            p.move(to: P(16, 13)); p.addLine(to: P(8, 13))
            p.move(to: P(16, 17)); p.addLine(to: P(8, 17))
        case .refine:
            // Lucide list-checks — 3 right rules + 2 left checks
            p.move(to: P(13, 5)); p.addLine(to: P(21, 5))
            p.move(to: P(13, 12)); p.addLine(to: P(21, 12))
            p.move(to: P(13, 19)); p.addLine(to: P(21, 19))
            p.move(to: P(3, 7)); p.addLine(to: P(5, 9)); p.addLine(to: P(9, 5))
            p.move(to: P(3, 17)); p.addLine(to: P(5, 19)); p.addLine(to: P(9, 15))
        case .publish:
            // Lucide upload — stem, head, 2r tray
            p.move(to: P(12, 3)); p.addLine(to: P(12, 15))
            p.move(to: P(17, 8)); p.addLine(to: P(12, 3)); p.addLine(to: P(7, 8))
            p.move(to: P(21, 15)); p.addLine(to: P(21, 19))
            p.addRelativeArc(center: P(19, 19), radius: 2*scale, startAngle: .degrees(0), delta: .degrees(90))
            p.addLine(to: P(5, 21))
            p.addRelativeArc(center: P(5, 19), radius: 2*scale, startAngle: .degrees(90), delta: .degrees(90))
            p.addLine(to: P(3, 15))
        case .reader:
            // Lucide book-open (approx — spine + rounded covers)
            p.move(to: P(12, 5)); p.addLine(to: P(12, 21))
            p.move(to: P(12, 5)); p.addCurve(to: P(4, 3), control1: P(9, 3), control2: P(6, 3))
            p.addLine(to: P(2, 3)); p.addRelativeArc(center: P(2, 5), radius: 2*scale, startAngle: .degrees(180), delta: .degrees(90))
            p.addLine(to: P(2, 17)); p.addRelativeArc(center: P(4, 17), radius: 2*scale, startAngle: .degrees(180), delta: .degrees(-90))
            p.addLine(to: P(8, 19)); p.addCurve(to: P(12, 21), control1: P(10, 19), control2: P(11, 20))
            p.move(to: P(12, 5)); p.addCurve(to: P(20, 3), control1: P(15, 3), control2: P(18, 3))
            p.addLine(to: P(22, 3)); p.addRelativeArc(center: P(22, 5), radius: 2*scale, startAngle: .degrees(0), delta: .degrees(-90))
            p.addLine(to: P(22, 17)); p.addRelativeArc(center: P(20, 17), radius: 2*scale, startAngle: .degrees(0), delta: .degrees(90))
            p.addLine(to: P(16, 19)); p.addCurve(to: P(12, 21), control1: P(14, 19), control2: P(13, 20))
        case .folder, .folderSolid:
            // Lucide folder — tab + 2r body
            p.move(to: P(20, 20)); p.addLine(to: P(20, 8)); p.addRelativeArc(center: P(18, 8), radius: 2*scale, startAngle: .degrees(0), delta: .degrees(-90))
            p.addLine(to: P(12.1, 6)); p.addRelativeArc(center: P(12.1, 8), radius: 2*scale, startAngle: .degrees(270), delta: .degrees(-45))
            p.addLine(to: P(9.6, 3.9)); p.addRelativeArc(center: P(7.93, 3.9), radius: 2*scale, startAngle: .degrees(20), delta: .degrees(-110))
            p.addLine(to: P(4, 3)); p.addRelativeArc(center: P(4, 5), radius: 2*scale, startAngle: .degrees(180), delta: .degrees(90))
            p.addLine(to: P(2, 18)); p.addRelativeArc(center: P(4, 18), radius: 2*scale, startAngle: .degrees(180), delta: .degrees(90))
            p.addLine(to: P(18, 20)); p.addRelativeArc(center: P(18, 18), radius: 2*scale, startAngle: .degrees(90), delta: .degrees(90))
            p.closeSubpath()
        case .search:
            // Lucide search — r8 circle + tail
            p.addEllipse(in: CGRect(origin: P(3, 3), size: CGSize(width: 16*scale, height: 16*scale)))
            p.move(to: P(21, 21)); p.addLine(to: P(16.66, 16.66))
        case .check:
            // Lucide check
            p.move(to: P(20, 6)); p.addLine(to: P(9, 17)); p.addLine(to: P(4, 12))
        case .chevron:
            // Lucide chevron-right
            p.move(to: P(9, 18)); p.addLine(to: P(15, 12)); p.addLine(to: P(9, 6))
        case .replay:
            // Lucide rotate-ccw — 9r arc + top-left arrow
            p.addArc(center: P(12, 12), radius: 9*scale, startAngle: .degrees(35), endAngle: .degrees(270), clockwise: false)
            p.move(to: P(3, 3)); p.addLine(to: P(3, 8)); p.addLine(to: P(8, 8))
        case .cursor:
            // Lucide mouse-pointer-2 (approx — pointer polygon)
            p.move(to: P(4.04, 4.69)); p.addLine(to: P(20.04, 11.19)); p.addLine(to: P(13.92, 12.77)); p.addLine(to: P(12.34, 18.89)); p.addLine(to: P(10.76, 18.26)); p.addLine(to: P(12.34, 12.14)); p.addLine(to: P(6.22, 10.56)); p.closeSubpath()
        default:
            break
        }
        return p
    }

    private var haloBody: some View {
        // Lucide circle-dot — r10 ring + r1 dot
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: 20*scale, height: 20*scale)
            Circle()
                .fill(Color.primary)
                .frame(width: 2*scale, height: 2*scale)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Logomark lockup helper

public struct FlowlineLockup: View {
    public let wordmark: String
    public let markSize: CGFloat
    public let fontSize: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(wordmark: String = "Flowline", markSize: CGFloat = 24, fontSize: CGFloat = 22) {
        self.wordmark = wordmark
        self.markSize = markSize
        self.fontSize = fontSize
    }

    public var body: some View {
        HStack(spacing: 8) {
            FlowlineIconView(.mark, size: markSize)
            Text(wordmark)
                .font(.system(size: fontSize, weight: .semibold))
                .tracking(-0.02 * fontSize)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(wordmark) logomark")
    }
}
