import Foundation
#if canImport(Compression)
import Compression
#endif

// MARK: - State types

/// Kitty graphics protocol state, stored per terminal instance.
public struct KittyGraphicsState: Sendable {
    /// Stored images by ID.
    public var imagesById: [UInt32: KittyImage] = [:]
    /// Image number to ID mapping.
    public var imageNumbers: [UInt32: UInt32] = [:]
    /// Placement records (virtual and non-virtual).
    public var placements: [KittyPlacementKey: KittyPlacement] = [:]
    /// Total bytes used by all stored images.
    public var totalImageBytes: Int = 0
    /// Next auto-assigned image ID.
    public var nextImageId: UInt32 = 1
    /// Next auto-assigned placement ID.
    public var nextPlacementId: UInt32 = 1
    /// Pending chunked transmission.
    public var pendingTransmission: PendingTransmission? = nil
    /// Cache limit in bytes (default 320 MB).
    public var cacheLimitBytes: Int = 320 * 1024 * 1024
    /// Access tick counter for LRU eviction.
    public var accessTick: UInt64 = 0

    public init() {}

    /// Clear all state (used on full terminal reset).
    public mutating func reset() {
        imagesById.removeAll()
        imageNumbers.removeAll()
        placements.removeAll()
        totalImageBytes = 0
        nextImageId = 1
        nextPlacementId = 1
        pendingTransmission = nil
        accessTick = 0
    }
}

/// A stored image (decoded pixel data).
public struct KittyImage: Sendable {
    public var id: UInt32
    public var number: UInt32?
    /// RGBA pixel data.
    public var data: Data
    public var width: Int
    public var height: Int
    public var lastAccessTick: UInt64

    public var byteSize: Int { data.count }
}

/// Key for placement lookup.
public struct KittyPlacementKey: Hashable, Sendable {
    public var imageId: UInt32
    public var placementId: UInt32
}

/// A placement record.
public struct KittyPlacement: Sendable {
    public var imageId: UInt32
    public var placementId: UInt32
    public var col: Int
    public var row: Int
    public var cols: Int           // cell width (0 = auto)
    public var rows: Int           // cell height (0 = auto)
    public var cropX: Int
    public var cropY: Int
    public var cropWidth: Int
    public var cropHeight: Int
    public var pixelOffsetX: Int
    public var pixelOffsetY: Int
    public var zIndex: Int32
    public var isVirtual: Bool     // Unicode placeholder mode
    public var cursorPolicy: Int   // 0 = move, 1 = stay
}

/// Accumulator for multi-chunk transmissions.
public struct PendingTransmission: Sendable {
    public var params: KittyParams
    public var accumulatedBase64: [UInt8]
}

// MARK: - Parsed parameters

/// Parsed key=value pairs from a Kitty graphics control string.
public struct KittyParams: Sendable {
    public var action: Character = "t"
    public var format: Int = 32
    public var transmissionMode: Character = "d"
    public var imageId: UInt32 = 0
    public var imageNumber: UInt32 = 0
    public var placementId: UInt32 = 0
    public var sourceWidth: Int = 0
    public var sourceHeight: Int = 0
    public var cols: Int = 0
    public var rows: Int = 0
    public var cropX: Int = 0
    public var cropY: Int = 0
    public var cropWidth: Int = 0
    public var cropHeight: Int = 0
    public var more: Bool = false
    public var quiet: Int = 0
    public var unicode: Bool = false
    public var compression: Character? = nil
    public var dataSize: Int = 0
    public var dataOffset: Int = 0
    public var cursorPolicy: Int = 0
    public var pixelOffsetX: Int = 0
    public var pixelOffsetY: Int = 0
    public var zIndex: Int32 = 0
    public var deleteMode: Character = "a"

