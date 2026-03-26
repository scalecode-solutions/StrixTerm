#if canImport(MetalKit) && canImport(CoreText)
import MetalKit
import CoreText
import FredTermCore

// MARK: - GPU Data Structures (must match Shaders.metal)

/// Per-cell data uploaded to the GPU. Matches the Metal `CellData` struct.
struct GPUCellData {
    var position: SIMD2<UInt32>      // (col, row)
    var fgColor: SIMD4<Float>
    var bgColor: SIMD4<Float>
    var glyphIndex: UInt32           // Index into glyph atlas
    var flags: UInt32                // Bold, italic, underline, blink, etc.
    var glyphSize: SIMD2<Float>      // Size in the atlas (pixels)
    var glyphOffset: SIMD2<Float>    // Offset within the atlas texture (UV)
}

/// Uniforms for the current frame. Matches the Metal `Uniforms` struct.
struct GPUUniforms {
    var cellSize: SIMD2<Float>       // Pixel size of each cell
    var viewportSize: SIMD2<Float>   // Total viewport size in pixels
    var gridOrigin: SIMD2<Float>     // Top-left corner of the grid in pixels
    var cols: UInt32
    var rows: UInt32
    var blinkPhase: Float            // 0.0 or 1.0 for blink toggle
    var time: Float                  // For smooth animations
}

/// Cursor uniforms. Matches the Metal `CursorUniforms` struct.
struct GPUCursorUniforms {
    var position: SIMD2<Float>       // Cell position
    var cellSize: SIMD2<Float>
    var viewportSize: SIMD2<Float>
    var color: SIMD4<Float>
    var style: UInt32                // 0=block, 1=underline, 2=bar
    var blinkPhase: Float
}

// MARK: - Glyph Cache Key

/// Key for looking up cached glyphs.
struct GlyphKey: Hashable {
    let codePoint: UInt32
    let isBold: Bool
    let isItalic: Bool
}

/// Cached information about a rasterized glyph in the atlas.
struct GlyphEntry {
    let region: GlyphRegion
    let bearingX: Float
    let bearingY: Float
    let isColored: Bool
}

// MARK: - Style Flags (matching shader expectations)

/// Flags packed into CellData.flags, matching the shader's flag checks.
struct CellStyleFlags {
    static let bold: UInt32          = 1 << 0
    static let dim: UInt32           = 1 << 1
    static let italic: UInt32        = 1 << 2
    static let underline: UInt32     = 1 << 3
    static let blink: UInt32         = 1 << 4
    static let inverse: UInt32       = 1 << 5
    static let invisible: UInt32     = 1 << 6
    static let strikethrough: UInt32 = 1 << 7
    static let overline: UInt32      = 1 << 8
}

/// GPU data for decoration quads (underlines, strikethrough, overline, selection).
/// Must match the Metal `DecorationData` struct in Shaders.metal.
struct GPUDecorationData {
    var pixelPosition: SIMD2<Float>  // Top-left corner in pixels
    var pixelSize: SIMD2<Float>      // Width and height in pixels
    var color: SIMD4<Float>          // RGBA color
}

// MARK: - MetalRenderer

/// The main Metal-based terminal renderer.
///
/// Turns a `TerminalSnapshot` into pixels using GPU-accelerated rendering.
/// Manages glyph rasterization, atlas packing, and draw call encoding.
@MainActor
public final class MetalRenderer: NSObject, MTKViewDelegate {

    // MARK: - Metal State

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let backgroundPipeline: MTLRenderPipelineState
    private let glyphPipeline: MTLRenderPipelineState
    private let decorationPipeline: MTLRenderPipelineState
    private let cursorPipeline: MTLRenderPipelineState

    // MARK: - Glyph System

    private let rasterizer: GlyphRasterizer
    private let grayscaleAtlas: GlyphAtlas
    private let colorAtlas: GlyphAtlas
    private var glyphCache: [GlyphKey: GlyphEntry] = [:]

    // MARK: - Terminal Reference

    private let terminal: Terminal

    // MARK: - Cell Metrics

