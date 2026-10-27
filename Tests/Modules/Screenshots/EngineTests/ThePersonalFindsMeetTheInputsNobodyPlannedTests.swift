import CoreGraphics
import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **What "Blur Emails and Phone Numbers" and "Copy Text" do with the readings nobody planned for:** the card rule
/// on numbers that are nearly cards, finds of every size and place, a text taller than the blocks of a blur already
/// over it, and what Copy Text keeps of a huge text.
final class ThePersonalFindsMeetTheInputsNobodyPlannedTests: XCTestCase {

    private let source = RecognizedBoxes.Source(pixels: CGRect(x: 0, y: 0, width: 400, height: 200), scale: 2)
    private let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

    private func reading(_ matches: [PrivateMatch], line string: String = "line") -> [RecognizedLine] {
        [RecognizedLine(string: string, box: CGRect(x: 0, y: 0, width: 1, height: 1), matches: matches)]
    }

    private func found(_ text: String) -> [String] {
        CardNumbers.ranges(in: text).map { String(text[$0]) }
    }

    // MARK: The card rule on numbers that are nearly cards

    func testWhatIsNotACardIsNotOneAndWhatIsIsFoundWhole() {
        let visa = "4111 1111 1111 1111"
        // Short, long, and a 16 digit run that fails Luhn.
        XCTAssertEqual(found("411111111111"), [], "12 digits")
        XCTAssertEqual(found("41111111111111111111"), [], "20 digits")
        XCTAssertEqual(found("4111 1111 1111 1112"), [], "16 digits that fail the check")
        // A valid 16 inside a 30-digit run: no separator ends it, so it is part of a longer number and is no card.
        XCTAssertEqual(found("123456" + "4111111111111111" + "12345678"), [], "a card number glued into a 30-digit number")
        // Mixed separators, one between each group.
        XCTAssertEqual(found("4111 1111-1111 1111"), ["4111 1111-1111 1111"])
        XCTAssertEqual(found("4111\u{00A0}1111\u{00A0}1111\u{00A0}1111"), ["4111\u{00A0}1111\u{00A0}1111\u{00A0}1111"])
        // Glued to letters on either side: letters end a digit group, so the number is found.
        XCTAssertEqual(found("x4111111111111111y"), ["4111111111111111"])
        XCTAssertEqual(found("Card:" + visa + "."), [visa])
        // Two in one line.
        XCTAssertEqual(found(visa + " / 5500 0000 0000 0004"), [visa, "5500 0000 0000 0004"])
        // Two cards with ONE separator between them: the longest run of whole groups that passes the check is taken.
        let both = visa + " 5500 0000 0000 0004"
        XCTAssertFalse(found(both).isEmpty, "two cards with one space between must not hide both from the rule: \(found(both))")
        // Not ASCII digits.
        XCTAssertEqual(found("４１１１ １１１１ １１１１ １１１１"), [], "full-width")
        XCTAssertEqual(found("٤١١١ ١١١١ ١١١١ ١١١١"), [], "Arabic-Indic")
        // A security code and an expiry after it do not extend the number.
        XCTAssertEqual(found(visa + " 12/29 123"), [visa])
        XCTAssertEqual(found(visa + " 123"), [visa])
    }

    /// An IBAN is not a card and not on the list: what the rule does with its digit groups is written down here, not promised.
    func testAnIBANIsTreatedAsWhatItIsAndTheOutcomeIsKnown() {
        // Every run of whole groups of 13 to 19 digits in this IBAN fails the Luhn check (worked out by hand: 89370400440532,
        // 893704004405320130, 3704004405320130, 370400440532013000, 00440532013000), so nothing of it is blurred.
        XCTAssertEqual(found("DE89 3704 0044 0532 0130 00"), [], "an IBAN is not on the list, and by chance a Luhn check lets some through")
    }

    /// A card number as another font, another language or another reading of the same picture spells the gap between its groups. The rule
    /// takes one space, a no-break space or a hyphen; each other gap here is a card that stays on the picture and is not said to.
    func testCardsWithTheOtherGapsASystemReadsAreFoundOrTheMissIsKnown() {
        let gaps: [(String, String)] = [("space", " "), ("hyphen", "-"), ("no-break space", "\u{00A0}"), ("narrow no-break space", "\u{202F}"),
                                        ("thin space", "\u{2009}"), ("en dash", "\u{2013}"), ("non-breaking hyphen", "\u{2011}"),
                                        ("ideographic space", "\u{3000}"), ("two spaces", "  "), ("figure space", "\u{2007}")]
        var missed: [String] = []
        for (name, gap) in gaps {
            let card = ["4111", "1111", "1111", "1111"].joined(separator: gap)
            if found(card) != [card] { missed.append(name) }
        }
        XCTAssertEqual(missed, [], "a card number with these gaps is not found: \(missed)")
    }

    /// The rule against a text that has no end in sight: it must not be quadratic in the digits.
    func testAHugeLineOfDigitsIsReadInTimeAndFindsNothing() {
        let line = String(repeating: "4111 ", count: 40_000)
        let start = Date()
        let ranges = CardNumbers.ranges(in: line)
        let took = Date().timeIntervalSince(start)
        XCTAssertLessThan(took, 2, "200 000 characters of digit groups took \(took) s")
        XCTAssertNotNil(ranges)
        let long = String(repeating: "1", count: 200_000)
        let start2 = Date()
        XCTAssertEqual(CardNumbers.ranges(in: long), [])
        XCTAssertLessThan(Date().timeIntervalSince(start2), 2)
    }