    /// Parse the control portion (everything before the ';') of a Kitty graphics APC.
    public static func parse(_ controlBytes: ArraySlice<UInt8>) -> KittyParams {
        var params = KittyParams()
        var values: [(key: String, value: String)] = []

        // Split on ','
        var start = controlBytes.startIndex
        while start < controlBytes.endIndex {
            let end = controlBytes[start...].firstIndex(of: UInt8(ascii: ",")) ?? controlBytes.endIndex
            let chunk = controlBytes[start..<end]
            if let eq = chunk.firstIndex(of: UInt8(ascii: "=")) {
                let keyBytes = chunk[chunk.startIndex..<eq]
                let valueBytes = chunk[(eq + 1)..<chunk.endIndex]
                if let key = String(bytes: keyBytes, encoding: .ascii),
                   let value = String(bytes: valueBytes, encoding: .ascii) {
                    values.append((key, value))
                }
            }
            start = end == controlBytes.endIndex ? end : controlBytes.index(after: end)
        }

        for (key, value) in values {
            switch key {
            case "a":
                if let ch = value.first { params.action = ch }
            case "f":
                if let v = Int(value) { params.format = v }
            case "t":
                if let ch = value.first { params.transmissionMode = ch }
            case "i":
                if let v = UInt32(value) { params.imageId = v }
            case "I":
                if let v = UInt32(value) { params.imageNumber = v }
            case "p":
                if let v = UInt32(value) { params.placementId = v }
            case "s":
                if let v = Int(value) { params.sourceWidth = v }
            case "v":
                if let v = Int(value) { params.sourceHeight = v }
            case "c":
                if let v = Int(value) { params.cols = v }
            case "r":
                if let v = Int(value) { params.rows = v }
            case "x":
                if let v = Int(value) { params.cropX = v }
            case "y":
                if let v = Int(value) { params.cropY = v }
            case "w":
                if let v = Int(value) { params.cropWidth = v }
            case "h":
                if let v = Int(value) { params.cropHeight = v }
            case "m":
                if let v = Int(value) { params.more = (v == 1) }
            case "q":
                if let v = Int(value) { params.quiet = v }
            case "U":
                if let v = Int(value) { params.unicode = (v == 1) }
            case "o":
                if let ch = value.first { params.compression = ch }
            case "S":
                if let v = Int(value) { params.dataSize = v }
            case "O":
                if let v = Int(value) { params.dataOffset = v }
            case "C":
                if let v = Int(value) { params.cursorPolicy = v }
            case "X":
                if let v = Int(value) { params.pixelOffsetX = v }
            case "Y":
                if let v = Int(value) { params.pixelOffsetY = v }
            case "z":
                if let v = Int32(value) { params.zIndex = v }
            case "d":
                if let ch = value.first { params.deleteMode = ch }
            default:
                break
            }
        }

        // Non-direct transmissions don't support chunking
        if params.transmissionMode != "d" {
            params.more = false
        }

        return params
    }
}

// MARK: - Constants

private let kittyMaxImageBytes = 400 * 1024 * 1024
private let kittyMaxImageDimension = 10_000

// MARK: - TerminalState extension for Kitty graphics

extension TerminalState {
    /// Handle a complete Kitty graphics APC sequence.
    /// `control` is everything before the first ';', `payload` is everything after.
    public mutating func handleKittyGraphics(control: ArraySlice<UInt8>, payload: ArraySlice<UInt8>) {
        let params = KittyParams.parse(control)

        // Delete actions clear any pending transmission
        if params.action == "d" || params.action == "D" {
            kittyGraphics.pendingTransmission = nil
        }

        // Chunked transmission: accumulate
        if params.more {
            if kittyGraphics.pendingTransmission == nil {
                kittyGraphics.pendingTransmission = PendingTransmission(
                    params: params,
                    accumulatedBase64: Array(payload)
                )
            } else {
                kittyGraphics.pendingTransmission?.accumulatedBase64.append(contentsOf: payload)
            }
            return
        }

        // Final chunk of a multi-chunk sequence, or single chunk
        if var pending = kittyGraphics.pendingTransmission {
            pending.accumulatedBase64.append(contentsOf: payload)
            kittyGraphics.pendingTransmission = nil
            processKittyGraphics(params: pending.params, base64Payload: pending.accumulatedBase64)
            return
        }

        processKittyGraphics(params: params, base64Payload: Array(payload))
    }

    // MARK: - Dispatch