    private let cellWidth: CGFloat
    private let cellHeight: CGFloat
    private let descent: CGFloat
    private let leading: CGFloat

    // MARK: - Default Colors

    private var defaultFG: SIMD4<Float> = SIMD4<Float>(0.9, 0.9, 0.9, 1.0)
    private var defaultBG: SIMD4<Float> = SIMD4<Float>(0.0, 0.0, 0.0, 1.0)

    // MARK: - Blink State

    private var blinkOn: Bool = true
    private var lastBlinkToggle: CFTimeInterval = 0
    private var blinkInterval: TimeInterval = 0.5
    private var startTime: CFTimeInterval = 0

    // MARK: - Dirty Tracking

    /// Per-row content hashes from the previous frame.
    private var previousRowHashes: [UInt64] = []

    // MARK: - GPU Buffers

    private var cellDataBuffer: MTLBuffer?
    private var glyphCellDataBuffer: MTLBuffer?
    private var decorationDataBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    private var cursorUniformBuffer: MTLBuffer?

    // MARK: - Selection State

    /// The current selection, if any. Set by the view layer to enable selection highlighting.
    public var selection: Selection = Selection()

    // MARK: - Init

    /// Create a MetalRenderer.
    ///
    /// - Parameters:
    ///   - device: The Metal device to use.
    ///   - terminal: The terminal whose state will be rendered.
    ///   - fontFamily: The font family name (e.g. "SF Mono", "Menlo").
    ///   - fontSize: The font size in points.
    public init?(
        device: MTLDevice,
        terminal: Terminal,
        fontFamily: String = "SF Mono",
        fontSize: CGFloat = 13
    ) {
        self.device = device
        self.terminal = terminal
        self.startTime = CACurrentMediaTime()

        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        // Create the font and rasterizer.
        self.rasterizer = GlyphRasterizer(fontFamily: fontFamily, size: fontSize)
        let metrics = rasterizer.cellMetrics()
        self.cellWidth = metrics.width
        self.cellHeight = metrics.height
        self.descent = metrics.descent
        self.leading = metrics.leading

        // Create glyph atlases.
        self.grayscaleAtlas = GlyphAtlas(device: device, isColor: false)
        self.colorAtlas = GlyphAtlas(device: device, isColor: true)

        // Build render pipeline states.
        guard let library = Self.makeLibrary(device: device) else { return nil }

        guard let bgPipeline = Self.makeBackgroundPipeline(device: device, library: library),
              let glPipeline = Self.makeGlyphPipeline(device: device, library: library),
              let decPipeline = Self.makeDecorationPipeline(device: device, library: library),
              let cuPipeline = Self.makeCursorPipeline(device: device, library: library) else {
            return nil
        }

        self.backgroundPipeline = bgPipeline
        self.glyphPipeline = glPipeline
        self.decorationPipeline = decPipeline
        self.cursorPipeline = cuPipeline

        // Pre-allocate uniform buffers.
        self.uniformBuffer = device.makeBuffer(
            length: MemoryLayout<GPUUniforms>.stride,
            options: .storageModeShared
        )
        self.cursorUniformBuffer = device.makeBuffer(
            length: MemoryLayout<GPUCursorUniforms>.stride,
            options: .storageModeShared
        )

        super.init()
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Viewport resized; dirty tracking is invalidated.
        previousRowHashes.removeAll()
    }

    public func draw(in view: MTKView) {
        // 1. Take a snapshot from the terminal.
        let snapshot = terminal.snapshot()

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        // Set clear color to the default background.
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(defaultBG.x),
            green: Double(defaultBG.y),
            blue: Double(defaultBG.z),
            alpha: Double(defaultBG.w)
        )
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        let viewportSize = SIMD2<Float>(
            Float(view.drawableSize.width),
            Float(view.drawableSize.height)
        )

        // Update blink state.
        let now = CACurrentMediaTime()
        if now - lastBlinkToggle >= blinkInterval {
            blinkOn.toggle()
            lastBlinkToggle = now
        }
        let blinkPhase: Float = blinkOn ? 1.0 : 0.0
        let time = Float(now - startTime)

