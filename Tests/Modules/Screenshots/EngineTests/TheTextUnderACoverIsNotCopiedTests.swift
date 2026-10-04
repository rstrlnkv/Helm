import CoreGraphics
import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **Copy Text leaves out the lines the person covered:** the reading is of the frame without the layers, so a line under a blur, a filled
/// rectangle or ellipse, or a step's circle would reach the clipboard under «Text copied» with the cover undone. A line wholly or partly under
/// one of them is not copied; a stroked shape hides nothing and a line it only outlines is.
final class TheTextUnderACoverIsNotCopiedTests: XCTestCase {

    /// A 1× picture of 200 × 100 pixels at the origin: a line's box of (0.1, 0.5, 0.5, 0.1) is the points (20, 40)-(120, 50).
    private let source = RecognizedBoxes.Source(pixels: CGRect(x: 0, y: 0, width: 200, height: 100), scale: 1)

    private func line(_ string: String, x: CGFloat = 0.1, y: CGFloat = 0.5) -> RecognizedLine {
        RecognizedLine(string: string, box: CGRect(x: x, y: y, width: 0.5, height: 0.1))
    }

    private func layer(_ tool: AnnotationTool, _ rect: CGRect, filled: Bool = false) -> Annotation {
        Annotation(tool: tool, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY),
                   style: AnnotationStyle(filled: filled), id: 1)
    }

    private func kept(_ lines: [RecognizedLine], under layers: [Annotation]) -> [String] {
        CopiedText.lines(lines, source: source, notUnder: layers).map(\.string)
    }

    func testALineWhollyUnderABlurIsNotCopied() {
        XCTAssertEqual(kept([line("secret")], under: [layer(.blur, CGRect(x: 0, y: 30, width: 200, height: 40))]), [])
    }

    func testALineOnlyPartlyUnderABlurIsNotCopiedEither() {
        // The blur reaches x = 30, the line spans 20...120.
        XCTAssertEqual(kept([line("half")], under: [layer(.blur, CGRect(x: 0, y: 30, width: 30, height: 40))]), [])
    }

    func testAFilledShapeAndAStepCoverAndAStrokedOneDoesNot() {
        let over = CGRect(x: 0, y: 30, width: 200, height: 40)
        XCTAssertEqual(kept([line("a")], under: [layer(.rectangle, over, filled: true)]), [])
        XCTAssertEqual(kept([line("a")], under: [layer(.ellipse, over, filled: true)]), [])
        XCTAssertEqual(kept([line("a")], under: [Annotation(tool: .step, start: CGPoint(x: 50, y: 45), end: CGPoint(x: 50, y: 45), id: 1)]), [])
        XCTAssertEqual(kept([line("a")], under: [layer(.rectangle, over)]), ["a"], "a stroked rectangle hides nothing")
        XCTAssertEqual(kept([line("a")], under: [layer(.arrow, over)]), ["a"])
    }

    func testALineAwayFromEveryCoverIsKeptAndTheOrderIsTheReaders() {
        let cover = layer(.blur, CGRect(x: 0, y: 0, width: 200, height: 20))
        XCTAssertEqual(kept([line("one", y: 0.1), line("hidden", y: 0.85), line("three", y: 0.3)], under: [cover]), ["one", "three"])
    }

    func testNoLayersKeepsEveryLineEvenOneThePictureHasNoPlaceFor() {
        let nowhere = RecognizedLine(string: "no box", box: .zero)
        XCTAssertEqual(kept([nowhere, line("b")], under: []), ["no box", "b"])
        XCTAssertEqual(kept([nowhere], under: [layer(.blur, CGRect(x: 0, y: 0, width: 200, height: 100))]), ["no box"],
                       "nothing says a line with no place on the picture is covered")
    }
}
