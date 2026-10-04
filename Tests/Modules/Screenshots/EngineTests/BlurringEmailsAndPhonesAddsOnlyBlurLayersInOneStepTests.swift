import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **"Blur Emails and Phone Numbers" adds blur layers and nothing else, and all of them are one undo step.**
/// The finds are made from a reading (`PersonalFinds`) and put on the picture by `AnnotationEditing.insert(blurs:)`.
final class BlurringEmailsAndPhonesAddsOnlyBlurLayersInOneStepTests: XCTestCase {

    /// The area read: 400 × 200 pixels at the display's origin, 2×. Its points are 200 × 100.
    private let source = RecognizedBoxes.Source(pixels: CGRect(x: 0, y: 0, width: 400, height: 200), scale: 2)
    private let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
    /// Room for the rectangle `drawnAndSelectedRectangle` draws, which is at (200, 200).
    private let room = CGRect(x: 0, y: 0, width: 400, height: 300)

    private func line(_ matches: [PrivateMatch]) -> RecognizedLine {
        RecognizedLine(string: "text", box: CGRect(x: 0, y: 0, width: 1, height: 1), matches: matches)
    }

    /// One of each kind, one under the other, each 0.1 high (10 points) and well apart.
    private var reading: [RecognizedLine] {
        [line([PrivateMatch(kind: .emailAddress, box: CGRect(x: 0.1, y: 0.8, width: 0.4, height: 0.1)),
               PrivateMatch(kind: .phoneNumber, box: CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.1)),
               PrivateMatch(kind: .cardNumber, box: CGRect(x: 0.1, y: 0.4, width: 0.5, height: 0.1)),
               PrivateMatch(kind: .link, box: CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.1))])]
    }

    func testEveryKindOnTheListIsFoundAndEachIsABox() {
        let finds = PersonalFinds.finds(in: reading, source: source, under: [])
        XCTAssertEqual(finds.count, 4, "e-mail, phone, card and link: the whole list")
        XCTAssertEqual(Set(finds.map(\.rect.minY)).count, 4, "four places, one under the other")
    }

    func testTheFindsBecomeBlurLayersAndNothingElseChanges() throws {
        var editing = drawnAndSelectedRectangle(in: room)
        let before = editing.layers
        let finds = PersonalFinds.finds(in: reading, source: source, under: editing.layers)
        XCTAssertEqual(editing.insert(blurs: finds), 4)
        XCTAssertEqual(editing.layers.count, before.count + 4)
        XCTAssertEqual(Array(editing.layers.prefix(before.count)), before, "the layers that were there are untouched")
        let added = Array(editing.layers.dropFirst(before.count))
        XCTAssertTrue(added.allSatisfy { $0.tool == .blur }, "only blur layers: \(added.map(\.tool))")
        XCTAssertEqual(Set(added.map(\.id)).count, 4, "each has an identity of its own")
        XCTAssertTrue(Set(added.map(\.id)).isDisjoint(with: before.map(\.id)))
        XCTAssertTrue(added.allSatisfy(\.isUsable))
        for (layer, find) in zip(added, finds) {
            XCTAssertEqual(layer.frame, find.rect, "the layer is the box that was found")
            XCTAssertEqual(layer.style.thickness, find.step, "its own step, from the height of its text")
        }
        XCTAssertNil(editing.selected, "the selection is let go of")
    }

    func testAllOfThemAreOneUndoStepAndRedoBringsThemBack() {
        var editing = AnnotationEditing(bounds: bounds)
        let finds = PersonalFinds.finds(in: reading, source: source, under: [])
        XCTAssertFalse(editing.canUndo)
        XCTAssertEqual(editing.insert(blurs: finds), 4)
        let after = editing.layers
        XCTAssertTrue(editing.canUndo)
        editing.undo()
        XCTAssertEqual(editing.layers, [], "one undo takes all four")
        XCTAssertFalse(editing.canUndo, "and it was the only step")
        editing.redo()
        XCTAssertEqual(editing.layers, after)
        XCTAssertFalse(editing.canRedo)
    }

    func testTheNextLayerTheyDrawGetsAnIdentityNoBlurHas() {
        var editing = AnnotationEditing(bounds: bounds)
        editing.insert(blurs: PersonalFinds.finds(in: reading, source: source, under: []))
        let used = Set(editing.layers.map(\.id))
        editing.begin(.rectangle, at: CGPoint(x: 5, y: 5))
        editing.drag(to: CGPoint(x: 50, y: 40), shift: false)
        editing.end()
        XCTAssertEqual(editing.layers.count, 5)
        XCTAssertFalse(used.contains(editing.layers.last!.id))
    }

    func testNothingFoundIsNoStepAndNoLayer() {
        var editing = drawnAndSelectedRectangle(in: room)
        let layers = editing.layers
        XCTAssertEqual(editing.insert(blurs: []), 0)
        XCTAssertEqual(editing.layers, layers)
        editing.undo()
        XCTAssertEqual(editing.layers.count, 0, "the undo that is there is the rectangle's, not a blur's")
    }

    func testABoxOutsideTheAreaOrThatIsNotANumberIsLeftOut() {
        var editing = AnnotationEditing(bounds: bounds)
        let outside = RecognizedBoxes.Placed(rect: CGRect(x: 300, y: 10, width: 40, height: 10), step: .thin)
        let nan = RecognizedBoxes.Placed(rect: CGRect(x: CGFloat.nan, y: 10, width: 40, height: 10), step: .thin)
        let thin = RecognizedBoxes.Placed(rect: CGRect(x: 10, y: 10, width: 0.4, height: 10), step: .thin)
        let inside = RecognizedBoxes.Placed(rect: CGRect(x: 10, y: 10, width: 40, height: 10), step: .medium)
        XCTAssertEqual(editing.insert(blurs: [outside, nan, thin, inside]), 1)
        XCTAssertEqual(editing.layers.first?.style.thickness, .medium)
    }

    func testABoxThatReachesPastTheAreaIsKeptToIt() throws {
        var editing = AnnotationEditing(bounds: bounds)
        XCTAssertEqual(editing.insert(blurs: [RecognizedBoxes.Placed(rect: CGRect(x: 150, y: 10, width: 120, height: 10), step: .thin)]), 1)
        let frame = try XCTUnwrap(editing.layers.first?.frame)
        XCTAssertEqual(frame.maxX, 200)
    }

    func testAnEditUnderThePointerOrAMoveStillOpenTakesNothing() {
        var editing = AnnotationEditing(bounds: bounds)
        editing.begin(.rectangle, at: CGPoint(x: 5, y: 5))
        XCTAssertEqual(editing.insert(blurs: PersonalFinds.finds(in: reading, source: source, under: [])), 0)
        XCTAssertTrue(editing.layers.isEmpty)
        XCTAssertEqual(editing.escape(), .dropped, "the draft was open until here")

        var moving = drawnAndSelectedRectangle(in: CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertTrue(moving.press(at: CGPoint(x: 200, y: 230), tool: nil))
        moving.drag(to: CGPoint(x: 210, y: 240), shift: false)
        let count = moving.layers.count
        XCTAssertEqual(moving.insert(blurs: PersonalFinds.finds(in: reading, source: source, under: [])), 0, "a move is open")
        XCTAssertEqual(moving.layers.count, count)
    }

    /// A reading of nothing the list names finds nothing: a line of words and no match is no place to blur.
    func testALineWithNoMatchIsNoPlace() {
        let words = [RecognizedLine(string: "Hello there", box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1))]
        XCTAssertEqual(PersonalFinds.finds(in: words, source: source, under: []), [])
        XCTAssertEqual(PersonalFinds.finds(in: [], source: source, under: []), [])
    }

    /// A reading of a long list of links is bounded: no thousand layers into one step.
    func testAReadingOfAThousandPlacesIsBounded() {
        var matches: [PrivateMatch] = []
        for row in 0..<1000 {
            matches.append(PrivateMatch(kind: .link, box: CGRect(x: 0.001 * CGFloat(row % 100), y: 0.1 * CGFloat(row % 9) + 0.001 * CGFloat(row / 100),
                                                                  width: 0.0004, height: 0.004)))
        }
        let finds = PersonalFinds.finds(in: [line(matches)], source: source, under: [])
        XCTAssertEqual(finds.count, PersonalFinds.limit)
    }
}