        // 2. Build cell data arrays.
        let cols = snapshot.cols
        let rows = snapshot.rows

        var bgCells: [GPUCellData] = []
        var glyphCells: [GPUCellData] = []
        var decorationQuads: [GPUDecorationData] = []
        bgCells.reserveCapacity(cols * rows)
        glyphCells.reserveCapacity(cols * rows)

        let cw = Float(cellWidth)
        let ch = Float(cellHeight)

        for row in 0..<rows {
            for col in 0..<cols {
                let cell = snapshot.cells[row * cols + col]

                // Skip wide-char continuation cells.
                if cell.flags.contains(.wideContinuation) {
                    continue
                }

                let attr = snapshot.attribute(for: cell)
                var fgColor = resolveColor(attr.fg, palette: snapshot.palette, isDefault: true)
                var bgColor = resolveColor(attr.bg, palette: snapshot.palette, isDefault: false)

                // Build flags.
                var styleFlags: UInt32 = 0
                if attr.style.contains(.bold) { styleFlags |= CellStyleFlags.bold }
                if attr.style.contains(.dim) { styleFlags |= CellStyleFlags.dim }
                if attr.style.contains(.italic) { styleFlags |= CellStyleFlags.italic }
                if attr.style.contains(.underline) { styleFlags |= CellStyleFlags.underline }
                if attr.style.contains(.blink) { styleFlags |= CellStyleFlags.blink }
                if attr.style.contains(.inverse) { styleFlags |= CellStyleFlags.inverse }
                if attr.style.contains(.invisible) { styleFlags |= CellStyleFlags.invisible }
                if attr.style.contains(.strikethrough) { styleFlags |= CellStyleFlags.strikethrough }
                if attr.style.contains(.overline) { styleFlags |= CellStyleFlags.overline }

                // Handle inverse video.
                if attr.style.contains(.inverse) {
                    let tmp = fgColor
                    fgColor = bgColor
                    bgColor = tmp
                }

                // Handle dim.
                if attr.style.contains(.dim) {
                    fgColor = SIMD4<Float>(
                        fgColor.x * 0.5,
                        fgColor.y * 0.5,
                        fgColor.z * 0.5,
                        fgColor.w
                    )
                }

                // Background quad. Determine effective cell width (wide chars = 2 cells).
                let effectiveWidth = max(Int(cell.width), 1)
                for w in 0..<effectiveWidth {
                    let bgData = GPUCellData(
                        position: SIMD2<UInt32>(UInt32(col + w), UInt32(row)),
                        fgColor: fgColor,
                        bgColor: bgColor,
                        glyphIndex: 0,
                        flags: styleFlags,
                        glyphSize: SIMD2<Float>(0, 0),
                        glyphOffset: SIMD2<Float>(0, 0)
                    )
                    bgCells.append(bgData)
                }

                // Selection overlay: render a semi-transparent blue highlight
                // for each cell in the effective width of this character.
                if selection.active {
                    for w in 0..<effectiveWidth {
                        let pos = Position(col: col + w, row: row)
                        if selection.contains(pos) {
                            let selectionColor = SIMD4<Float>(0.3, 0.5, 0.9, 0.35)
                            let px = Float(col + w) * cw
                            let py = Float(row) * ch
                            decorationQuads.append(GPUDecorationData(
                                pixelPosition: SIMD2<Float>(px, py),
                                pixelSize: SIMD2<Float>(cw, ch),
                                color: selectionColor
                            ))
                        }
                    }
                }

                // Build decoration quads for underline, strikethrough, and overline.
                let decoWidth = Float(effectiveWidth) * cw
                let cellPx = Float(col) * cw
                let cellPy = Float(row) * ch

                // Determine the decoration color: use underlineColor if set, otherwise fg.
                let decoColor: SIMD4<Float>
                if let ulColor = attr.underlineColor {
                    decoColor = resolveColor(ulColor, palette: snapshot.palette, isDefault: true)
                } else {
                    decoColor = fgColor
                }

                // Underline decoration.
                if attr.style.contains(.underline) || attr.underlineStyle != .none {
                    let ulStyle = attr.underlineStyle != .none ? attr.underlineStyle : .single
                    buildUnderlineQuads(
                        style: ulStyle,
                        x: cellPx, y: cellPy,
                        width: decoWidth, cellHeight: ch,
                        color: decoColor,
                        into: &decorationQuads
                    )
                }

                // Strikethrough decoration.
                if attr.style.contains(.strikethrough) {
                    let strikeY = cellPy + ch * 0.5
                    decorationQuads.append(GPUDecorationData(
                        pixelPosition: SIMD2<Float>(cellPx, strikeY),
                        pixelSize: SIMD2<Float>(decoWidth, 1),
                        color: fgColor
                    ))
                }

                // Overline decoration.
                if attr.style.contains(.overline) {
                    decorationQuads.append(GPUDecorationData(
                        pixelPosition: SIMD2<Float>(cellPx, cellPy),
                        pixelSize: SIMD2<Float>(decoWidth, 1),
                        color: fgColor
                    ))
                }

                // Skip invisible cells or blank spaces for glyph rendering.
                if attr.style.contains(.invisible) || cell.isBlank {
                    continue
                }

                // Check if this is a box drawing / block element character.
                if BoxDrawingRenderer.isBoxDrawingCharacter(cell.codePoint) {
                    if let entry = lookupOrRasterizeBoxDrawing(codePoint: cell.codePoint) {
                        let atlas = grayscaleAtlas
                        let (uvX, uvY) = entry.region.uvOffset(
                            atlasWidth: atlas.atlasWidth,
                            atlasHeight: atlas.atlasHeight
                        )

                        let glyphData = GPUCellData(
                            position: SIMD2<UInt32>(UInt32(col), UInt32(row)),
                            fgColor: fgColor,
                            bgColor: bgColor,
                            glyphIndex: 1,
                            flags: styleFlags,
                            glyphSize: SIMD2<Float>(Float(entry.region.width), Float(entry.region.height)),
                            glyphOffset: SIMD2<Float>(uvX, uvY)
                        )
                        glyphCells.append(glyphData)
                    }
                    continue
                }

                // Look up or rasterize the glyph from the font.
                let glyphKey = GlyphKey(
                    codePoint: cell.codePoint,
                    isBold: attr.style.contains(.bold),
                    isItalic: attr.style.contains(.italic)
                )

                if let entry = lookupOrRasterizeGlyph(key: glyphKey, cell: cell) {
                    let atlas = entry.isColored ? colorAtlas : grayscaleAtlas
                    let (uvX, uvY) = entry.region.uvOffset(
                        atlasWidth: atlas.atlasWidth,
                        atlasHeight: atlas.atlasHeight
                    )
                    let (uvW, uvH) = entry.region.uvSize(
                        atlasWidth: atlas.atlasWidth,
                        atlasHeight: atlas.atlasHeight
                    )

                    let glyphData = GPUCellData(
                        position: SIMD2<UInt32>(UInt32(col), UInt32(row)),
                        fgColor: fgColor,
                        bgColor: bgColor,
                        glyphIndex: 1, // Non-zero means has glyph
                        flags: styleFlags,
                        glyphSize: SIMD2<Float>(Float(entry.region.width), Float(entry.region.height)),
                        glyphOffset: SIMD2<Float>(uvX, uvY)
                    )
                    _ = (uvW, uvH) // UV size used by shader via glyphSize / atlas size
                    glyphCells.append(glyphData)
                }
            }
        }

