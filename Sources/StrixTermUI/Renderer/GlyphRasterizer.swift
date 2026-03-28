#if canImport(CoreText) && canImport(CoreGraphics) && canImport(MetalKit)
import CoreText
import CoreGraphics
import Foundation

/// Result of rasterizing a single glyph.
struct RasterizedGlyph: Sendable {
    /// Pixel data in row-major order.
    let data: [UInt8]
    /// Width of the rasterized bitmap in pixels.
    let width: Int
    /// Height of the rasterized bitmap in pixels.
    let height: Int
    /// Horizontal bearing: offset from the pen position to the left edge of the glyph.
    let bearingX: CGFloat
    /// Vertical bearing: offset from the baseline to the top of the glyph.
    let bearingY: CGFloat
    /// Whether this glyph contains color data (e.g. emoji).
    let isColored: Bool
}

/// CoreText-based glyph rasterizer.
///
/// Rasterizes CGGlyphs from a given CTFont into bitmap pixel data suitable
/// for uploading to a Metal texture atlas.
@MainActor
final class GlyphRasterizer {
    struct ResolvedGlyph {
        let font: CTFont
        let glyph: CGGlyph
    }

    private let font: CTFont
    private let fontSize: CGFloat
    private let lineSpacing: CGFloat
    private let letterSpacing: CGFloat
    /// Backing scale factor for Retina rendering.
    let scale: CGFloat

    /// Padding around each glyph to prevent texture bleeding.
    private let padding: Int = 1

    init(
        font: CTFont,
        scale: CGFloat = 1.0,
        lineSpacing: CGFloat = 1.0,
        letterSpacing: CGFloat = 0
    ) {
        self.font = font
        self.fontSize = CTFontGetSize(font)
        self.scale = scale
        self.lineSpacing = lineSpacing
        self.letterSpacing = letterSpacing
    }

    /// Create a rasterizer from a font name and size.
    /// The font is created at `size * scale` to produce Retina-quality bitmaps.
    convenience init(
        fontFamily: String,
        size: CGFloat,
        scale: CGFloat = 1.0,
        lineSpacing: CGFloat = 1.0,
        letterSpacing: CGFloat = 0
    ) {
        let scaledSize = size * scale
        let exactFont = CTFontCreateWithName(fontFamily as CFString, scaledSize, nil)
        let exactFontName = CTFontCopyPostScriptName(exactFont) as String

        let ctFont: CTFont
        if exactFontName.caseInsensitiveCompare(fontFamily) == .orderedSame ||
            exactFontName.lowercased().contains(fontFamily.lowercased()) {
            ctFont = exactFont
        } else {
            let descriptor = CTFontDescriptorCreateWithAttributes(
                [kCTFontNameAttribute: fontFamily as CFString] as CFDictionary
            )
            let resolved = CTFontCreateWithFontDescriptor(descriptor, scaledSize, nil)
            let resolvedName = CTFontCopyPostScriptName(resolved) as String

            if resolvedName.lowercased().contains(fontFamily.lowercased()) {
                ctFont = resolved
            } else {
                ctFont = CTFontCreateWithName("Menlo-Regular" as CFString, scaledSize, nil)
            }
        }
        self.init(
            font: ctFont,
            scale: scale,
            lineSpacing: lineSpacing,
            letterSpacing: letterSpacing
        )
    }

    /// The underlying CTFont.
    var ctFont: CTFont { font }

    /// Rasterize a single glyph. Returns nil if the glyph has no visual representation.
    func rasterize(
        glyph: CGGlyph,
        font overrideFont: CTFont? = nil,
        isColored: Bool = false
    ) -> RasterizedGlyph? {
        let renderFont = overrideFont ?? font
        var glyphs = [glyph]

        // Get glyph bounding rect
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(renderFont, .default, &glyphs, &boundingRect, 1)

        // Skip zero-size glyphs (spaces, etc.)
        if boundingRect.width <= 0 || boundingRect.height <= 0 {
            return nil
        }

        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(renderFont, .default, &glyphs, &advance, 1)

        let ascent = CTFontGetAscent(renderFont)
        let descent = CTFontGetDescent(renderFont)
        let contentHeight = ascent + descent
        let normalizedLineSpacing = max(lineSpacing, 0.9)

        let cellPixelWidth = Int(ceil(max(advance.width + (letterSpacing * scale), boundingRect.maxX) + CGFloat(padding * 2)))
        let cellPixelHeight = Int(ceil(max(contentHeight * normalizedLineSpacing, boundingRect.height) + CGFloat(padding * 2)))

        let verticalInset = max(0, (CGFloat(cellPixelHeight) - contentHeight) * 0.5)
        let baselineY = descent + verticalInset + CGFloat(padding)
        let drawX = max(CGFloat(padding), ((CGFloat(cellPixelWidth) - boundingRect.width) * 0.5) - boundingRect.origin.x)
        let drawY = baselineY

        let bearingX = 0 as CGFloat
        let bearingY = CGFloat(cellPixelHeight)

        if isColored {
            return rasterizeColored(
                glyph: glyph,
                width: cellPixelWidth,
                height: cellPixelHeight,
                bearingX: bearingX,
                bearingY: bearingY,
                drawX: drawX,
                drawY: drawY,
                font: renderFont
            )
        } else {
            return rasterizeGrayscale(
                glyph: glyph,
                width: cellPixelWidth,
                height: cellPixelHeight,
                bearingX: bearingX,
                bearingY: bearingY,
                drawX: drawX,
                drawY: drawY,
                font: renderFont
            )
        }
    }

