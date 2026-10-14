import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The floor a found blur keeps under its block** (`AnnotationStyle.blockFloor`) stays with that layer and with nothing
/// else, and a floor that is not a height is no floor.
final class TheFloorOfAFoundBlursBlockMeetsInputsNobodyPlannedTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    /// One found layer, 40 points of text, over (10, 10) to (110, 70).
    private func editingWithAFoundLayer(floor: CGFloat = 40) -> AnnotationEditing {
        var editing = AnnotationEditing(bounds: bounds)
        let find = RecognizedBoxes.Placed(rect: CGRect(x: 10, y: 10, width: 100, height: 60), step: .thick, textHeight: floor)
        XCTAssertEqual(editing.insert(blurs: [find]), 1)
        return editing
    }

    /// A blur the person draws afterwards, with the style the editor remembers, takes the step and no floor, whether or not the
    /// found layer is selected: the editor's remembered style is built from the store's picks, none of which is a floor.
    func testABlurDrawnByHandAfterAFoundOneIsSelectedHasNoFloor() throws {
        var editing = editingWithAFoundLayer()
        XCTAssertTrue(editing.press(at: CGPoint(x: 60, y: 40), tool: nil))
        editing.end()
        let found = try XCTUnwrap(editing.selected)
        XCTAssertEqual(found.blockPoints, 40)

        var memory = EditorMemory()
        memory.note(style: found.style, for: .blur)
        XCTAssertEqual(memory.style(for: .blur).blockFloor, 0, "the remembered style of the blur tool carries no floor")
        XCTAssertEqual(memory.style(for: .blur).blockPoints, memory.style(for: .blur).thickness.points(for: .blur))

        XCTAssertTrue(editing.press(at: CGPoint(x: 300, y: 300), tool: .blur, style: memory.style(for: .blur)))
        editing.drag(to: CGPoint(x: 500, y: 400), shift: false)
        editing.end()
        let drawn = try XCTUnwrap(editing.layers.last)
        XCTAssertEqual(drawn.tool, .blur)
        XCTAssertNotEqual(drawn.id, found.id)
        XCTAssertEqual(drawn.blockPoints, memory.style(for: .blur).thickness.points(for: .blur),
                       "a blur drawn by hand has the step's block, not the found layer's 40")
        XCTAssertEqual(editing.layers.first?.blockPoints, 40, "and the found layer keeps its own")
    }

    /// Undo takes the layers away and redo gives back the same values: the floor is a part of the layer.
    func testUndoAndRedoCarryTheFloor() throws {
        var editing = editingWithAFoundLayer()
        editing.undo()
        XCTAssertTrue(editing.layers.isEmpty)
        editing.redo()
        XCTAssertEqual(editing.layers.map(\.blockPoints), [40])
        // A thickness edit and its undo: the floor is there before, after, and after the undo.
        XCTAssertTrue(editing.press(at: CGPoint(x: 60, y: 40), tool: nil))
        editing.end()
        editing.setThickness(.thin)
        XCTAssertEqual(editing.layers.map(\.blockPoints), [40])
        editing.undo()
        XCTAssertEqual(editing.layers.map(\.blockPoints), [40])
        XCTAssertEqual(editing.layers.first?.style.thickness, .thick)
    }

    /// Making the layer smaller by its handle rebuilds its geometry, not its style: the block stays the text's.
    func testResizingAndMovingAFoundLayerKeepsItsFloor() throws {
        var editing = editingWithAFoundLayer()
        XCTAssertTrue(editing.press(at: CGPoint(x: 60, y: 40), tool: nil))
        editing.end()
        let corner = try XCTUnwrap(editing.selected?.handles.first { $0.handle == .bottomRight }?.point)
        XCTAssertTrue(editing.press(at: corner, tool: nil))
        editing.drag(to: CGPoint(x: corner.x - 40, y: corner.y - 20), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.count, 1)
        XCTAssertEqual(try XCTUnwrap(editing.layers.first).frame.width, 60, accuracy: 1e-9, "the handle made it narrower")
        XCTAssertEqual(editing.layers.first?.blockPoints, 40)
        XCTAssertTrue(editing.nudgeSelected(by: CGPoint(x: 5, y: 5)))
        XCTAssertEqual(editing.layers.first?.blockPoints, 40, "a move keeps it")
    }

    /// A floor that is not a height counts for none: the layer's block is the step's whatever the number, and the mosaic of it is a
    /// tile and not a trap.
    func testAFloorThatIsNotAHeightIsNoFloor() throws {
        for floor in [CGFloat.nan, .infinity, -.infinity, -5, 0, -0.0] {
            let editing = editingWithAFoundLayer(floor: floor)
            let layer = try XCTUnwrap(editing.layers.first, "floor \(floor)")
            XCTAssertEqual(layer.blockPoints, 24, "floor \(floor): the thick step's block")
            let display = try XCTUnwrap(Self.noise(width: 200, height: 200))
            XCTAssertNotNil(Pixelate.tile(of: display, rect: layer.frame, blockPoints: layer.blockPoints, scale: 1), "floor \(floor)")
        }
        // The step is still the floor of a step: a floor under it changes nothing.
        XCTAssertEqual(AnnotationStyle(thickness: .thick, blockFloor: 10).blockPoints, 24)
        XCTAssertEqual(AnnotationStyle(thickness: .thin, blockFloor: 40.5).blockPoints, 40.5)
    }

    /// A find 40.3 points high at 1×: the layer's block is the find's height; the file's block is `round(40.3)` = 40 pixels, 0.3 of a
    /// pixel under the text: the block is whole pixels (`Pixelate.block`), the text's height is not.
    func testTheFilesBlockOfAFindWithAFractionIsTheRoundedOne() throws {
        let source = RecognizedBoxes.Source(pixels: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 1)
        let box = CGRect(x: 0.2, y: 0.5, width: 0.3, height: 0.0403)
        let ink = try XCTUnwrap(RecognizedBoxes.ink(of: box, in: source))
        let placed = try XCTUnwrap(RecognizedBoxes.place(box, in: source))
        var editing = AnnotationEditing(bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        XCTAssertEqual(editing.insert(blurs: [placed]), 1)
        let layer = try XCTUnwrap(editing.layers.first)
        let fileSide = Pixelate.block(points: layer.blockPoints, scale: 1)
        XCTAssertEqual(ink.height, 40.3, accuracy: 1e-9)
        XCTAssertEqual(layer.blockPoints, 40.3, accuracy: 1e-9)
        XCTAssertEqual(fileSide, 40, "the file's block is the rounded one")
        XCTAssertEqual(placed.rect.height.truncatingRemainder(dividingBy: 40), 0, "the box is made of whole file blocks")
    }

    /// A picture in which no two pixels side by side are alike, nor two stacked ones at a width that is not a multiple of 256.
    private static func noise(width: Int, height: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            bytes[i * 4] = UInt8(truncatingIfNeeded: i &* 37); bytes[i * 4 + 1] = UInt8(truncatingIfNeeded: i &* 91)
            bytes[i * 4 + 2] = UInt8(truncatingIfNeeded: i &* 53)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