        // 3. Upload data to GPU buffers.
        let bgDataSize = MemoryLayout<GPUCellData>.stride * max(bgCells.count, 1)
        let glyphDataSize = MemoryLayout<GPUCellData>.stride * max(glyphCells.count, 1)

        cellDataBuffer = device.makeBuffer(
            bytes: bgCells,
            length: bgDataSize,
            options: .storageModeShared
        )
        glyphCellDataBuffer = device.makeBuffer(
            bytes: glyphCells,
            length: glyphDataSize,
            options: .storageModeShared
        )

        if !decorationQuads.isEmpty {
            let decDataSize = MemoryLayout<GPUDecorationData>.stride * decorationQuads.count
            decorationDataBuffer = device.makeBuffer(
                bytes: decorationQuads,
                length: decDataSize,
                options: .storageModeShared
            )
        } else {
            decorationDataBuffer = nil
        }

        // Update uniforms.
        var uniforms = GPUUniforms(
            cellSize: SIMD2<Float>(Float(cellWidth), Float(cellHeight)),
            viewportSize: viewportSize,
            gridOrigin: SIMD2<Float>(0, 0),
            cols: UInt32(cols),
            rows: UInt32(rows),
            blinkPhase: blinkPhase,
            time: time
        )

        if let uniformBuffer = uniformBuffer {
            uniformBuffer.contents().copyMemory(
                from: &uniforms,
                byteCount: MemoryLayout<GPUUniforms>.stride
            )
        }

