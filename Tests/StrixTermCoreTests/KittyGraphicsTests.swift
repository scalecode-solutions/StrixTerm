import Testing
import Foundation
@testable import StrixTermCore

@Suite("Kitty Graphics Protocol")
struct KittyGraphicsTests {

    // MARK: - Helpers

    /// Create a terminal state and send a Kitty graphics sequence.
    private func makeTerminal(cols: Int = 80, rows: Int = 24) -> TerminalState {
        TestHarness.makeTerminal(cols: cols, rows: rows)
    }

    /// Build and feed a Kitty graphics APC sequence.
    private func sendKitty(_ state: inout TerminalState, control: String, payload: [UInt8] = []) {
        let base64 = Data(payload).base64EncodedString()
        let sequence: String
        if payload.isEmpty {
            sequence = "\u{1b}_G\(control)\u{1b}\\"
        } else {
            sequence = "\u{1b}_G\(control);\(base64)\u{1b}\\"
        }
        state.feed(text: sequence)
    }

    /// Collect sendData responses from pending actions.
    private func collectResponses(_ state: inout TerminalState) -> [String] {
        let responses = state.pendingActions.compactMap { action -> String? in
            if case .sendData(let data) = action {
                return String(bytes: data, encoding: .utf8)
            }
            return nil
        }
        state.pendingActions.removeAll()
        return responses
    }

    /// Collect all responses and return them joined.
    private func collectResponseText(_ state: inout TerminalState) -> String {
        collectResponses(&state).joined()
    }

    // MARK: - Single-chunk RGBA Transmission (f=32)

