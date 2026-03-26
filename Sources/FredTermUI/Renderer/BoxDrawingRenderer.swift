#if canImport(CoreGraphics) && canImport(MetalKit)
import CoreGraphics
import Foundation

/// Programmatic renderer for Unicode box drawing characters (U+2500-U+257F)
/// and block elements (U+2580-U+259F).
///
/// Instead of relying on font glyphs (which often have alignment issues at
/// terminal cell boundaries), this renderer draws them pixel-perfectly using
/// CoreGraphics, producing grayscale bitmap data compatible with GlyphRasterizer
/// output.
@MainActor
final class BoxDrawingRenderer {

    /// Returns true if the given code point should be rendered programmatically
    /// rather than via the font.
    static func isBoxDrawingCharacter(_ codePoint: UInt32) -> Bool {
        // Box Drawing: U+2500-U+257F
        // Block Elements: U+2580-U+259F
        return (codePoint >= 0x2500 && codePoint <= 0x257F) ||
               (codePoint >= 0x2580 && codePoint <= 0x259F)
    }

    /// Rasterize a box drawing or block element character.
    ///
    /// Returns a `RasterizedGlyph` with grayscale pixel data sized exactly
    /// to the cell dimensions, or `nil` if the code point is not handled.
    static func rasterize(
        codePoint: UInt32,
        cellWidth: Int,
        cellHeight: Int
    ) -> RasterizedGlyph? {
        guard isBoxDrawingCharacter(codePoint) else { return nil }
        guard cellWidth > 0 && cellHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: cellWidth,
            height: cellHeight,
            bitsPerComponent: 8,
            bytesPerRow: cellWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        // Clear to black (transparent for grayscale atlas).
        context.setFillColor(CGColor(gray: 0.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight))

        // Draw white shapes.
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
        context.setShouldAntialias(true)

        let w = CGFloat(cellWidth)
        let h = CGFloat(cellHeight)

        if codePoint >= 0x2580 && codePoint <= 0x259F {
            drawBlockElement(context: context, codePoint: codePoint, w: w, h: h)
        } else {
            drawBoxDrawing(context: context, codePoint: codePoint, w: w, h: h)
        }

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: cellWidth * cellHeight)
        let pixelData = Array(UnsafeBufferPointer(start: buffer, count: cellWidth * cellHeight))