    /// Rasterize a glyph as a single-channel grayscale coverage mask.
    private func rasterizeGrayscale(
        glyph: CGGlyph,
        width: Int,
        height: Int,
        bearingX: CGFloat,
        bearingY: CGFloat,
        drawX: CGFloat,
        drawY: CGFloat,
        font: CTFont
    ) -> RasterizedGlyph? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))

        var glyphs = [glyph]
        var position = CGPoint(x: drawX, y: drawY)
        CTFontDrawGlyphs(font, &glyphs, &position, 1, context)

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        let pixelData = Array(UnsafeBufferPointer(start: buffer, count: width * height))

        return RasterizedGlyph(
            data: pixelData,
            width: width,
            height: height,
            bearingX: bearingX,
            bearingY: bearingY,
            isColored: false
        )
    }

    /// Rasterize a colored glyph (emoji) as RGBA data.
    private func rasterizeColored(
        glyph: CGGlyph,
        width: Int,
        height: Int,
        bearingX: CGFloat,
        bearingY: CGFloat,
        drawX: CGFloat,
        drawY: CGFloat,
        font: CTFont
    ) -> RasterizedGlyph? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        var glyphs = [glyph]
        var position = CGPoint(x: drawX, y: drawY)
        CTFontDrawGlyphs(font, &glyphs, &position, 1, context)

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let pixelData = Array(UnsafeBufferPointer(start: buffer, count: width * height * 4))

        return RasterizedGlyph(
            data: pixelData,
            width: width,
            height: height,
            bearingX: bearingX,
            bearingY: bearingY,
            isColored: true
        )
    }

    /// Compute the cell dimensions from the font metrics.
    func cellMetrics() -> (width: CGFloat, height: CGFloat, descent: CGFloat, leading: CGFloat) {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)

        // Use the digit zero for a more representative terminal cell width.
        // `M` tends to produce roomier cells than modern terminal layouts want.
        var glyph: CGGlyph = 0
        var characters: [UniChar] = [0x0030] // '0'
        CTFontGetGlyphsForCharacters(font, &characters, &glyph, 1)

        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .default, &glyph, &advance, 1)

        let cellWidth = ceil(advance.width + (letterSpacing * scale))
        let baseHeight = ascent + descent + leading
        let normalizedLineSpacing = max(lineSpacing, 0.9)
        let cellHeight = ceil(baseHeight * normalizedLineSpacing)

        return (cellWidth, cellHeight, descent, leading)
    }

    /// Check if a unicode scalar has a color glyph in this font (e.g., emoji).
    func hasColorGlyph(for scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value > 0xFFFF {
            // Surrogate pair range - likely emoji
            return true
        }
        // Check for known emoji ranges
        if (0x2600...0x27BF).contains(value) ||
           (0xFE00...0xFE0F).contains(value) ||
           (0x1F000...0x1FFFF).contains(value) {
            return true
        }
        return false
    }

    /// Get the CGGlyph for a given unicode scalar.
    func glyphForScalar(_ scalar: Unicode.Scalar) -> CGGlyph {
        resolvedGlyph(for: scalar).glyph
    }

    /// Resolve a font/glyph pair for a unicode scalar using CoreText fallback.
    func resolvedGlyph(for scalar: Unicode.Scalar) -> ResolvedGlyph {
        let value = scalar.value
        let string = String(scalar)
        let resolvedFont = CTFontCreateForString(font, string as CFString, CFRangeMake(0, string.utf16.count))

        if value <= 0xFFFF {
            var characters: [UniChar] = [UniChar(value)]
            var glyph: CGGlyph = 0
            CTFontGetGlyphsForCharacters(resolvedFont, &characters, &glyph, 1)
            return ResolvedGlyph(font: resolvedFont, glyph: glyph)
        } else {
            // Handle supplementary plane characters via surrogate pair
            let hi = UniChar(0xD800 + ((value - 0x10000) >> 10))
            let lo = UniChar(0xDC00 + ((value - 0x10000) & 0x3FF))
            var characters: [UniChar] = [hi, lo]
            var glyphs: [CGGlyph] = [0, 0]
            CTFontGetGlyphsForCharacters(resolvedFont, &characters, &glyphs, 2)
            return ResolvedGlyph(font: resolvedFont, glyph: glyphs[0])
        }
    }

    /// Get the CGGlyph for a string (for grapheme clusters).
    func glyphForString(_ string: String) -> CGGlyph {
        let attrString = CFAttributedStringCreate(
            nil,
            string as CFString,
            [kCTFontAttributeName: font] as CFDictionary
        )!
        let line = CTLineCreateWithAttributedString(attrString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        guard let run = runs.first else { return 0 }
        var glyph: CGGlyph = 0
        CTRunGetGlyphs(run, CFRangeMake(0, 1), &glyph)
        return glyph
    }
}

#endif
