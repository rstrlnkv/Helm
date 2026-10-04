import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **A find lying wholly under a blur already placed is skipped**, so a second press adds nothing, and what the
/// person covered by hand is not covered twice. A find that is only partly under one is made, and so is one
/// under a layer that is not a blur.
final class TheFindsUnderABlurAreSkippedTests: XCTestCase {

    private let source = RecognizedBoxes.Source(pixels: CGRect(x: 0, y: 0, width: 400, height: 200), scale: 2)
    private let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
    /// The text's own box in points: x 20…100, y 10…20.
    private let email = PrivateMatch(kind: .emailAddress, box: CGRect(x: 0.1, y: 0.85, width: 0.4, height: 0.05))

    private func reading(_ matches: PrivateMatch...) -> [RecognizedLine] {
        [RecognizedLine(string: "line", box: CGRect(x: 0, y: 0, width: 1, height: 1), matches: matches)]
    }

    private func layer(_ tool: AnnotationTool, _ rect: CGRect) -> Annotation {
        Annotation(tool: tool, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), id: 77)
    }

    func testTheSubjectIsFoundWhenNothingCoversIt() throws {
        let finds = PersonalFinds.finds(in: reading(email), source: source, under: [])
        XCTAssertEqual(finds.count, 1, "the subject of every test below")
        let ink = try XCTUnwrap(RecognizedBoxes.ink(of: email.box, in: source))
        let got = [ink.minX, ink.minY, ink.width, ink.height], want: [CGFloat] = [20, 10, 80, 5]
        for (value, expected) in zip(got, want) {
            XCTAssertEqual(value, expected, accuracy: 1e-9, "and it is where the layers below are put")
        }
    }

    func testAFindWhollyUnderABlurIsSkipped() {
        let under = layer(.blur, CGRect(x: 10, y: 5, width: 100, height: 20))
        XCTAssertEqual(PersonalFinds.finds(in: reading(email), source: source, under: [under]), [])
        let exact = layer(.blur, CGRect(x: 20, y: 10, width: 80, height: 5))
        XCTAssertEqual(PersonalFinds.finds(in: reading(email), source: source, under: [exact]), [], "a blur of exactly the text covers it")
    }

    func testAFindOnlyPartlyUnderABlurIsMade() {
        let half = layer(.blur, CGRect(x: 10, y: 5, width: 50, height: 20))
        XCTAssertEqual(PersonalFinds.finds(in: reading(email), source: source, under: [half]).count, 1)
        let short = layer(.blur, CGRect(x: 10, y: 5, width: 100, height: 8))
        XCTAssertEqual(PersonalFinds.finds(in: reading(email), source: source, under: [short]).count, 1, "the lower part shows")
    }

    /// Only a blur hides what is under it: a rectangle or a highlight is drawn over it and leaves it readable.
    func testALayerThatIsNotABlurHidesNothing() {
        for tool in [AnnotationTool.rectangle, .ellipse, .highlighter, .pen, .spotlight] {
            let over = layer(tool, CGRect(x: 10, y: 5, width: 100, height: 20))
            XCTAssertEqual(PersonalFinds.finds(in: reading(email), source: source, under: [over]).count, 1, "\(tool)")
        }
    }

    func testABlurElsewhereCoversNothingHere() {
        let elsewhere = layer(.blur, CGRect(x: 120, y: 60, width: 60, height: 30))
        XCTAssertEqual(PersonalFinds.finds(in: reading(email), source: source, under: [elsewhere]).count, 1)
    }

    /// Pressing twice: what the first press put is what the second finds covered.
    func testASecondPressOverTheSamePictureAddsNothing() {
        var editing = AnnotationEditing(bounds: bounds)
        let phone = PrivateMatch(kind: .phoneNumber, box: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.05))
        let lines = reading(email, phone)
        XCTAssertEqual(editing.insert(blurs: PersonalFinds.finds(in: lines, source: source, under: editing.layers)), 2)
        let again = PersonalFinds.finds(in: lines, source: source, under: editing.layers)
        XCTAssertEqual(again, [])
        XCTAssertEqual(editing.insert(blurs: again), 0)
        XCTAssertEqual(editing.layers.count, 2)
        editing.undo()
        XCTAssertTrue(editing.layers.isEmpty, "one undo took the one press's layers, and the second press made no step")
    }

    /// A blur the person deleted is a find again.
    func testADeletedBlurIsFoundAgain() {
        var editing = AnnotationEditing(bounds: bounds)
        editing.insert(blurs: PersonalFinds.finds(in: reading(email), source: source, under: []))
        editing.undo()
        XCTAssertEqual(PersonalFinds.finds(in: reading(email), source: source, under: editing.layers).count, 1)
    }

    /// Of two finds in the same place — the card number the system also reads as a phone number — one box; of a
    /// find and a bigger one round it, the bigger; of two equal ones, the first.
    func testAFindInsideAnotherOfTheSameReadingIsOnePlace() {
        let card = PrivateMatch(kind: .cardNumber, box: CGRect(x: 0.1, y: 0.5, width: 0.5, height: 0.05))
        let phone = PrivateMatch(kind: .phoneNumber, box: CGRect(x: 0.2, y: 0.5, width: 0.2, height: 0.05))
        XCTAssertEqual(PersonalFinds.finds(in: reading(card, phone), source: source, under: []).count, 1)
        XCTAssertEqual(PersonalFinds.finds(in: reading(phone, card), source: source, under: []).count, 1, "whichever comes first")
        let twin = PrivateMatch(kind: .link, box: card.box)
        let both = PersonalFinds.finds(in: reading(card, twin), source: source, under: [])
        XCTAssertEqual(both.count, 1, "two equal places are one")
        XCTAssertEqual(both, PersonalFinds.finds(in: reading(card), source: source, under: []))
        XCTAssertEqual(PersonalFinds.finds(in: reading(email, card), source: source, under: []).count, 2, "apart, they are two")
    }

    /// A match that is not on the area read — a line of the picture's edge the area cut — makes no find.
    func testAMatchOffTheAreaIsNoFind() {
        let off = PrivateMatch(kind: .link, box: CGRect(x: 1.5, y: 0.5, width: 0.1, height: 0.1))
        XCTAssertEqual(PersonalFinds.finds(in: reading(off), source: source, under: []), [])
    }
}