        return RasterizedGlyph(
            data: pixelData,
            width: cellWidth,
            height: cellHeight,
            bearingX: 0,
            bearingY: CGFloat(cellHeight),
            isColored: false
        )
    }

    // MARK: - Block Elements (U+2580-U+259F)

    private static func drawBlockElement(
        context: CGContext,
        codePoint: UInt32,
        w: CGFloat,
        h: CGFloat
    ) {
        switch codePoint {
        case 0x2580: // ▀ UPPER HALF BLOCK
            context.fill(CGRect(x: 0, y: h / 2, width: w, height: h / 2))

        case 0x2581: // ▁ LOWER ONE EIGHTH BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w, height: h / 8))

        case 0x2582: // ▂ LOWER ONE QUARTER BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w, height: h / 4))

        case 0x2583: // ▃ LOWER THREE EIGHTHS BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w, height: 3 * h / 8))

        case 0x2584: // ▄ LOWER HALF BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w, height: h / 2))

        case 0x2585: // ▅ LOWER FIVE EIGHTHS BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w, height: 5 * h / 8))

        case 0x2586: // ▆ LOWER THREE QUARTERS BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w, height: 3 * h / 4))

        case 0x2587: // ▇ LOWER SEVEN EIGHTHS BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w, height: 7 * h / 8))

        case 0x2588: // █ FULL BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        case 0x2589: // ▉ LEFT SEVEN EIGHTHS BLOCK
            context.fill(CGRect(x: 0, y: 0, width: 7 * w / 8, height: h))

        case 0x258A: // ▊ LEFT THREE QUARTERS BLOCK
            context.fill(CGRect(x: 0, y: 0, width: 3 * w / 4, height: h))

        case 0x258B: // ▋ LEFT FIVE EIGHTHS BLOCK
            context.fill(CGRect(x: 0, y: 0, width: 5 * w / 8, height: h))

        case 0x258C: // ▌ LEFT HALF BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))

        case 0x258D: // ▍ LEFT THREE EIGHTHS BLOCK
            context.fill(CGRect(x: 0, y: 0, width: 3 * w / 8, height: h))

        case 0x258E: // ▎ LEFT ONE QUARTER BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w / 4, height: h))

        case 0x258F: // ▏ LEFT ONE EIGHTH BLOCK
            context.fill(CGRect(x: 0, y: 0, width: w / 8, height: h))

        case 0x2590: // ▐ RIGHT HALF BLOCK
            context.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h))

        case 0x2591: // ░ LIGHT SHADE (25%)
            drawShade(context: context, w: w, h: h, density: 0.25)

        case 0x2592: // ▒ MEDIUM SHADE (50%)
            drawShade(context: context, w: w, h: h, density: 0.50)

        case 0x2593: // ▓ DARK SHADE (75%)
            drawShade(context: context, w: w, h: h, density: 0.75)

        case 0x2594: // ▔ UPPER ONE EIGHTH BLOCK
            context.fill(CGRect(x: 0, y: 7 * h / 8, width: w, height: h / 8))

        case 0x2595: // ▕ RIGHT ONE EIGHTH BLOCK
            context.fill(CGRect(x: 7 * w / 8, y: 0, width: w / 8, height: h))

        case 0x2596: // ▖ QUADRANT LOWER LEFT
            context.fill(CGRect(x: 0, y: 0, width: w / 2, height: h / 2))

        case 0x2597: // ▗ QUADRANT LOWER RIGHT
            context.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2))

        case 0x2598: // ▘ QUADRANT UPPER LEFT
            context.fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))

        case 0x2599: // ▙ QUADRANT UPPER LEFT AND LOWER LEFT AND LOWER RIGHT
            context.fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h / 2))

        case 0x259A: // ▚ QUADRANT UPPER LEFT AND LOWER RIGHT
            context.fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))
            context.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2))

        case 0x259B: // ▛ QUADRANT UPPER LEFT AND UPPER RIGHT AND LOWER LEFT
            context.fill(CGRect(x: 0, y: h / 2, width: w, height: h / 2))
            context.fill(CGRect(x: 0, y: 0, width: w / 2, height: h / 2))

        case 0x259C: // ▜ QUADRANT UPPER LEFT AND UPPER RIGHT AND LOWER RIGHT
            context.fill(CGRect(x: 0, y: h / 2, width: w, height: h / 2))
            context.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2))

        case 0x259D: // ▝ QUADRANT UPPER RIGHT
            context.fill(CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2))

        case 0x259E: // ▞ QUADRANT UPPER RIGHT AND LOWER LEFT
            context.fill(CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2))
            context.fill(CGRect(x: 0, y: 0, width: w / 2, height: h / 2))

        case 0x259F: // ▟ QUADRANT UPPER RIGHT AND LOWER LEFT AND LOWER RIGHT
            context.fill(CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h / 2))

        default:
            break
        }
    }

    /// Draw a shade pattern by filling the entire cell with a gray value.
    private static func drawShade(
        context: CGContext,
        w: CGFloat,
        h: CGFloat,
        density: CGFloat
    ) {
        context.setFillColor(CGColor(gray: density, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }

    // MARK: - Box Drawing Characters (U+2500-U+257F)

    private static func drawBoxDrawing(
        context: CGContext,
        codePoint: UInt32,
        w: CGFloat,
        h: CGFloat
    ) {
        let cx = floor(w / 2) + 0.5
        let cy = floor(h / 2) + 0.5

        let lightWidth: CGFloat = max(1, floor(w / 8))
        let heavyWidth: CGFloat = max(2, floor(w / 4))

        // Determine which segments to draw based on the code point.
        // Each box drawing character is a combination of segments:
        // right, left, down, up with light/heavy/double/dashed weight.
        // Handle diagonal lines as special cases.
        if codePoint >= 0x2571 && codePoint <= 0x2573 {
            context.setLineWidth(lightWidth)
            context.setLineCap(.butt)
            if codePoint == 0x2571 || codePoint == 0x2573 {
                // ╱ diagonal from bottom-left to top-right
                context.move(to: CGPoint(x: 0, y: 0))
                context.addLine(to: CGPoint(x: w, y: h))
                context.strokePath()
            }
            if codePoint == 0x2572 || codePoint == 0x2573 {
                // ╲ diagonal from top-left to bottom-right
                context.move(to: CGPoint(x: 0, y: h))
                context.addLine(to: CGPoint(x: w, y: 0))
                context.strokePath()
            }
            return
        }

        let segments = boxSegments(for: codePoint)

        for seg in segments {
            let lineWidth: CGFloat
            switch seg.weight {
            case .light: lineWidth = lightWidth
            case .heavy: lineWidth = heavyWidth
            case .double: lineWidth = lightWidth
            }

            context.setLineWidth(lineWidth)
            context.setLineCap(.butt)
            context.setLineDash(phase: 0, lengths: dashPattern(for: seg.dash, cellW: w, cellH: h))

            if seg.weight == .double {
                // Double lines: draw two parallel lines with a gap.
                let gap = max(2, floor(w / 5))
                drawDoubleSegment(context: context, seg: seg, cx: cx, cy: cy,
                                  w: w, h: h, lineWidth: lineWidth, gap: gap)
            } else {
                drawSingleSegment(context: context, seg: seg, cx: cx, cy: cy,
                                  w: w, h: h)
            }
        }
    }

    // MARK: - Segment Model

    enum SegmentDirection {
        case right, left, down, up
    }

    enum SegmentWeight {
        case light, heavy, double
    }

    enum SegmentDash {
        case solid
        case triple   // ┄ ┆ (3 dashes)
        case quadruple // ┈ ┊ (4 dashes)
        case double   // ╌ ╎ (2 dashes)
    }

    struct Segment {
        let direction: SegmentDirection
        let weight: SegmentWeight
        let dash: SegmentDash
    }

    private static func drawSingleSegment(
        context: CGContext,
        seg: Segment,
        cx: CGFloat,
        cy: CGFloat,
        w: CGFloat,
        h: CGFloat
    ) {
        let (startPt, endPt) = segmentEndpoints(seg: seg, cx: cx, cy: cy, w: w, h: h)
        context.move(to: startPt)
        context.addLine(to: endPt)
        context.strokePath()
    }

    private static func drawDoubleSegment(
        context: CGContext,
        seg: Segment,
        cx: CGFloat,
        cy: CGFloat,
        w: CGFloat,
        h: CGFloat,
        lineWidth: CGFloat,
        gap: CGFloat
    ) {
        let offset = (gap + lineWidth) / 2

        switch seg.direction {
        case .right:
            context.move(to: CGPoint(x: cx, y: cy - offset))
            context.addLine(to: CGPoint(x: w, y: cy - offset))
            context.strokePath()
            context.move(to: CGPoint(x: cx, y: cy + offset))
            context.addLine(to: CGPoint(x: w, y: cy + offset))
            context.strokePath()
        case .left:
            context.move(to: CGPoint(x: 0, y: cy - offset))
            context.addLine(to: CGPoint(x: cx, y: cy - offset))
            context.strokePath()
            context.move(to: CGPoint(x: 0, y: cy + offset))
            context.addLine(to: CGPoint(x: cx, y: cy + offset))
            context.strokePath()
        case .down:
            context.move(to: CGPoint(x: cx - offset, y: 0))
            context.addLine(to: CGPoint(x: cx - offset, y: cy))
            context.strokePath()
            context.move(to: CGPoint(x: cx + offset, y: 0))
            context.addLine(to: CGPoint(x: cx + offset, y: cy))
            context.strokePath()
        case .up:
            context.move(to: CGPoint(x: cx - offset, y: cy))
            context.addLine(to: CGPoint(x: cx - offset, y: h))
            context.strokePath()
            context.move(to: CGPoint(x: cx + offset, y: cy))
            context.addLine(to: CGPoint(x: cx + offset, y: h))
            context.strokePath()
        }
    }

    private static func segmentEndpoints(
        seg: Segment,
        cx: CGFloat,
        cy: CGFloat,
        w: CGFloat,
        h: CGFloat
    ) -> (CGPoint, CGPoint) {
        switch seg.direction {
        case .right:
            return (CGPoint(x: cx, y: cy), CGPoint(x: w, y: cy))
        case .left:
            return (CGPoint(x: 0, y: cy), CGPoint(x: cx, y: cy))
        case .down:
            // In CoreGraphics, y=0 is bottom, so "down" visually = towards y=0
            return (CGPoint(x: cx, y: 0), CGPoint(x: cx, y: cy))
        case .up:
            // "up" visually = towards y=h
            return (CGPoint(x: cx, y: cy), CGPoint(x: cx, y: h))
        }
    }

    private static func dashPattern(
        for dash: SegmentDash,
        cellW: CGFloat,
        cellH: CGFloat
    ) -> [CGFloat] {
        let unit = max(cellW, cellH) / 2
        switch dash {
        case .solid:
            return []
        case .triple:
            let seg = unit / 3
            return [seg * 0.6, seg * 0.4]
        case .quadruple:
            let seg = unit / 4
            return [seg * 0.5, seg * 0.5]
        case .double:
            let seg = unit / 2
            return [seg * 0.6, seg * 0.4]
        }
    }

    // MARK: - Code Point to Segment Mapping

    /// Map a box drawing code point to its constituent line segments.
    private static func boxSegments(for codePoint: UInt32) -> [Segment] {
        switch codePoint {
        // Light lines
        case 0x2500: // ─ BOX DRAWINGS LIGHT HORIZONTAL
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x2501: // ━ BOX DRAWINGS HEAVY HORIZONTAL
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x2502: // │ BOX DRAWINGS LIGHT VERTICAL
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x2503: // ┃ BOX DRAWINGS HEAVY VERTICAL
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid)]

        // Dashed lines - triple dash
        case 0x2504: // ┄ LIGHT TRIPLE DASH HORIZONTAL
            return [Segment(direction: .left, weight: .light, dash: .triple),
                    Segment(direction: .right, weight: .light, dash: .triple)]
        case 0x2505: // ┅ HEAVY TRIPLE DASH HORIZONTAL
            return [Segment(direction: .left, weight: .heavy, dash: .triple),
                    Segment(direction: .right, weight: .heavy, dash: .triple)]
        case 0x2506: // ┆ LIGHT TRIPLE DASH VERTICAL
            return [Segment(direction: .up, weight: .light, dash: .triple),
                    Segment(direction: .down, weight: .light, dash: .triple)]
        case 0x2507: // ┇ HEAVY TRIPLE DASH VERTICAL
            return [Segment(direction: .up, weight: .heavy, dash: .triple),
                    Segment(direction: .down, weight: .heavy, dash: .triple)]

        // Dashed lines - quadruple dash
        case 0x2508: // ┈ LIGHT QUADRUPLE DASH HORIZONTAL
            return [Segment(direction: .left, weight: .light, dash: .quadruple),
                    Segment(direction: .right, weight: .light, dash: .quadruple)]
        case 0x2509: // ┉ HEAVY QUADRUPLE DASH HORIZONTAL
            return [Segment(direction: .left, weight: .heavy, dash: .quadruple),
                    Segment(direction: .right, weight: .heavy, dash: .quadruple)]
        case 0x250A: // ┊ LIGHT QUADRUPLE DASH VERTICAL
            return [Segment(direction: .up, weight: .light, dash: .quadruple),
                    Segment(direction: .down, weight: .light, dash: .quadruple)]
        case 0x250B: // ┋ HEAVY QUADRUPLE DASH VERTICAL
            return [Segment(direction: .up, weight: .heavy, dash: .quadruple),
                    Segment(direction: .down, weight: .heavy, dash: .quadruple)]

        // Light corners
        case 0x250C: // ┌ BOX DRAWINGS LIGHT DOWN AND RIGHT
            return [Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x250D: // ┍ LIGHT DOWN AND HEAVY RIGHT
            return [Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x250E: // ┎ HEAVY DOWN AND LIGHT RIGHT
            return [Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid)]
        case 0x250F: // ┏ HEAVY DOWN AND RIGHT
            return [Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid)]

        case 0x2510: // ┐ LIGHT DOWN AND LEFT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x2511: // ┑ LIGHT DOWN AND HEAVY LEFT
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x2512: // ┒ HEAVY DOWN AND LIGHT LEFT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid)]
        case 0x2513: // ┓ HEAVY DOWN AND LEFT
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid)]

        case 0x2514: // └ LIGHT UP AND RIGHT
            return [Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2515: // ┕ LIGHT UP AND HEAVY RIGHT
            return [Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2516: // ┖ HEAVY UP AND LIGHT RIGHT
            return [Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .heavy, dash: .solid)]
        case 0x2517: // ┗ HEAVY UP AND RIGHT
            return [Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .up, weight: .heavy, dash: .solid)]

        case 0x2518: // ┘ LIGHT UP AND LEFT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2519: // ┙ LIGHT UP AND HEAVY LEFT
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x251A: // ┚ HEAVY UP AND LIGHT LEFT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .heavy, dash: .solid)]
        case 0x251B: // ┛ HEAVY UP AND LEFT
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .up, weight: .heavy, dash: .solid)]

        // T-junctions
        case 0x251C: // ├ LIGHT VERTICAL AND RIGHT
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x251D: // ┝ VERTICAL LIGHT AND RIGHT HEAVY
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x251E: // ┞ UP HEAVY AND RIGHT DOWN LIGHT
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x251F: // ┟ DOWN HEAVY AND RIGHT UP LIGHT
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x2520: // ┠ VERTICAL HEAVY AND RIGHT LIGHT
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x2521: // ┡ DOWN LIGHT AND RIGHT UP HEAVY
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x2522: // ┢ UP LIGHT AND RIGHT DOWN HEAVY
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x2523: // ┣ HEAVY VERTICAL AND RIGHT
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]

        case 0x2524: // ┤ LIGHT VERTICAL AND LEFT
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid)]
        case 0x2525: // ┥ VERTICAL LIGHT AND LEFT HEAVY
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid)]
        case 0x2526: // ┦ UP HEAVY AND LEFT DOWN LIGHT
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid)]
        case 0x2527: // ┧ DOWN HEAVY AND LEFT UP LIGHT
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid)]
        case 0x2528: // ┨ VERTICAL HEAVY AND LEFT LIGHT
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid)]
        case 0x2529: // ┩ DOWN LIGHT AND LEFT UP HEAVY
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid)]
        case 0x252A: // ┪ UP LIGHT AND LEFT DOWN HEAVY
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid)]
        case 0x252B: // ┫ HEAVY VERTICAL AND LEFT
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid)]

        // Top T-junctions
        case 0x252C: // ┬ LIGHT DOWN AND HORIZONTAL
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x252D: // ┭ LEFT HEAVY AND RIGHT DOWN LIGHT
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x252E: // ┮ RIGHT HEAVY AND LEFT DOWN LIGHT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x252F: // ┯ DOWN LIGHT AND HORIZONTAL HEAVY
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x2530: // ┰ DOWN HEAVY AND HORIZONTAL LIGHT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid)]
        case 0x2531: // ┱ RIGHT LIGHT AND LEFT DOWN HEAVY
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid)]
        case 0x2532: // ┲ LEFT LIGHT AND RIGHT DOWN HEAVY
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid)]
        case 0x2533: // ┳ HEAVY DOWN AND HORIZONTAL
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid)]

        // Bottom T-junctions
        case 0x2534: // ┴ LIGHT UP AND HORIZONTAL
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2535: // ┵ LEFT HEAVY AND RIGHT UP LIGHT
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2536: // ┶ RIGHT HEAVY AND LEFT UP LIGHT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2537: // ┷ UP LIGHT AND HORIZONTAL HEAVY
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2538: // ┸ UP HEAVY AND HORIZONTAL LIGHT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .heavy, dash: .solid)]
        case 0x2539: // ┹ RIGHT LIGHT AND LEFT UP HEAVY
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .heavy, dash: .solid)]
        case 0x253A: // ┺ LEFT LIGHT AND RIGHT UP HEAVY
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .up, weight: .heavy, dash: .solid)]
        case 0x253B: // ┻ HEAVY UP AND HORIZONTAL
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid),
                    Segment(direction: .up, weight: .heavy, dash: .solid)]

        // Cross junctions
        case 0x253C: // ┼ LIGHT VERTICAL AND HORIZONTAL
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x253D: // ┽ LEFT HEAVY AND RIGHT VERTICAL LIGHT
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x253E: // ┾ RIGHT HEAVY AND LEFT VERTICAL LIGHT
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x253F: // ┿ VERTICAL LIGHT AND HORIZONTAL HEAVY
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x2540: // ╀ UP HEAVY AND DOWN HORIZONTAL LIGHT
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x2541: // ╁ DOWN HEAVY AND UP HORIZONTAL LIGHT
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x2542: // ╂ VERTICAL HEAVY AND HORIZONTAL LIGHT
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x2543: // ╃ LEFT UP HEAVY AND RIGHT DOWN LIGHT
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x2544: // ╄ RIGHT UP HEAVY AND LEFT DOWN LIGHT
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x2545: // ╅ LEFT DOWN HEAVY AND RIGHT UP LIGHT
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x2546: // ╆ RIGHT DOWN HEAVY AND LEFT UP LIGHT
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x2547: // ╇ DOWN LIGHT AND UP HORIZONTAL HEAVY
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x2548: // ╈ UP LIGHT AND DOWN HORIZONTAL HEAVY
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x2549: // ╉ RIGHT LIGHT AND LEFT VERTICAL HEAVY
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x254A: // ╊ LEFT LIGHT AND RIGHT VERTICAL HEAVY
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x254B: // ╋ HEAVY VERTICAL AND HORIZONTAL
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid),
                    Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]

        // Light/heavy dashed (2-dash variants)
        case 0x254C: // ╌ LIGHT DOUBLE DASH HORIZONTAL
            return [Segment(direction: .left, weight: .light, dash: .double),
                    Segment(direction: .right, weight: .light, dash: .double)]
        case 0x254D: // ╍ HEAVY DOUBLE DASH HORIZONTAL
            return [Segment(direction: .left, weight: .heavy, dash: .double),
                    Segment(direction: .right, weight: .heavy, dash: .double)]
        case 0x254E: // ╎ LIGHT DOUBLE DASH VERTICAL
            return [Segment(direction: .up, weight: .light, dash: .double),
                    Segment(direction: .down, weight: .light, dash: .double)]
        case 0x254F: // ╏ HEAVY DOUBLE DASH VERTICAL
            return [Segment(direction: .up, weight: .heavy, dash: .double),
                    Segment(direction: .down, weight: .heavy, dash: .double)]

        // Double lines
        case 0x2550: // ═ DOUBLE HORIZONTAL
            return [Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .right, weight: .double, dash: .solid)]
        case 0x2551: // ║ DOUBLE VERTICAL
            return [Segment(direction: .up, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid)]

        // Double corners
        case 0x2552: // ╒ DOWN SINGLE AND RIGHT DOUBLE
            return [Segment(direction: .right, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x2553: // ╓ DOWN DOUBLE AND RIGHT SINGLE
            return [Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid)]
        case 0x2554: // ╔ DOUBLE DOWN AND RIGHT
            return [Segment(direction: .right, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid)]

        case 0x2555: // ╕ DOWN SINGLE AND LEFT DOUBLE
            return [Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x2556: // ╖ DOWN DOUBLE AND LEFT SINGLE
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid)]
        case 0x2557: // ╗ DOUBLE DOWN AND LEFT
            return [Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid)]

        case 0x2558: // ╘ UP SINGLE AND RIGHT DOUBLE
            return [Segment(direction: .right, weight: .double, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2559: // ╙ UP DOUBLE AND RIGHT SINGLE
            return [Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .double, dash: .solid)]
        case 0x255A: // ╚ DOUBLE UP AND RIGHT
            return [Segment(direction: .right, weight: .double, dash: .solid),
                    Segment(direction: .up, weight: .double, dash: .solid)]

        case 0x255B: // ╛ UP SINGLE AND LEFT DOUBLE
            return [Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x255C: // ╜ UP DOUBLE AND LEFT SINGLE
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .double, dash: .solid)]
        case 0x255D: // ╝ DOUBLE UP AND LEFT
            return [Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .up, weight: .double, dash: .solid)]

        // Double T-junctions
        case 0x255E: // ╞ VERTICAL SINGLE AND RIGHT DOUBLE
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .double, dash: .solid)]
        case 0x255F: // ╟ VERTICAL DOUBLE AND RIGHT SINGLE
            return [Segment(direction: .up, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x2560: // ╠ DOUBLE VERTICAL AND RIGHT
            return [Segment(direction: .up, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid),
                    Segment(direction: .right, weight: .double, dash: .solid)]

        case 0x2561: // ╡ VERTICAL SINGLE AND LEFT DOUBLE
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .double, dash: .solid)]
        case 0x2562: // ╢ VERTICAL DOUBLE AND LEFT SINGLE
            return [Segment(direction: .up, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid)]
        case 0x2563: // ╣ DOUBLE VERTICAL AND LEFT
            return [Segment(direction: .up, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid),
                    Segment(direction: .left, weight: .double, dash: .solid)]

        case 0x2564: // ╤ DOWN SINGLE AND HORIZONTAL DOUBLE
            return [Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .right, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x2565: // ╥ DOWN DOUBLE AND HORIZONTAL SINGLE
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid)]
        case 0x2566: // ╦ DOUBLE DOWN AND HORIZONTAL
            return [Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .right, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid)]

        case 0x2567: // ╧ UP SINGLE AND HORIZONTAL DOUBLE
            return [Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .right, weight: .double, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2568: // ╨ UP DOUBLE AND HORIZONTAL SINGLE
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .double, dash: .solid)]
        case 0x2569: // ╩ DOUBLE UP AND HORIZONTAL
            return [Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .right, weight: .double, dash: .solid),
                    Segment(direction: .up, weight: .double, dash: .solid)]

        // Double cross junctions
        case 0x256A: // ╪ VERTICAL SINGLE AND HORIZONTAL DOUBLE
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid),
                    Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .right, weight: .double, dash: .solid)]
        case 0x256B: // ╫ VERTICAL DOUBLE AND HORIZONTAL SINGLE
            return [Segment(direction: .up, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid),
                    Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x256C: // ╬ DOUBLE VERTICAL AND HORIZONTAL
            return [Segment(direction: .up, weight: .double, dash: .solid),
                    Segment(direction: .down, weight: .double, dash: .solid),
                    Segment(direction: .left, weight: .double, dash: .solid),
                    Segment(direction: .right, weight: .double, dash: .solid)]

        // Rounded corners (light arc)
        case 0x256D: // ╭ LIGHT ARC DOWN AND RIGHT
            return [Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x256E: // ╮ LIGHT ARC DOWN AND LEFT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x256F: // ╯ LIGHT ARC UP AND LEFT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2570: // ╰ LIGHT ARC UP AND RIGHT
            return [Segment(direction: .right, weight: .light, dash: .solid),
                    Segment(direction: .up, weight: .light, dash: .solid)]

        // Diagonals
        case 0x2571: // ╱ LIGHT DIAGONAL UPPER RIGHT TO LOWER LEFT
            return [] // Handled as special case below
        case 0x2572: // ╲ LIGHT DIAGONAL UPPER LEFT TO LOWER RIGHT
            return []
        case 0x2573: // ╳ LIGHT DIAGONAL CROSS
            return []

        // Light left/right/up/down (half lines)
        case 0x2574: // ╴ LIGHT LEFT
            return [Segment(direction: .left, weight: .light, dash: .solid)]
        case 0x2575: // ╵ LIGHT UP
            return [Segment(direction: .up, weight: .light, dash: .solid)]
        case 0x2576: // ╶ LIGHT RIGHT
            return [Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x2577: // ╷ LIGHT DOWN
            return [Segment(direction: .down, weight: .light, dash: .solid)]
        case 0x2578: // ╸ HEAVY LEFT
            return [Segment(direction: .left, weight: .heavy, dash: .solid)]
        case 0x2579: // ╹ HEAVY UP
            return [Segment(direction: .up, weight: .heavy, dash: .solid)]
        case 0x257A: // ╺ HEAVY RIGHT
            return [Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x257B: // ╻ HEAVY DOWN
            return [Segment(direction: .down, weight: .heavy, dash: .solid)]

        // Mixed light/heavy
        case 0x257C: // ╼ LIGHT LEFT AND HEAVY RIGHT
            return [Segment(direction: .left, weight: .light, dash: .solid),
                    Segment(direction: .right, weight: .heavy, dash: .solid)]
        case 0x257D: // ╽ LIGHT UP AND HEAVY DOWN
            return [Segment(direction: .up, weight: .light, dash: .solid),
                    Segment(direction: .down, weight: .heavy, dash: .solid)]
        case 0x257E: // ╾ HEAVY LEFT AND LIGHT RIGHT
            return [Segment(direction: .left, weight: .heavy, dash: .solid),
                    Segment(direction: .right, weight: .light, dash: .solid)]
        case 0x257F: // ╿ HEAVY UP AND LIGHT DOWN
            return [Segment(direction: .up, weight: .heavy, dash: .solid),
                    Segment(direction: .down, weight: .light, dash: .solid)]

        default:
            return []
        }
    }
}

#endif