    @Test("Single chunk RGBA transmission stores image")
    func singleChunkRGBA() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // 2x1 RGBA image: 2 pixels * 4 bytes = 8 bytes
        let rgba: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255]
        sendKitty(&state, control: "a=t,f=32,s=2,v=1,i=1", payload: rgba)

        #expect(state.kittyGraphics.imagesById[1] != nil)
        let image = state.kittyGraphics.imagesById[1]!
        #expect(image.width == 2)
        #expect(image.height == 1)
        #expect(image.data.count == 8)
    }

    // MARK: - Raw RGB Transmission (f=24)

    @Test("RGB transmission converts to RGBA")
    func rgbTransmission() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // 1x1 RGB image: 3 bytes
        let rgb: [UInt8] = [255, 128, 0]
        sendKitty(&state, control: "a=t,f=24,s=1,v=1,i=2", payload: rgb)

        #expect(state.kittyGraphics.imagesById[2] != nil)
        let image = state.kittyGraphics.imagesById[2]!
        #expect(image.width == 1)
        #expect(image.height == 1)
        // Should be 4 bytes (RGBA) after conversion
        #expect(image.data.count == 4)
        // Check the conversion: R=255, G=128, B=0, A=255
        let bytes = [UInt8](image.data)
        #expect(bytes == [255, 128, 0, 255])
    }

    // MARK: - Multi-chunk Transmission

    @Test("Multi-chunk transmission accumulates data")
    func multiChunkTransmission() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // 2x1 RGBA image (8 bytes), encoded as one base64 string then split.
        let fullData: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255]
        let fullBase64 = Data(fullData).base64EncodedString()
        // Split the base64 string roughly in half (at a safe position)
        let midpoint = fullBase64.index(fullBase64.startIndex, offsetBy: fullBase64.count / 2)
        let chunk1 = String(fullBase64[..<midpoint])
        let chunk2 = String(fullBase64[midpoint...])

        // First chunk with m=1 (more coming)
        state.feed(text: "\u{1b}_Ga=t,f=32,s=2,v=1,i=3,m=1;\(chunk1)\u{1b}\\")

        // Image should not be stored yet
        #expect(state.kittyGraphics.imagesById[3] == nil)
        #expect(state.kittyGraphics.pendingTransmission != nil)

        // Second chunk with m=0 (final)
        state.feed(text: "\u{1b}_Gm=0;\(chunk2)\u{1b}\\")

        // Now image should be stored
        #expect(state.kittyGraphics.imagesById[3] != nil)
        #expect(state.kittyGraphics.pendingTransmission == nil)
        let image = state.kittyGraphics.imagesById[3]!
        #expect(image.width == 2)
        #expect(image.height == 1)
        #expect(image.data.count == 8)
    }

    // MARK: - Transmit and Display (a=T)

    @Test("Transmit and display creates image and placement")
    func transmitAndDisplay() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=10,p=5,c=2,r=3", payload: rgba)

        #expect(state.kittyGraphics.imagesById[10] != nil)
        let key = KittyPlacementKey(imageId: 10, placementId: 5)
        #expect(state.kittyGraphics.placements[key] != nil)
        let placement = state.kittyGraphics.placements[key]!
        #expect(placement.cols == 2)
        #expect(placement.rows == 3)
    }

    // MARK: - Query (a=q)

    @Test("Query existing image returns OK")
    func queryExisting() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // First transmit an image
        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,i=5", payload: rgba)
        state.pendingActions.removeAll()

        // Query it
        sendKitty(&state, control: "a=q,f=32,s=1,v=1,i=5", payload: rgba)

        let responses = collectResponses(&state)
        #expect(responses.count >= 1)
        let response = responses.first!
        #expect(response.contains("OK"))
        #expect(response.contains("i=5"))
    }

    @Test("Query with bad payload returns error")
    func queryBadPayload() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // Query with empty payload
        state.feed(text: "\u{1b}_Ga=q,f=32,s=1,v=1,i=99\u{1b}\\")

        let responses = collectResponses(&state)
        #expect(responses.count >= 1)
        let response = responses.first!
        #expect(response.contains("EINVAL"))
    }

    // MARK: - Delete Operations

    @Test("Delete all visible placements (d=a)")
    func deleteAllPlacements() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        #expect(!state.kittyGraphics.placements.isEmpty)
        #expect(state.kittyGraphics.imagesById[1] != nil)

        // Delete visible placements (lowercase 'a')
        state.feed(text: "\u{1b}_Ga=d,d=a\u{1b}\\")

        // Placements gone, but image data still present (lowercase = don't free)
        #expect(state.kittyGraphics.placements.isEmpty)
        #expect(state.kittyGraphics.imagesById[1] != nil)
    }

    @Test("Delete all visible placements and cleanup images (d=A)")
    func deleteAllPlacementsAndCleanup() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        // Delete with uppercase 'A' (delete placements AND free unused images)
        state.feed(text: "\u{1b}_Ga=d,d=A\u{1b}\\")

        #expect(state.kittyGraphics.placements.isEmpty)
        #expect(state.kittyGraphics.imagesById.isEmpty)
    }

    @Test("Delete placements by image ID (d=i)")
    func deletePlacementsByImageId() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=2,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        #expect(state.kittyGraphics.imagesById[1] != nil)
        #expect(state.kittyGraphics.imagesById[2] != nil)

        // Delete placements for image 1 (lowercase 'i')
        state.feed(text: "\u{1b}_Ga=d,d=i,i=1\u{1b}\\")

        // Image 1 still exists (lowercase = don't free), image 2 untouched
        #expect(state.kittyGraphics.imagesById[1] != nil)
        #expect(state.kittyGraphics.imagesById[2] != nil)
    }

    @Test("Delete placements by image ID and cleanup (d=I)")
    func deletePlacementsByImageIdAndCleanup() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=2,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        // Delete placements for image 1 with cleanup (uppercase 'I')
        state.feed(text: "\u{1b}_Ga=d,d=I,i=1\u{1b}\\")

        // Image 1 freed (no placements left), image 2 still has placement
        #expect(state.kittyGraphics.imagesById[1] == nil)
        #expect(state.kittyGraphics.imagesById[2] != nil)
    }

    @Test("Delete placements by z-index (d=z)")
    func deleteByZIndex() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1,z=5", payload: rgba)
        state.pendingActions.removeAll()

        #expect(!state.kittyGraphics.placements.isEmpty)

        state.feed(text: "\u{1b}_Ga=d,d=z,z=5\u{1b}\\")

        #expect(state.kittyGraphics.placements.isEmpty)
    }

    @Test("Delete by image ID range (d=r)")
    func deleteByIdRange() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=2,U=1,c=1,r=1", payload: rgba)
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=3,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        // Delete range 1-2 (lowercase, keeps images)
        state.feed(text: "\u{1b}_Ga=d,d=r,x=1,y=2\u{1b}\\")

        // Images still exist
        #expect(state.kittyGraphics.imagesById[1] != nil)
        #expect(state.kittyGraphics.imagesById[2] != nil)
        #expect(state.kittyGraphics.imagesById[3] != nil)
    }

    @Test("Delete by image ID range and cleanup (d=R)")
    func deleteByIdRangeAndCleanup() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=2,U=1,c=1,r=1", payload: rgba)
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=3,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        // Delete range 1-2 with cleanup (uppercase 'R')
        state.feed(text: "\u{1b}_Ga=d,d=R,x=1,y=2\u{1b}\\")

        // Images 1 and 2 freed, 3 still has placement
        #expect(state.kittyGraphics.imagesById[1] == nil)
        #expect(state.kittyGraphics.imagesById[2] == nil)
        #expect(state.kittyGraphics.imagesById[3] != nil)
    }

    // MARK: - Image ID Auto-assignment

    @Test("Image number assigns auto ID")
    func imageNumberMapping() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,I=42", payload: rgba)

        // Should have assigned an auto ID and mapped image number 42 to it
        #expect(state.kittyGraphics.imageNumbers[42] != nil)
        let autoId = state.kittyGraphics.imageNumbers[42]!
        #expect(state.kittyGraphics.imagesById[autoId] != nil)
    }

    // MARK: - Response Format

    @Test("OK response includes image ID")
    func responseFormatWithId() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,i=7", payload: rgba)

        let responses = collectResponses(&state)
        #expect(responses.count >= 1)
        let response = responses.first!
        // Response should be APC G i=7;OK ST
        #expect(response.contains("i=7"))
        #expect(response.contains("OK"))
        #expect(response.hasPrefix("\u{1b}_G"))
        #expect(response.hasSuffix("\u{1b}\\"))
    }

    @Test("OK response includes image number")
    func responseFormatWithNumber() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,I=99", payload: rgba)

        let responses = collectResponses(&state)
        #expect(responses.count >= 1)
        let response = responses.first!
        // Should contain I=99 for image number
        #expect(response.contains("I=99"))
        #expect(response.contains("OK"))
    }

    // MARK: - Suppress Response (q=1)

    @Test("Quiet mode suppresses OK response")
    func quietModeSuppressesResponse() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,i=8,q=1", payload: rgba)

        // Image should be stored
        #expect(state.kittyGraphics.imagesById[8] != nil)

        // No response should be emitted
        let responses = collectResponses(&state)
        let kittyResponses = responses.filter { $0.contains("_G") }
        #expect(kittyResponses.isEmpty)
    }

    @Test("Quiet mode suppresses error response")
    func quietModeSuppressesError() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // Bad payload with q=1 -- should not crash, no response
        state.feed(text: "\u{1b}_Ga=t,f=32,s=1,v=1,i=9,q=1\u{1b}\\")

        let responses = collectResponses(&state)
        let kittyResponses = responses.filter { $0.contains("_G") }
        #expect(kittyResponses.isEmpty)
    }

    // MARK: - Cache Eviction

    @Test("Cache eviction removes oldest images when limit exceeded")
    func cacheEviction() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // Set a very small cache limit
        state.kittyGraphics.cacheLimitBytes = 16

        // Store a 4-byte image
        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,i=1", payload: rgba)
        state.pendingActions.removeAll()
        #expect(state.kittyGraphics.imagesById[1] != nil)

        // Store another 4-byte image
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,i=2", payload: rgba)
        state.pendingActions.removeAll()
        #expect(state.kittyGraphics.imagesById[2] != nil)

        // Store a third 4-byte image
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,i=3", payload: rgba)
        state.pendingActions.removeAll()
        #expect(state.kittyGraphics.imagesById[3] != nil)

        // Store a fourth 4-byte image
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,i=4", payload: rgba)
        state.pendingActions.removeAll()
        #expect(state.kittyGraphics.imagesById[4] != nil)

        // Now total is 16 bytes which is at the limit.
        // Store a fifth, pushing us over
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,i=5", payload: rgba)
        state.pendingActions.removeAll()

        // The oldest image(s) should have been evicted
        #expect(state.kittyGraphics.totalImageBytes <= state.kittyGraphics.cacheLimitBytes)
        // Image 5 should exist since it's the newest
        #expect(state.kittyGraphics.imagesById[5] != nil)
    }

    // MARK: - PNG Transmission (f=100)

    @Test("PNG transmission parses IHDR dimensions")
    func pngTransmission() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // Minimal valid PNG: 1x1 pixel, white, RGBA
        // This is a real minimal PNG file
        let pngData: [UInt8] = [
            // PNG signature
            137, 80, 78, 71, 13, 10, 26, 10,
            // IHDR chunk
            0, 0, 0, 13,  // length = 13
            73, 72, 68, 82, // "IHDR"
            0, 0, 0, 1,   // width = 1
            0, 0, 0, 1,   // height = 1
            8,             // bit depth
            2,             // color type (RGB)
            0,             // compression method
            0,             // filter method
            0,             // interlace method
            // IHDR CRC (doesn't need to be valid for dimension parsing)
            0, 0, 0, 0,
            // IDAT chunk (minimal)
            0, 0, 0, 12,
            73, 68, 65, 84,
            8, 215, 99, 248, 207, 0, 0, 0, 4, 0, 1,
            0,
            // IDAT CRC
            0, 0, 0, 0,
            // IEND chunk
            0, 0, 0, 0,
            73, 69, 78, 68,
            174, 66, 96, 130
        ]
        sendKitty(&state, control: "a=t,f=100,i=20", payload: pngData)

        #expect(state.kittyGraphics.imagesById[20] != nil)
        let image = state.kittyGraphics.imagesById[20]!
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    // MARK: - Put (a=p)

    @Test("Put displays a previously transmitted image")
    func putDisplaysImage() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // First transmit
        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,i=15", payload: rgba)
        state.pendingActions.removeAll()

        // Then put/display
        state.feed(text: "\u{1b}_Ga=p,i=15,p=1,c=3,r=2\u{1b}\\")

        // Should have created a placement
        let key = KittyPlacementKey(imageId: 15, placementId: 1)
        #expect(state.kittyGraphics.placements[key] != nil)
    }

    @Test("Put for missing image returns error")
    func putMissingImage() {
        var state = makeTerminal()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}_Ga=p,i=999\u{1b}\\")

        let responses = collectResponses(&state)
        #expect(responses.count >= 1)
        let response = responses.first!
        #expect(response.contains("ENOENT"))
    }

    // MARK: - Delete at cursor (d=c)

    @Test("Delete at cursor position")
    func deleteAtCursor() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // Position cursor at 0,0 and create image there
        state.feed(text: "\u{1b}[1;1H")
        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        #expect(!state.kittyGraphics.placements.isEmpty)

        state.feed(text: "\u{1b}_Ga=d,d=c\u{1b}\\")

        #expect(state.kittyGraphics.placements.isEmpty)
    }

    // MARK: - Delete by column (d=x)

    @Test("Delete by column")
    func deleteByColumn() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        #expect(!state.kittyGraphics.placements.isEmpty)

        // Delete by column 1 (1-based)
        state.feed(text: "\u{1b}_Ga=d,d=x,x=1\u{1b}\\")

        #expect(state.kittyGraphics.placements.isEmpty)
    }

    // MARK: - Delete by row (d=y)

    @Test("Delete by row")
    func deleteByRow() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        #expect(!state.kittyGraphics.placements.isEmpty)

        // Delete by row 1 (1-based)
        state.feed(text: "\u{1b}_Ga=d,d=y,y=1\u{1b}\\")

        #expect(state.kittyGraphics.placements.isEmpty)
    }

    // MARK: - Delete at specific cell (d=p)

    @Test("Delete at specific cell")
    func deleteAtSpecificCell() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        #expect(!state.kittyGraphics.placements.isEmpty)

        state.feed(text: "\u{1b}_Ga=d,d=p,x=1,y=1\u{1b}\\")

        #expect(state.kittyGraphics.placements.isEmpty)
    }

    // MARK: - Mutually exclusive i and I

    @Test("Both i and I specified returns error")
    func mutuallyExclusiveIdAndNumber() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,i=1,I=2", payload: rgba)

        let responses = collectResponses(&state)
        let kittyResponses = responses.filter { $0.contains("_G") }
        #expect(kittyResponses.count >= 1)
        #expect(kittyResponses.first!.contains("EINVAL"))
    }

    // MARK: - Full reset clears kitty state

    @Test("Full terminal reset clears kitty state")
    func fullResetClearsState() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=T,f=32,s=1,v=1,i=1,U=1,c=1,r=1", payload: rgba)
        state.pendingActions.removeAll()

        #expect(state.kittyGraphics.imagesById[1] != nil)
        #expect(!state.kittyGraphics.placements.isEmpty)

        // ESC c = full reset (RIS)
        state.feed(text: "\u{1b}c")

        #expect(state.kittyGraphics.imagesById.isEmpty)
        #expect(state.kittyGraphics.imageNumbers.isEmpty)
        #expect(state.kittyGraphics.placements.isEmpty)
    }

    // MARK: - Parser APC routing

    @Test("APC with non-G prefix is ignored")
    func apcNonGraphicsIgnored() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // Send an APC that doesn't start with 'G'
        state.feed(text: "\u{1b}_Xsome-data\u{1b}\\")

        // Should not crash, no kitty state changes
        #expect(state.kittyGraphics.imagesById.isEmpty)
    }

    @Test("APC sequence is properly parsed and dispatched")
    func apcParsing() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [10, 20, 30, 40]
        let base64 = Data(rgba).base64EncodedString()

        // Manually construct the full escape sequence
        state.feed(text: "\u{1b}_Ga=t,f=32,s=1,v=1,i=42;\(base64)\u{1b}\\")

        #expect(state.kittyGraphics.imagesById[42] != nil)
    }

    // MARK: - Delete clears pending transmission

    @Test("Delete action clears pending transmission")
    func deleteClearsPending() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // Start a chunked transmission
        let chunk = Data([1, 2, 3, 4]).base64EncodedString()
        state.feed(text: "\u{1b}_Ga=t,f=32,s=2,v=1,i=1,m=1;\(chunk)\u{1b}\\")
        #expect(state.kittyGraphics.pendingTransmission != nil)

        // Delete action should clear pending
        state.feed(text: "\u{1b}_Ga=d,d=a\u{1b}\\")
        #expect(state.kittyGraphics.pendingTransmission == nil)
    }

    // MARK: - Image number to ID mapping with put

    @Test("Put by image number resolves to correct image")
    func putByImageNumber() {
        var state = makeTerminal()
        defer { state.deallocate() }

        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=t,f=32,s=1,v=1,I=50", payload: rgba)
        state.pendingActions.removeAll()

        // Should have mapped image number 50 to an auto-assigned ID
        guard let autoId = state.kittyGraphics.imageNumbers[50] else {
            Issue.record("Image number 50 was not mapped")
            return
        }

        // Put using image number
        state.feed(text: "\u{1b}_Ga=p,I=50,p=1\u{1b}\\")

        // Should have a placement referencing the correct image ID
        let key = KittyPlacementKey(imageId: autoId, placementId: 1)
        #expect(state.kittyGraphics.placements[key] != nil)
    }

    // MARK: - Unsupported action

    @Test("Unsupported action returns error")
    func unsupportedAction() {
        var state = makeTerminal()
        defer { state.deallocate() }

        state.feed(text: "\u{1b}_Ga=Z\u{1b}\\")

        let responses = collectResponses(&state)
        // No payload means this should generate an error
        // Actually "Z" is unsupported action
        let kittyResponses = responses.filter { $0.contains("_G") }
        #expect(kittyResponses.count >= 1)
        #expect(kittyResponses.first!.contains("EINVAL"))
    }

    // MARK: - Wrong data size

    @Test("Wrong data size for RGBA returns error")
    func wrongDataSize() {
        var state = makeTerminal()
        defer { state.deallocate() }

        // Claim 2x2 but only send 1 pixel worth of data
        let rgba: [UInt8] = [1, 2, 3, 4]
        sendKitty(&state, control: "a=t,f=32,s=2,v=2,i=1", payload: rgba)

        // Should fail since 2*2*4=16 bytes needed but only 4 provided
        #expect(state.kittyGraphics.imagesById[1] == nil)

        let responses = collectResponses(&state)
        let kittyResponses = responses.filter { $0.contains("_G") }
        #expect(kittyResponses.count >= 1)
        #expect(kittyResponses.first!.contains("EINVAL"))
    }
}