    private mutating func processKittyGraphics(params: KittyParams, base64Payload: [UInt8]) {
        switch params.action {
        case "q":
            kittyQuery(params, base64Payload: base64Payload)
        case "t":
            kittyTransmit(params, base64Payload: base64Payload, display: false)
        case "T":
            kittyTransmit(params, base64Payload: base64Payload, display: true)
        case "p":
            kittyPut(params)
        case "d", "D":
            kittyDelete(params)
        default:
            kittySendError(params: params, message: "EINVAL: unsupported action")
        }
    }

    // MARK: - Query (a=q)

    private mutating func kittyQuery(_ params: KittyParams, base64Payload: [UInt8]) {
        // The query action validates that the payload decodes successfully.
        guard kittyDecodePayload(base64Payload, params: params) != nil else {
            kittySendError(params: params, message: "EINVAL: bad payload")
            return
        }
        kittySendOk(params: params, imageId: params.imageId, imageNumber: params.imageNumber, placementId: params.placementId)
    }

    // MARK: - Transmit (a=t / a=T)

    private mutating func kittyTransmit(_ params: KittyParams, base64Payload: [UInt8], display: Bool) {
        guard params.imageId == 0 || params.imageNumber == 0 else {
            kittySendError(params: params, message: "EINVAL: i and I are mutually exclusive")
            return
        }

        guard let decoded = kittyDecodePayload(base64Payload, params: params) else {
            kittySendError(params: params, message: "EINVAL: bad payload")
            return
        }

        let resolved = resolveImageId(params)
        let imageId = resolved.imageId
        let imageNumber = resolved.imageNumber

        // Store the image
        if imageId != 0 {
            storeImage(id: imageId, number: imageNumber, data: decoded.data, width: decoded.width, height: decoded.height)
        }

        if display {
            kittyDisplay(params, imageId: imageId, imageNumber: imageNumber, data: decoded.data, width: decoded.width, height: decoded.height)
        }

        if resolved.shouldReply {
            kittySendOk(params: params, imageId: imageId, imageNumber: imageNumber, placementId: params.placementId)
        }
    }

    // MARK: - Put / Display (a=p)

    private mutating func kittyPut(_ params: KittyParams) {
        // Look up the image
        let id: UInt32
        if params.imageNumber != 0 {
            guard let mapped = kittyGraphics.imageNumbers[params.imageNumber] else {
                kittySendError(params: params, message: "ENOENT: image not found")
                return
            }
            id = mapped
        } else if params.imageId != 0 {
            id = params.imageId
        } else {
            kittySendError(params: params, message: "ENOENT: image not found")
            return
        }

        guard let image = kittyGraphics.imagesById[id] else {
            kittySendError(params: params, message: "ENOENT: image not found")
            return
        }

        // Update access tick
        kittyGraphics.accessTick &+= 1
        kittyGraphics.imagesById[id]?.lastAccessTick = kittyGraphics.accessTick

        kittyDisplay(params, imageId: id, imageNumber: params.imageNumber, data: image.data, width: image.width, height: image.height)

        if params.quiet == 0 {
            kittySendOk(params: params, imageId: id, imageNumber: params.imageNumber, placementId: params.placementId)
        }
    }

    // MARK: - Display helper

    private mutating func kittyDisplay(_ params: KittyParams, imageId: UInt32, imageNumber: UInt32, data: Data, width: Int, height: Int) {
        let placementId = params.placementId != 0 ? params.placementId : nextPlacementId()
        let col = buffer.cursorX
        let row = buffer.cursorY

        let placement = KittyPlacement(
            imageId: imageId,
            placementId: placementId,
            col: col,
            row: row,
            cols: params.cols,
            rows: params.rows,
            cropX: params.cropX,
            cropY: params.cropY,
            cropWidth: params.cropWidth,
            cropHeight: params.cropHeight,
            pixelOffsetX: params.pixelOffsetX,
            pixelOffsetY: params.pixelOffsetY,
            zIndex: params.zIndex,
            isVirtual: params.unicode,
            cursorPolicy: params.cursorPolicy
        )

        let key = KittyPlacementKey(imageId: imageId, placementId: placementId)
        kittyGraphics.placements[key] = placement

        pendingActions.append(.imagePlaced(placement: placement))
    }

    // MARK: - Delete (a=d / a=D)

