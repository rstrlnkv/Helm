import CoreGraphics
import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **Copy Text leaves out the lines the person covered:** the reading is of the frame without the layers, so a line under a blur, a filled
/// rectangle or ellipse, or a step's circle would reach the clipboard under «Text copied» with the cover undone. A line wholly or partly under
/// one of them is not copied; a stroked shape hides nothing and a line it only outlines is.
///
/// Mutant, red here: `CopiedText.lines` ignores the covers.
final class TheTextUnderACoverIsNotCopiedTests: XCTestCase {

    /// A 1× picture of 200 × 100 pixels at the origin: a line's box of (0.1, 0.5, 0.5, 0.1) is the points (20, 40)-(120, 50).
    private let source = RecognizedBoxes.Source(pixels: CGRect(x: 0, y: 0, width: 200, height: 100), scale: 1)

    private let box = CGSize(width: 0.5, height: 0.1)

    private func kept(_ lines: [RecognizedLine], under layers: [Annotation]) -> [String] {
        CopiedText.lines(lines, source: source, notUnder: layers).map(\.string)
    }

    func testALineWhollyUnderABlurIsNotCopied() {
        XCTAssertEqual(kept([line("secret", size: box)], under: [layer(.blur, CGRect(x: 0, y: 30, width: 200, height: 40))]), [])
    }

    func testALineOnlyPartlyUnderABlurIsNotCopiedEither() {
        // The blur reaches x = 30, the line spans 20...120.
        XCTAssertEqual(kept([line("half", size: box)], under: [layer(.blur, CGRect(x: 0, y: 30, width: 30, height: 40))]), [])
    }

    func testAFilledShapeAndAStepCoverAndAStrokedOneDoesNot() {
        let over = CGRect(x: 0, y: 30, width: 200, height: 40)
        XCTAssertEqual(kept([line("a", size: box)], under: [layer(.rectangle, over, filled: true)]), [])
        XCTAssertEqual(kept([line("a", size: box)], under: [layer(.ellipse, over, filled: true)]), [])
        XCTAssertEqual(kept([line("a", size: box)], under: [Annotation(tool: .step, start: CGPoint(x: 50, y: 45), end: CGPoint(x: 50, y: 45), id: 1)]), [])
        XCTAssertEqual(kept([line("a", size: box)], under: [layer(.rectangle, over)]), ["a"], "a stroked rectangle hides nothing")
        XCTAssertEqual(kept([line("a", size: box)], under: [layer(.arrow, over)]), ["a"])
    }

    func testALineAwayFromEveryCoverIsKeptAndTheOrderIsTheReaders() {
        let cover = layer(.blur, CGRect(x: 0, y: 0, width: 200, height: 20))
        XCTAssertEqual(kept([line("one", y: 0.1, size: box), line("hidden", y: 0.85, size: box), line("three", y: 0.3, size: box)], under: [cover]), ["one", "three"])
    }

    func testNoLayersKeepsEveryLineEvenOneThePictureHasNoPlaceFor() {
        let nowhere = RecognizedLine(string: "no box", box: .zero)
        XCTAssertEqual(kept([nowhere, line("b", size: box)], under: []), ["no box", "b"])
        XCTAssertEqual(kept([nowhere], under: [layer(.blur, CGRect(x: 0, y: 0, width: 200, height: 100))]), ["no box"],
                       "nothing says a line with no place on the picture is covered")
    }
}