    // MARK: Boxes that are not on the picture

    func testBoxesThatAreNotARectangleOnThePictureMakeNoFindAndNoCrash() {
        let boxes = [CGRect(x: -3, y: -3, width: 1, height: 1), CGRect(x: 2, y: 2, width: 1, height: 1),
                     CGRect(x: 0.5, y: 0.5, width: 0, height: 0), CGRect(x: 0.5, y: 0.5, width: -0.2, height: 0.1),
                     CGRect(x: .nan, y: 0.5, width: 0.2, height: 0.1), CGRect(x: 0.5, y: .infinity, width: 0.2, height: 0.1),
                     CGRect(x: 0.5, y: 0.5, width: .nan, height: 0.1), CGRect(x: 0.5, y: 0.5, width: 0.1, height: -.infinity),
                     CGRect.null, CGRect.infinite, CGRect(x: 0.5, y: 0.5, width: 1e-12, height: 1e-12)]
        for box in boxes {
            let finds = PersonalFinds.finds(in: reading([PrivateMatch(kind: .link, box: box)]), source: source, under: [])
            var editing = AnnotationEditing(bounds: bounds)
            editing.insert(blurs: finds)
            for layer in editing.layers {
                XCTAssertTrue(layer.isUsable, "\(box): \(layer)")
                XCTAssertTrue(bounds.contains(layer.frame), "\(box): \(layer.frame) leaves the area")
            }
        }
        // `.infinite` is a rectangle that holds everything: it is a find the size of the area, and a normal one.
        let all = PersonalFinds.finds(in: reading([PrivateMatch(kind: .link, box: .infinite)]), source: source, under: [])
        XCTAssertLessThanOrEqual(all.count, 1)
    }

    func testAFindLargerThanTheAreaIsKeptToTheArea() throws {
        let finds = PersonalFinds.finds(in: reading([PrivateMatch(kind: .link, box: CGRect(x: -1, y: -1, width: 3, height: 3))]),
                                        source: source, under: [])
        let one = try XCTUnwrap(finds.first)
        XCTAssertEqual(one.rect, bounds)
        XCTAssertEqual(one.step, .thick)
    }

    // MARK: A text taller than an old blur's blocks

    /// A blur of the person's own whose blocks are lower than the text under it leaves the text readable back (`RecognizedBoxes.step`), so it is not "already covered".
    func testATextTallerThanAnOldBlursBlocksIsBlurredAgain() {
        let tall = PrivateMatch(kind: .cardNumber, box: CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.2))
        let thin = Annotation(tool: .blur, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 200, y: 100),
                              style: AnnotationStyle(thickness: .thin), id: 1)
        let finds = PersonalFinds.finds(in: reading([tall]), source: source, under: [thin])
        let own = RecognizedBoxes.place(tall.box, in: source)
        XCTAssertEqual(own?.step, .thick, "the subject: the find would get the thickest block, 20 points of text")
        XCTAssertEqual(finds.count, 1, "text 20 pt high under a 10 pt block is readable back, by the rule of the step: it is blurred again at the step it needs")
    }

    // MARK: Copy

    private func makeRig() -> Rig { Rig(home: scratchDirectory("shots-copy")) }

    func testTenThousandLinesAndAFiveMegabyteStringAreCopiedWhole() {
        let rig = makeRig()
        let lines = (0..<10_000).map { RecognizedLine(string: "line \($0)", box: CGRect(x: 0, y: 0, width: 1, height: 0.001)) }
        XCTAssertEqual(rig.session.copyText(lines), .copied)
        XCTAssertEqual(rig.pasteboard.texts.last?.split(separator: "\n").count, 10_000)
        let big = String(repeating: "x", count: 5_000_000)
        XCTAssertEqual(rig.session.copyText([RecognizedLine(string: big, box: .zero)]), .copied)
        XCTAssertEqual(rig.pasteboard.texts.last?.utf8.count, 5_000_000)
    }

    /// The real pasteboard, a board of its own: text the engine hands it comes back unchanged — NUL, controls, right to left, an astral plane.
    func testTheRealBoardKeepsTheTextItWasGiven() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("helm.test.copytext.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let port = SystemShotPasteboard(named: board.name)
        let cases = ["plain", "tab\tand\u{1}control\u{7F}", "עברית مرحبا \u{202E}mixed", "emoji 👩‍👩‍👧‍👦 and 𝔘𝔫𝔦", "line\r\nbreak", String(repeating: "я", count: 1_000_000)]
        for text in cases {
            XCTAssertEqual(port.copy(text: text), .accepted)
            XCTAssertEqual(board.string(forType: .string), text, "«\(text.prefix(20))»")
        }
        // A NUL: what the board hands back is what went in, or the copy says it was refused.
        let withNul = "before\u{0}after"
        let outcome = port.copy(text: withNul)
        if outcome == .accepted { XCTAssertEqual(board.string(forType: .string), withNul, "a NUL cut the text short and the copy said it was copied") }
    }

    func testBlankAndControlOnlyLinesAreLeftOutAndNothingBlankIsNil() {
        let lines = ["\u{0}", "\u{200B}", " \t ", "\u{FEFF}"].map { RecognizedLine(string: $0, box: .zero) }
        let text = CopiedText.text(of: lines)
        XCTAssertNil(text, "lines of nothing a person can see are no text: \(String(describing: text?.unicodeScalars.map(\.value)))")
    }
}