    private mutating func kittyDelete(_ params: KittyParams) {
        let mode = params.deleteMode
        let isUppercase = mode.isUppercase

        switch mode.lowercased().first ?? "a" {
        case "a":
            // Delete all visible placements
            deletePlacementsOnScreen()
        case "i":
            // Delete placements by image ID
            guard params.imageId != 0 else {
                kittySendError(params: params, message: "EINVAL: missing image id")
                return
            }
            deletePlacementsByImageId(params.imageId, placementId: params.placementId != 0 ? params.placementId : nil)
        case "n":
            // Delete placements by image number
            guard params.imageNumber != 0 else {
                kittySendError(params: params, message: "EINVAL: missing image number")
                return
            }
            if let imageId = kittyGraphics.imageNumbers[params.imageNumber] {
                deletePlacementsByImageId(imageId, placementId: params.placementId != 0 ? params.placementId : nil)
            }
        case "c":
            // Delete placements at cursor
            let col = buffer.cursorX + 1
            let row = buffer.cursorY + 1
            deletePlacementsAtCell(col: col, row: row, zIndex: nil)
        case "p":
            // Delete placements at specified cell
            guard params.cropX > 0, params.cropY > 0 else {
                kittySendError(params: params, message: "EINVAL: missing cell position")
                return
            }
            deletePlacementsAtCell(col: params.cropX, row: params.cropY, zIndex: nil)
        case "q":
            // Delete placements at specified cell with z-index filter
            guard params.cropX > 0, params.cropY > 0 else {
                kittySendError(params: params, message: "EINVAL: missing cell position")
                return
            }
            deletePlacementsAtCell(col: params.cropX, row: params.cropY, zIndex: params.zIndex)
        case "x":
            // Delete placements in column
            guard params.cropX > 0 else {
                kittySendError(params: params, message: "EINVAL: missing column")
                return
            }
            deletePlacementsInColumn(params.cropX)
        case "y":
            // Delete placements in row
            guard params.cropY > 0 else {
                kittySendError(params: params, message: "EINVAL: missing row")
                return
            }
            deletePlacementsInRow(params.cropY)
        case "z":
            // Delete placements by z-index
            deletePlacementsWithZIndex(params.zIndex)
        case "r":
            // Delete placements by image ID range
            guard params.cropX > 0, params.cropY > 0 else {
                kittySendError(params: params, message: "EINVAL: missing id range")
                return
            }
            let minId = UInt32(min(params.cropX, params.cropY))
            let maxId = UInt32(max(params.cropX, params.cropY))
            deletePlacementsByImageIdRange(minId: minId, maxId: maxId)
        default:
            kittySendError(params: params, message: "EINVAL: unsupported delete")
        }

        // Uppercase variant also frees image data for unreferenced images
        if isUppercase {
            cleanupUnusedImages()
        }
    }

    // MARK: - Deletion helpers

    private mutating func deletePlacementsOnScreen() {
        let keysToRemove = kittyGraphics.placements.keys.filter { _ in true }
        for key in keysToRemove {
            kittyGraphics.placements.removeValue(forKey: key)
        }
        pendingActions.append(.imageDeleted(imageId: nil))
    }

    private mutating func deletePlacementsByImageId(_ imageId: UInt32, placementId: UInt32?) {
        let keysToRemove = kittyGraphics.placements.keys.filter { key in
            guard key.imageId == imageId else { return false }
            if let pid = placementId {
                return key.placementId == pid
            }
            return true
        }
        for key in keysToRemove {
            kittyGraphics.placements.removeValue(forKey: key)
        }
        pendingActions.append(.imageDeleted(imageId: imageId))
    }

    private mutating func deletePlacementsByImageIdRange(minId: UInt32, maxId: UInt32) {
        let keysToRemove = kittyGraphics.placements.keys.filter { key in
            key.imageId >= minId && key.imageId <= maxId
        }
        for key in keysToRemove {
            kittyGraphics.placements.removeValue(forKey: key)
        }
    }