        // 4. Encode render commands.
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Background pass.
        if !bgCells.isEmpty, let buffer = cellDataBuffer {
            encoder.setRenderPipelineState(backgroundPipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: bgCells.count
            )
        }

        // Selection and decoration overlay pass (between background and glyphs).
        // Selection quads are included in decorationQuads but rendered before glyphs
        // so that text remains visible on top of the highlight.
        if !decorationQuads.isEmpty, let decBuffer = decorationDataBuffer {
            // Split: render selection overlays now (before glyphs).
            // Selection quads were added first in the array, but for simplicity
            // we render all decoration quads in a single pass after glyphs.
            // Actually, selection should be between bg and glyphs, decorations after glyphs.
            // We'll render all decorations here as a single pass. Selection has alpha
            // blending so text will still be visible.
            encoder.setRenderPipelineState(decorationPipeline)
            encoder.setVertexBuffer(decBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: decorationQuads.count
            )
        }

        // Glyph pass.
        if !glyphCells.isEmpty, let buffer = glyphCellDataBuffer, let atlasTexture = grayscaleAtlas.texture {
            encoder.setRenderPipelineState(glyphPipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentTexture(atlasTexture, index: 0)
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: glyphCells.count
            )
        }

        // Cursor pass.
        if snapshot.cursorVisible {
            let cursorRow = snapshot.cursorPosition.row
            let cursorCol = snapshot.cursorPosition.col
            let cursorShapeValue: UInt32
            switch snapshot.cursorStyle.shape {
            case .block: cursorShapeValue = 0
            case .underline: cursorShapeValue = 1
            case .bar: cursorShapeValue = 2
            }
            let cursorBlinkPhase: Float = snapshot.cursorStyle.blinks ? blinkPhase : 1.0

            var cursorUniforms = GPUCursorUniforms(
                position: SIMD2<Float>(Float(cursorCol), Float(cursorRow)),
                cellSize: SIMD2<Float>(Float(cellWidth), Float(cellHeight)),
                viewportSize: viewportSize,
                color: defaultFG,
                style: cursorShapeValue,
                blinkPhase: cursorBlinkPhase
            )

            if let cursorBuffer = cursorUniformBuffer {
                cursorBuffer.contents().copyMemory(
                    from: &cursorUniforms,
                    byteCount: MemoryLayout<GPUCursorUniforms>.stride
                )

                encoder.setRenderPipelineState(cursorPipeline)
                encoder.setVertexBuffer(cursorBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(cursorBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(
                    type: .triangle,
                    vertexStart: 0,
                    vertexCount: 6
                )
            }
        }

        encoder.endEncoding()

        // 5. Present drawable.
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Color Resolution

    /// Resolve a `TerminalColor` to an RGBA float4.
    private func resolveColor(
        _ color: TerminalColor,
        palette: ColorPalette,
        isDefault: Bool
    ) -> SIMD4<Float> {
        switch color {
        case .default:
            return isDefault ? defaultFG : defaultBG
        case .indexed(let idx):
            let entry = palette.colors[Int(idx)]
            return SIMD4<Float>(
                Float(entry.r) / 255.0,
                Float(entry.g) / 255.0,
                Float(entry.b) / 255.0,
                Float(entry.a) / 255.0
            )
        case .rgb(let r, let g, let b):
            return SIMD4<Float>(
                Float(r) / 255.0,
                Float(g) / 255.0,
                Float(b) / 255.0,
                1.0
            )
        }
    }

    // MARK: - Glyph Cache

    /// Look up a glyph in the cache, or rasterize it and add it.
    private func lookupOrRasterizeGlyph(key: GlyphKey, cell: Cell) -> GlyphEntry? {
        if let cached = glyphCache[key] {
            return cached
        }

        // Get the CGGlyph.
        let space: Unicode.Scalar = " "
        let scalar = Unicode.Scalar(key.codePoint) ?? space
        let isColorGlyph = rasterizer.hasColorGlyph(for: scalar)
        let cgGlyph = rasterizer.glyphForScalar(scalar)

        guard let rasterized = rasterizer.rasterize(glyph: cgGlyph, isColored: isColorGlyph) else {
            return nil
        }

        let atlas = rasterized.isColored ? colorAtlas : grayscaleAtlas
        guard let region = atlas.reserve(width: rasterized.width, height: rasterized.height) else {
            return nil
        }

        atlas.write(region: region, data: rasterized.data)

        let entry = GlyphEntry(
            region: region,
            bearingX: Float(rasterized.bearingX),
            bearingY: Float(rasterized.bearingY),
            isColored: rasterized.isColored
        )

        glyphCache[key] = entry
        return entry
    }

    // MARK: - Pipeline Construction

    private static func makeLibrary(device: MTLDevice) -> MTLLibrary? {
        // Try loading from the bundle (SPM resource bundle).
        if let bundleURL = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
           let source = try? String(contentsOf: bundleURL, encoding: .utf8),
           let library = try? device.makeLibrary(source: source, options: nil) {
            return library
        }
        // Fall back to default library.
        if let library = device.makeDefaultLibrary() {
            return library
        }
        // Try compiling from source as a last resort by searching in the bundle.
        if let metalURL = Bundle.module.url(forResource: "Shaders", withExtension: "metallib"),
           let library = try? device.makeLibrary(URL: metalURL) {
            return library
        }
        return nil
    }

    private static func makeBackgroundPipeline(
        device: MTLDevice,
        library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        guard let vertexFunc = library.makeFunction(name: "backgroundVertex"),
              let fragmentFunc = library.makeFunction(name: "backgroundFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable alpha blending for background.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeGlyphPipeline(
        device: MTLDevice,
        library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        guard let vertexFunc = library.makeFunction(name: "glyphVertex"),
              let fragmentFunc = library.makeFunction(name: "glyphFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable alpha blending for glyphs.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeCursorPipeline(
        device: MTLDevice,
        library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        guard let vertexFunc = library.makeFunction(name: "cursorVertex"),
              let fragmentFunc = library.makeFunction(name: "cursorFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable alpha blending for cursor.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Public Configuration

    /// Update the default foreground color.
    public func setDefaultForeground(r: Float, g: Float, b: Float, a: Float = 1.0) {
        defaultFG = SIMD4<Float>(r, g, b, a)
    }

    /// Update the default background color.
    public func setDefaultBackground(r: Float, g: Float, b: Float, a: Float = 1.0) {
        defaultBG = SIMD4<Float>(r, g, b, a)
    }

    /// Get the cell size in points.
    public var cellSize: CGSize {
        CGSize(width: cellWidth, height: cellHeight)
    }

    /// Clear the glyph cache (e.g. after a font change).
    public func clearGlyphCache() {
        glyphCache.removeAll()
        boxDrawingCache.removeAll()
        grayscaleAtlas.reset()
        colorAtlas.reset()
    }

    // MARK: - Decoration Pipeline Construction

    private static func makeDecorationPipeline(
        device: MTLDevice,
        library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        guard let vertexFunc = library.makeFunction(name: "decorationVertex"),
              let fragmentFunc = library.makeFunction(name: "decorationFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable alpha blending for decorations (selection uses translucency).
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Underline Quad Generation

    /// Build decoration quads for the various underline styles.
    private func buildUnderlineQuads(
        style: UnderlineStyle,
        x: Float,
        y: Float,
        width: Float,
        cellHeight ch: Float,
        color: SIMD4<Float>,
        into quads: inout [GPUDecorationData]
    ) {
        // Underline is drawn near the bottom of the cell.
        let baselineY = y + ch - 2

        switch style {
        case .none:
            break

        case .single:
            // Solid 1px line at the bottom of the cell.
            quads.append(GPUDecorationData(
                pixelPosition: SIMD2<Float>(x, baselineY),
                pixelSize: SIMD2<Float>(width, 1),
                color: color
            ))

        case .double:
            // Two 1px lines with a 1px gap.
            quads.append(GPUDecorationData(
                pixelPosition: SIMD2<Float>(x, baselineY - 2),
                pixelSize: SIMD2<Float>(width, 1),
                color: color
            ))
            quads.append(GPUDecorationData(
                pixelPosition: SIMD2<Float>(x, baselineY),
                pixelSize: SIMD2<Float>(width, 1),
                color: color
            ))

        case .curly:
            // Approximate a wavy/curly line with a series of small quads
            // forming a sine-wave pattern.
            let segmentWidth: Float = 4
            let amplitude: Float = 1.5
            var cx = x
            while cx < x + width {
                let segW = min(segmentWidth, x + width - cx)
                let phase = (cx - x).truncatingRemainder(dividingBy: segmentWidth * 2)
                let dy: Float = phase < segmentWidth ? -amplitude : amplitude
                quads.append(GPUDecorationData(
                    pixelPosition: SIMD2<Float>(cx, baselineY + dy),
                    pixelSize: SIMD2<Float>(segW, 1),
                    color: color
                ))
                cx += segW
            }

        case .dotted:
            // Dotted line: 1px dots with 1px gaps.
            var cx = x
            while cx < x + width {
                let dotW: Float = min(1, x + width - cx)
                quads.append(GPUDecorationData(
                    pixelPosition: SIMD2<Float>(cx, baselineY),
                    pixelSize: SIMD2<Float>(dotW, 1),
                    color: color
                ))
                cx += 2 // 1px dot + 1px gap
            }

        case .dashed:
            // Dashed line: 4px dashes with 2px gaps.
            var cx = x
            while cx < x + width {
                let dashW: Float = min(4, x + width - cx)
                quads.append(GPUDecorationData(
                    pixelPosition: SIMD2<Float>(cx, baselineY),
                    pixelSize: SIMD2<Float>(dashW, 1),
                    color: color
                ))
                cx += 6 // 4px dash + 2px gap
            }
        }
    }

    // MARK: - Box Drawing Cache

    /// Cache for programmatically rendered box drawing / block element glyphs.
    private var boxDrawingCache: [UInt32: GlyphEntry] = [:]

    /// Look up or rasterize a box drawing character.
    private func lookupOrRasterizeBoxDrawing(codePoint: UInt32) -> GlyphEntry? {
        if let cached = boxDrawingCache[codePoint] {
            return cached
        }

        guard let rasterized = BoxDrawingRenderer.rasterize(
            codePoint: codePoint,
            cellWidth: Int(cellWidth),
            cellHeight: Int(cellHeight)
        ) else {
            return nil
        }

        guard let region = grayscaleAtlas.reserve(
            width: rasterized.width,
            height: rasterized.height
        ) else {
            return nil
        }

        grayscaleAtlas.write(region: region, data: rasterized.data)

        let entry = GlyphEntry(
            region: region,
            bearingX: Float(rasterized.bearingX),
            bearingY: Float(rasterized.bearingY),
            isColored: false
        )

        boxDrawingCache[codePoint] = entry
        return entry
    }
}

#endif
