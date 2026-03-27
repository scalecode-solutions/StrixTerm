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
    private let font: CTFont
    private let fontSize: CGFloat
    /// Backing scale factor for Retina rendering.
    let scale: CGFloat

    /// Padding around each glyph to prevent texture bleeding.
    private let padding: Int = 1

    init(font: CTFont, scale: CGFloat = 1.0) {
        self.font = font
        self.fontSize = CTFontGetSize(font)
        self.scale = scale
    }

    /// Create a rasterizer from a font name and size.
    /// The font is created at `size * scale` to produce Retina-quality bitmaps.
    convenience init(fontFamily: String, size: CGFloat, scale: CGFloat = 1.0) {
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontFamilyNameAttribute: fontFamily as CFString] as CFDictionary
        )
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size * scale, nil)
        self.init(font: ctFont, scale: scale)
    }

    /// The underlying CTFont.
    var ctFont: CTFont { font }

    /// Rasterize a single glyph. Returns nil if the glyph has no visual representation.
    func rasterize(glyph: CGGlyph, isColored: Bool = false) -> RasterizedGlyph? {
        var glyphs = [glyph]

        // Get glyph bounding rect
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyphs, &boundingRect, 1)

        // Skip zero-size glyphs (spaces, etc.)
        let glyphWidth = Int(ceil(boundingRect.width)) + padding * 2
        let glyphHeight = Int(ceil(boundingRect.height)) + padding * 2
        if glyphWidth <= padding * 2 || glyphHeight <= padding * 2 {
            return nil
        }

        let bearingX = boundingRect.origin.x - CGFloat(padding)
        let bearingY = boundingRect.origin.y + boundingRect.height + CGFloat(padding)

        if isColored {
            return rasterizeColored(
                glyph: glyph,
                width: glyphWidth,
                height: glyphHeight,
                bearingX: bearingX,
                bearingY: bearingY,
                boundingRect: boundingRect
            )
        } else {
            return rasterizeGrayscale(
                glyph: glyph,
                width: glyphWidth,
                height: glyphHeight,
                bearingX: bearingX,
                bearingY: bearingY,
                boundingRect: boundingRect
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
        boundingRect: CGRect
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

        // Position the glyph so its bounding box lands inside our bitmap.
        let drawX = -boundingRect.origin.x + CGFloat(padding)
        let drawY = -boundingRect.origin.y + CGFloat(padding)

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
        boundingRect: CGRect
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

        let drawX = -boundingRect.origin.x + CGFloat(padding)
        let drawY = -boundingRect.origin.y + CGFloat(padding)

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

        // Use the font's advancement of '0' or 'M' for cell width
        var glyph: CGGlyph = 0
        var characters: [UniChar] = [0x004D] // 'M'
        CTFontGetGlyphsForCharacters(font, &characters, &glyph, 1)

        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .default, &glyph, &advance, 1)

        let cellWidth = ceil(advance.width)
        let cellHeight = ceil(ascent + descent + leading)

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
        let value = scalar.value
        if value <= 0xFFFF {
            var characters: [UniChar] = [UniChar(value)]
            var glyph: CGGlyph = 0
            CTFontGetGlyphsForCharacters(font, &characters, &glyph, 1)
            return glyph
        } else {
            // Handle supplementary plane characters via surrogate pair
            let hi = UniChar(0xD800 + ((value - 0x10000) >> 10))
            let lo = UniChar(0xDC00 + ((value - 0x10000) & 0x3FF))
            var characters: [UniChar] = [hi, lo]
            var glyphs: [CGGlyph] = [0, 0]
            CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 2)
            return glyphs[0]
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