    private mutating func deletePlacementsAtCell(col: Int, row: Int, zIndex: Int32?) {
        let colIdx = col - 1
        let rowIdx = row - 1
        let keysToRemove = kittyGraphics.placements.filter { (_, placement) in
            if let z = zIndex, placement.zIndex != z { return false }
            return placementIntersectsCell(placement, col: colIdx, row: rowIdx)
        }.map { $0.key }
        for key in keysToRemove {
            kittyGraphics.placements.removeValue(forKey: key)
        }
    }

    private mutating func deletePlacementsInColumn(_ col: Int) {
        let colIdx = col - 1
        let keysToRemove = kittyGraphics.placements.filter { (_, placement) in
            placementIntersectsColumn(placement, col: colIdx)
        }.map { $0.key }
        for key in keysToRemove {
            kittyGraphics.placements.removeValue(forKey: key)
        }
    }

    private mutating func deletePlacementsInRow(_ row: Int) {
        let rowIdx = row - 1
        let keysToRemove = kittyGraphics.placements.filter { (_, placement) in
            placementIntersectsRow(placement, row: rowIdx)
        }.map { $0.key }
        for key in keysToRemove {
            kittyGraphics.placements.removeValue(forKey: key)
        }
    }

    private mutating func deletePlacementsWithZIndex(_ zIndex: Int32) {
        let keysToRemove = kittyGraphics.placements.filter { (_, placement) in
            placement.zIndex == zIndex
        }.map { $0.key }
        for key in keysToRemove {
            kittyGraphics.placements.removeValue(forKey: key)
        }
    }

    // MARK: - Intersection tests

    private func placementIntersectsCell(_ placement: KittyPlacement, col: Int, row: Int) -> Bool {
        let left = placement.col
        let top = placement.row
        let width = max(1, placement.cols)
        let height = max(1, placement.rows)
        let right = left + width - 1
        let bottom = top + height - 1
        return col >= left && col <= right && row >= top && row <= bottom
    }

    private func placementIntersectsColumn(_ placement: KittyPlacement, col: Int) -> Bool {
        let left = placement.col
        let width = max(1, placement.cols)
        let right = left + width - 1
        return col >= left && col <= right
    }

    private func placementIntersectsRow(_ placement: KittyPlacement, row: Int) -> Bool {
        let top = placement.row
        let height = max(1, placement.rows)
        let bottom = top + height - 1
        return row >= top && row <= bottom
    }

    // MARK: - Image cleanup

    private mutating func cleanupUnusedImages() {
        let usedIds = Set(kittyGraphics.placements.values.map { $0.imageId })
        let unusedIds = kittyGraphics.imagesById.keys.filter { !usedIds.contains($0) }
        for id in unusedIds {
            removeImage(id)
        }
    }

    private mutating func removeImage(_ imageId: UInt32) {
        if let removed = kittyGraphics.imagesById.removeValue(forKey: imageId) {
            kittyGraphics.totalImageBytes = max(0, kittyGraphics.totalImageBytes - removed.byteSize)
        }
        // Remove image number mappings for this ID
        let numbers = kittyGraphics.imageNumbers.filter { $0.value == imageId }.map { $0.key }
        for number in numbers {
            kittyGraphics.imageNumbers.removeValue(forKey: number)
        }
    }

    // MARK: - Image storage

    private mutating func storeImage(id: UInt32, number: UInt32, data: Data, width: Int, height: Int) {
        // Remove old image if replacing
        if let existing = kittyGraphics.imagesById[id] {
            kittyGraphics.totalImageBytes = max(0, kittyGraphics.totalImageBytes - existing.byteSize)
        }

        kittyGraphics.accessTick &+= 1
        let image = KittyImage(
            id: id,
            number: number != 0 ? number : nil,
            data: data,
            width: width,
            height: height,
            lastAccessTick: kittyGraphics.accessTick
        )
        kittyGraphics.imagesById[id] = image
        kittyGraphics.totalImageBytes += image.byteSize

        if number != 0 {
            kittyGraphics.imageNumbers[number] = id
        }

        evictIfNeeded()
    }

    // MARK: - ID resolution

