#if canImport(MetalKit)
import Metal
import Foundation

/// A rectangular region within the glyph atlas texture.
struct GlyphRegion: Sendable {
    /// Pixel coordinates within the atlas texture.
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    /// UV coordinates normalized to [0, 1] range for a given atlas size.
    func uvOffset(atlasWidth: Int, atlasHeight: Int) -> (Float, Float) {
        let u = Float(x) / Float(atlasWidth)
        let v = Float(y) / Float(atlasHeight)
        return (u, v)
    }

    func uvSize(atlasWidth: Int, atlasHeight: Int) -> (Float, Float) {
        let u = Float(width) / Float(atlasWidth)
        let v = Float(height) / Float(atlasHeight)
        return (u, v)
    }
}

/// GPU texture atlas for caching rasterized glyphs.
///
/// Uses linear packing: fills left-to-right across the current row,
/// then wraps to the next row when the current row is full. The atlas
/// texture grows dynamically from 512 to 4096 pixels as needed.
@MainActor
final class GlyphAtlas {
    private let device: MTLDevice
    private(set) var texture: MTLTexture?

    /// Current atlas dimensions in pixels.
    private(set) var atlasWidth: Int
    private(set) var atlasHeight: Int

    /// Maximum atlas size.
    private let maxSize: Int = 4096

    /// Current packing cursor.
    private var cursorX: Int = 0
    private var cursorY: Int = 0
    /// Height of the tallest glyph in the current row.
    private var rowHeight: Int = 0

    /// Whether this atlas stores color (RGBA) or grayscale (R8) data.
    let isColor: Bool

    /// The pixel format for this atlas.
    var pixelFormat: MTLPixelFormat {
        isColor ? .rgba8Unorm : .r8Unorm
    }

    init(device: MTLDevice, isColor: Bool, initialSize: Int = 512) {
        self.device = device
        self.isColor = isColor
        self.atlasWidth = initialSize
        self.atlasHeight = initialSize
        self.texture = Self.createTexture(
            device: device,
            width: initialSize,
            height: initialSize,
            pixelFormat: isColor ? .rgba8Unorm : .r8Unorm
        )
    }

    /// Reserve a region in the atlas for a glyph of the given size.
    /// Returns nil if the atlas is full and cannot grow further.
    func reserve(width: Int, height: Int) -> GlyphRegion? {
        guard width > 0 && height > 0 else { return nil }

        // Check if the glyph fits in the current row.
        if cursorX + width > atlasWidth {
            // Move to the next row.
            cursorX = 0
            cursorY += rowHeight
            rowHeight = 0
        }

        // Check if we need to grow vertically.
        if cursorY + height > atlasHeight {
            if !grow() {
                return nil
            }
        }

        let region = GlyphRegion(
            x: cursorX,
            y: cursorY,
            width: width,
            height: height
        )

        cursorX += width
        rowHeight = max(rowHeight, height)

        return region
    }

    /// Write pixel data into a previously reserved region.
    func write(region: GlyphRegion, data: [UInt8]) {
        guard let texture = texture else { return }

        let bytesPerPixel = isColor ? 4 : 1
        let bytesPerRow = region.width * bytesPerPixel

        let mtlRegion = MTLRegion(
            origin: MTLOrigin(x: region.x, y: region.y, z: 0),
            size: MTLSize(width: region.width, height: region.height, depth: 1)
        )

        data.withUnsafeBufferPointer { buffer in
            texture.replace(
                region: mtlRegion,
                mipmapLevel: 0,
                withBytes: buffer.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }
    }

    /// Reset the atlas, clearing all packed data. The texture is recreated.
    func reset() {
        cursorX = 0
        cursorY = 0
        rowHeight = 0
        atlasWidth = 512
        atlasHeight = 512
        texture = Self.createTexture(
            device: device,
            width: atlasWidth,
            height: atlasHeight,
            pixelFormat: pixelFormat
        )
    }

    // MARK: - Private

    /// Grow the atlas texture, doubling the size (up to maxSize).
    /// Copies existing content to the new texture.
    private func grow() -> Bool {
        let newWidth: Int
        let newHeight: Int

        if atlasWidth < maxSize {
            newWidth = min(atlasWidth * 2, maxSize)
            newHeight = min(atlasHeight * 2, maxSize)
        } else {
            // Already at max size, can't grow.
            return false
        }

        guard let oldTexture = texture else { return false }

        guard let newTexture = Self.createTexture(
            device: device,
            width: newWidth,
            height: newHeight,
            pixelFormat: pixelFormat
        ) else {
            return false
        }

        // Copy old texture content to the new texture using a blit encoder.
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return false
        }

        let copyWidth = min(atlasWidth, newWidth)
        let copyHeight = min(atlasHeight, newHeight)

        blitEncoder.copy(
            from: oldTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: copyWidth, height: copyHeight, depth: 1),
            to: newTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )

        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        texture = newTexture
        atlasWidth = newWidth
        atlasHeight = newHeight

        return true
    }

    private static func createTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        return device.makeTexture(descriptor: descriptor)
    }
}

#endif
