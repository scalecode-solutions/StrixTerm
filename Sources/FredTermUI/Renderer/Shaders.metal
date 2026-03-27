#include <metal_stdlib>
using namespace metal;

/// Per-cell data uploaded to the GPU.
struct CellData {
    uint2 position;          // (col, row)
    float4 fgColor;
    float4 bgColor;
    uint glyphIndex;         // Index into glyph atlas
    uint flags;              // Bold, italic, underline, blink, etc.
    float2 glyphSize;        // Size in the atlas
    float2 glyphOffset;      // Offset within the atlas texture
};

/// Uniforms for the current frame.
struct Uniforms {
    float2 cellSize;          // Pixel size of each cell
    float2 viewportSize;      // Total viewport size in pixels
    float2 gridOrigin;        // Top-left corner of the grid in pixels
    uint cols;
    uint rows;
    float blinkPhase;         // 0.0 or 1.0 for blink toggle
    float time;               // For smooth animations
};

/// Vertex output for the cell background pass.
struct BackgroundVertex {
    float4 position [[position]];
    float4 color;
};

/// Vertex output for the glyph rendering pass.
struct GlyphVertex {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

// MARK: - Background Pass

/// Renders cell backgrounds as colored quads.
vertex BackgroundVertex backgroundVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant CellData *cells [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    CellData cell = cells[instanceID];

    // Skip blink-hidden cells
    if ((cell.flags & 0x10) != 0 && uniforms.blinkPhase < 0.5) {
        BackgroundVertex out;
        out.position = float4(0, 0, 0, 0);
        out.color = float4(0);
        return out;
    }

    // Quad vertices (2 triangles = 6 vertices)
    float2 positions[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    float2 pos = positions[vertexID];
    float2 cellPos = float2(cell.position) * uniforms.cellSize + uniforms.gridOrigin;
    float2 worldPos = cellPos + pos * uniforms.cellSize;

    // Convert to NDC
    float2 ndc = worldPos / uniforms.viewportSize * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y

    BackgroundVertex out;
    out.position = float4(ndc, 0, 1);
    out.color = cell.bgColor;
    return out;
}

fragment float4 backgroundFragment(BackgroundVertex in [[stage_in]]) {
    return in.color;
}

// MARK: - Glyph Pass

/// Renders glyphs from the atlas texture.
vertex GlyphVertex glyphVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant CellData *cells [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    CellData cell = cells[instanceID];

    float2 positions[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    float2 texCoords[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    float2 pos = positions[vertexID];
    float2 cellPos = float2(cell.position) * uniforms.cellSize + uniforms.gridOrigin;
    float2 worldPos = cellPos + pos * cell.glyphSize;

    float2 ndc = worldPos / uniforms.viewportSize * 2.0 - 1.0;
    ndc.y = -ndc.y;

    // Map texture coordinates to the atlas region
    float2 texCoord = cell.glyphOffset + texCoords[vertexID] * cell.glyphSize;

    GlyphVertex out;
    out.position = float4(ndc, 0, 1);
    out.texCoord = texCoord;
    out.color = cell.fgColor;
    return out;
}

fragment float4 glyphFragment(
    GlyphVertex in [[stage_in]],
    texture2d<float> atlas [[texture(0)]]
) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);
    float alpha = atlas.sample(s, in.texCoord).r;
    return float4(in.color.rgb, in.color.a * alpha);
}

// MARK: - Decoration/Overlay Pass

/// Per-quad data for decorations (underlines, strikethrough, overline) and selection overlays.
/// Uses pixel coordinates rather than cell grid positions for sub-cell precision.
struct DecorationData {
    float2 pixelPosition;    // Top-left corner in pixels
    float2 pixelSize;        // Width and height in pixels
    float4 color;            // RGBA color
};

/// Vertex output for the decoration pass (reuses BackgroundVertex layout).
vertex BackgroundVertex decorationVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant DecorationData *decorations [[buffer(0)]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    DecorationData dec = decorations[instanceID];

    // Quad vertices (2 triangles = 6 vertices)
    float2 positions[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    float2 pos = positions[vertexID];
    float2 worldPos = dec.pixelPosition + pos * dec.pixelSize;

    // Convert to NDC
    float2 ndc = worldPos / uniforms.viewportSize * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y

    BackgroundVertex out;
    out.position = float4(ndc, 0, 1);
    out.color = dec.color;
    return out;
}

fragment float4 decorationFragment(BackgroundVertex in [[stage_in]]) {
    return in.color;
}

// MARK: - Kitty Image Pass

/// Vertex output for the image rendering pass.
struct ImageVertex {
    float4 position [[position]];
    float2 texCoord;
};

/// Renders a Kitty graphics image as a textured quad.
/// Buffer 0: float4 rect (x, y, width, height in pixels).
/// Buffer 1: float2 viewport size.
/// Buffer 2: float4 crop (u0, v0, u1, v1) normalized texture coords.
vertex ImageVertex imageVertex(
    uint vertexID [[vertex_id]],
    constant float4 &rect [[buffer(0)]],
    constant float2 &viewport [[buffer(1)]],
    constant float4 &crop [[buffer(2)]]
) {
    // 6 vertices for a quad (2 triangles).
    float2 corners[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };
    float2 corner = corners[vertexID];

    // Pixel position of this vertex.
    float2 pos = rect.xy + corner * rect.zw;
    // Convert to NDC.
    float2 ndc = pos / viewport * 2.0 - 1.0;
    ndc.y = -ndc.y;

    // Interpolate texture coordinates within the crop region.
    float2 uv = crop.xy + corner * (crop.zw - crop.xy);

    ImageVertex out;
    out.position = float4(ndc, 0, 1);
    out.texCoord = uv;
    return out;
}

fragment float4 imageFragment(
    ImageVertex in [[stage_in]],
    texture2d<float> tex [[texture(0)]]
) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);
    return tex.sample(s, in.texCoord);
}

// MARK: - Cursor Pass

struct CursorUniforms {
    float2 position;     // Cell position
    float2 cellSize;
    float2 viewportSize;
    float4 color;
    uint style;          // 0=block, 1=underline, 2=bar
    float blinkPhase;
};

vertex float4 cursorVertex(
    uint vertexID [[vertex_id]],
    constant CursorUniforms &cursor [[buffer(0)]]
) {
    float2 positions[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    float2 pos = positions[vertexID];
    float2 cellPos = cursor.position * cursor.cellSize;
    float2 size = cursor.cellSize;

    // Adjust size based on cursor style
    if (cursor.style == 1) { // Underline
        cellPos.y += size.y * 0.85;
        size.y *= 0.15;
    } else if (cursor.style == 2) { // Bar
        size.x *= 0.1;
    }

    float2 worldPos = cellPos + pos * size;
    float2 ndc = worldPos / cursor.viewportSize * 2.0 - 1.0;
    ndc.y = -ndc.y;

    return float4(ndc, 0, 1);
}

fragment float4 cursorFragment(
    float4 position [[position]],
    constant CursorUniforms &cursor [[buffer(0)]]
) {
    if (cursor.blinkPhase < 0.5) {
        discard_fragment();
    }
    return cursor.color;
}