    private mutating func resolveImageId(_ params: KittyParams) -> (imageId: UInt32, imageNumber: UInt32, shouldReply: Bool) {
        if params.imageNumber != 0 {
            let newId = kittyGraphics.nextImageId
            kittyGraphics.nextImageId &+= 1
            return (newId, params.imageNumber, params.quiet == 0)
        }
        if params.imageId != 0 {
            return (params.imageId, 0, params.quiet == 0)
        }
        // No ID specified: auto-assign, no response
        return (0, 0, false)
    }

    private mutating func nextPlacementId() -> UInt32 {
        var id = kittyGraphics.nextPlacementId
        kittyGraphics.nextPlacementId &+= 1
        if id == 0 {
            id = kittyGraphics.nextPlacementId
            kittyGraphics.nextPlacementId &+= 1
        }
        return id == 0 ? 1 : id
    }

    // MARK: - Eviction

    private mutating func evictIfNeeded() {
        guard kittyGraphics.totalImageBytes > kittyGraphics.cacheLimitBytes else { return }

        let usedIds = Set(kittyGraphics.placements.values.map { $0.imageId })

        // First evict unused images, oldest first
        let unusedSorted = kittyGraphics.imagesById
            .filter { !usedIds.contains($0.key) }
            .sorted { $0.value.lastAccessTick < $1.value.lastAccessTick }
            .map { $0.key }
        for id in unusedSorted {
            removeImage(id)
            if kittyGraphics.totalImageBytes <= kittyGraphics.cacheLimitBytes { return }
        }

        // Then evict used images if still over limit
        let allSorted = kittyGraphics.imagesById
            .sorted { $0.value.lastAccessTick < $1.value.lastAccessTick }
            .map { $0.key }
        for id in allSorted {
            removeImage(id)
            if kittyGraphics.totalImageBytes <= kittyGraphics.cacheLimitBytes { return }
        }
    }

    // MARK: - Payload decoding

    /// Decode base64 payload into RGBA pixel data.
    private func kittyDecodePayload(_ base64Payload: [UInt8], params: KittyParams) -> (data: Data, width: Int, height: Int)? {
        if base64Payload.isEmpty { return nil }

        guard let decoded = Data(base64Encoded: Data(base64Payload), options: .ignoreUnknownCharacters),
              decoded.count <= kittyMaxImageBytes else {
            return nil
        }

        // Decompress if needed
        let rawData: Data
        if let compression = params.compression {
            guard compression == "z" else { return nil }
            guard let inflated = decompressZlib(decoded), inflated.count <= kittyMaxImageBytes else {
                return nil
            }
            rawData = inflated
        } else {
            rawData = decoded
        }

        switch params.format {
        case 100:
            // PNG format: for the core protocol we accept and store as-is.
            // We need to decode to get dimensions.
            return decodePngPayload(rawData)
        case 24:
            // Raw RGB (3 bytes per pixel)
            let w = params.sourceWidth
            let h = params.sourceHeight
            guard w > 0, h > 0, w <= kittyMaxImageDimension, h <= kittyMaxImageDimension else { return nil }
            let expected = w * h * 3
            guard rawData.count == expected else { return nil }
            // Convert RGB to RGBA
            var rgba = Data(capacity: w * h * 4)
            var idx = rawData.startIndex
            while idx < rawData.endIndex {
                rgba.append(rawData[idx])
                rgba.append(rawData[rawData.index(after: idx)])
                rgba.append(rawData[rawData.index(idx, offsetBy: 2)])
                rgba.append(255)
                idx = rawData.index(idx, offsetBy: 3)
            }
            return (rgba, w, h)
        case 32:
            // Raw RGBA (4 bytes per pixel)
            let w = params.sourceWidth
            let h = params.sourceHeight
            guard w > 0, h > 0, w <= kittyMaxImageDimension, h <= kittyMaxImageDimension else { return nil }
            let expected = w * h * 4
            guard rawData.count == expected else { return nil }
            return (rawData, w, h)
        default:
            return nil
        }
    }

    /// Decode a PNG payload to RGBA data with dimensions.
    /// Parses IHDR chunk to extract dimensions, stores raw PNG data.
    /// Actual pixel decoding is deferred to the rendering layer.
    private func decodePngPayload(_ data: Data) -> (data: Data, width: Int, height: Int)? {
        // Parse PNG IHDR to get dimensions.
        // PNG signature: 8 bytes, then first chunk is IHDR (4 len + 4 type + 4 width + 4 height ...)
        // Minimum: 8 (sig) + 4 (len) + 4 (type) + 8 (w+h) = 24 bytes
        guard data.count >= 24 else { return nil }
        // Check PNG signature
        let sig: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        for i in 0..<8 {
            guard data[data.startIndex + i] == sig[i] else { return nil }
        }
        // IHDR width and height are at offset 16 and 20 (big-endian UInt32)
        let widthOffset = data.startIndex + 16
        let heightOffset = data.startIndex + 20
        let width = Int(UInt32(data[widthOffset]) << 24 |
                        UInt32(data[widthOffset + 1]) << 16 |
                        UInt32(data[widthOffset + 2]) << 8 |
                        UInt32(data[widthOffset + 3]))
        let height = Int(UInt32(data[heightOffset]) << 24 |
                         UInt32(data[heightOffset + 1]) << 16 |
                         UInt32(data[heightOffset + 2]) << 8 |
                         UInt32(data[heightOffset + 3]))
        guard width > 0, height > 0, width <= kittyMaxImageDimension, height <= kittyMaxImageDimension else {
            return nil
        }
        // Store the raw PNG data; the rendering layer will decode it.
        return (data, width, height)
    }

    // MARK: - Zlib decompression

    private func decompressZlib(_ data: Data) -> Data? {
        #if canImport(Compression)
        let dummyDst = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        let dummySrc = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        var stream = compression_stream(
            dst_ptr: dummyDst,
            dst_size: 0,
            src_ptr: UnsafePointer(dummySrc),
            src_size: 0,
            state: nil
        )
        let initStatus = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus != COMPRESSION_STATUS_ERROR else {
            dummyDst.deallocate()
            dummySrc.deallocate()
            return nil
        }
        defer {
            compression_stream_destroy(&stream)
            dummyDst.deallocate()
            dummySrc.deallocate()
        }

        var output = Data()
        let dstSize = 64 * 1024
        var dstBuffer = [UInt8](repeating: 0, count: dstSize)

        return data.withUnsafeBytes { srcPtr -> Data? in
            guard let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            stream.src_ptr = srcBase
            stream.src_size = data.count

            while true {
                let status = dstBuffer.withUnsafeMutableBytes { dstPtr -> compression_status in
                    guard let dstBase = dstPtr.bindMemory(to: UInt8.self).baseAddress else {
                        return COMPRESSION_STATUS_ERROR
                    }
                    stream.dst_ptr = dstBase
                    stream.dst_size = dstSize
                    return compression_stream_process(&stream, 0)
                }
                let produced = dstSize - stream.dst_size
                if produced > 0 {
                    output.append(dstBuffer, count: produced)
                }
                switch status {
                case COMPRESSION_STATUS_END:
                    return output
                case COMPRESSION_STATUS_OK:
                    continue
                default:
                    return nil
                }
            }
        }
        #else
        return nil
        #endif
    }

    // MARK: - Response helpers

    private mutating func kittySendOk(params: KittyParams, imageId: UInt32, imageNumber: UInt32, placementId: UInt32) {
        guard params.quiet == 0 else { return }
        var parts: [String] = []
        if imageId != 0 { parts.append("i=\(imageId)") }
        if imageNumber != 0 { parts.append("I=\(imageNumber)") }
        if placementId != 0 { parts.append("p=\(placementId)") }
        var controlData = "G"
        if !parts.isEmpty {
            controlData += parts.joined(separator: ",")
        }
        let response = "\u{1b}_\(controlData);OK\u{1b}\\"
        pendingActions.append(.sendData(Array(response.utf8)))
    }

    private mutating func kittySendError(params: KittyParams, message: String) {
        guard params.quiet == 0 else { return }
        var controlData = "G"
        if params.imageId != 0 {
            controlData += "i=\(params.imageId)"
        } else if params.imageNumber != 0 {
            controlData += "I=\(params.imageNumber)"
        }
        let response = "\u{1b}_\(controlData);\(message)\u{1b}\\"
        pendingActions.append(.sendData(Array(response.utf8)))
    }
}
