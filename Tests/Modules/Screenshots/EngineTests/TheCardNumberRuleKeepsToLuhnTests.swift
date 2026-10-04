import XCTest
@testable import Module_Screenshots_Engine

/// **Helm's own card-number rule**: thirteen to nineteen ASCII digits, in groups with one space or hyphen
/// between them, that pass the Luhn check — and what it deliberately does not find.
final class TheCardNumberRuleKeepsToLuhnTests: XCTestCase {

    private func found(in text: String) -> [String] {
        CardNumbers.ranges(in: text).map { String(text[$0]) }
    }

    /// `prefix` and the one digit that makes the whole pass the Luhn check, so a test owns a number of any length.
    private func luhn(_ prefix: String) -> String {
        for check in 0...9 where CardNumbers.passesLuhn(prefix + String(check)) { return prefix + String(check) }
        XCTFail("no check digit for \(prefix)")
        return prefix
    }

    func testTheKnownTestNumbersPass() {
        for number in ["4111111111111111", "5500000000000004", "4222222222222", "378282246310005"] {
            XCTAssertTrue(CardNumbers.passesLuhn(number), number)
        }
        XCTAssertFalse(CardNumbers.passesLuhn("4111111111111112"))
        XCTAssertFalse(CardNumbers.passesLuhn(""), "no digits pass nothing")
    }

    func testEveryLengthFromThirteenToNineteenIsFoundAndNoOtherIs() {
        for length in 8...24 {
            let number = luhn(String(repeating: "4", count: length - 1))
            XCTAssertEqual(number.count, length)
            let hits = found(in: "number \(number) end")
            if (13...19).contains(length) {
                XCTAssertEqual(hits, [number], "\(length) digits")
            } else {
                XCTAssertEqual(hits, [], "\(length) digits are no card")
            }
        }
    }

    func testSpacesAndHyphensBetweenTheGroupsAreAllowed() {
        XCTAssertEqual(found(in: "4111 1111 1111 1111"), ["4111 1111 1111 1111"])
        XCTAssertEqual(found(in: "4111-1111-1111-1111"), ["4111-1111-1111-1111"])
        XCTAssertEqual(found(in: "4111 1111-1111 1111"), ["4111 1111-1111 1111"])
        XCTAssertEqual(found(in: "3782 822463 10005"), ["3782 822463 10005"], "groups of any size, 15 digits")
        XCTAssertEqual(found(in: "4111\u{00A0}1111\u{00A0}1111\u{00A0}1111"), ["4111\u{00A0}1111\u{00A0}1111\u{00A0}1111"],
                       "a non-breaking space is a space")
    }

    func testMoreThanOneSeparatorBreaksTheNumber() {
        XCTAssertEqual(found(in: "4111  1111 1111 1111"), ["4111  1111 1111 1111"], "two spaces are still one gap (the rule: one or two spaces)")
        XCTAssertEqual(found(in: "4111   1111 1111 1111"), [], "three spaces: the first group is alone")
        XCTAssertEqual(found(in: "4111 -1111 1111 1111"), [], "a space and a hyphen are two separators")
        XCTAssertEqual(found(in: "4111 - 1111 - 1111 - 1111"), [])
        XCTAssertEqual(found(in: "4111.1111.1111.1111"), [], "a dot is no separator")
    }

    /// A sixteen-digit number that fails the check is something else: an order number, a phone and a code.
    func testASixteenDigitNumberThatFailsTheCheckIsNoCard() {
        XCTAssertEqual(found(in: "4111 1111 1111 1112"), [])
        XCTAssertEqual(found(in: "1234 5678 9012 3456"), [])
    }

    /// Digits inside a longer number are no card: it is the number that is something else.
    func testDigitsInsideALongerNumberAreNoCard() {
        let card = "4111111111111111"
        XCTAssertEqual(found(in: "99" + card + "99"), [], "glued either side: twenty digits")
        XCTAssertEqual(found(in: card + "5"), [], "glued on the end: seventeen digits that fail")
        XCTAssertFalse(CardNumbers.passesLuhn(card + "5"), "the number above is one that fails, so the line proves what it says")
        let twenty = String(repeating: "7", count: 20)
        XCTAssertEqual(found(in: twenty), [])
        XCTAssertEqual(found(in: "x" + luhn("411111111111111") + "x"), [luhn("411111111111111")], "letters round it are not digits")
    }

    /// A security code or a date after the number, with a separator, is not part of it.
    func testWhatFollowsTheNumberAfterASeparatorIsNotPartOfIt() {
        XCTAssertEqual(found(in: "4111 1111 1111 1111 123"), ["4111 1111 1111 1111"])
        XCTAssertEqual(found(in: "card 4111 1111 1111 1111 exp 12/29"), ["4111 1111 1111 1111"])
        XCTAssertEqual(found(in: "12 4111 1111 1111 1111"), ["4111 1111 1111 1111"], "nor what stands before it")
    }

    func testTwoCardsInOneLineAreTwoMatchesInOrder() {
        XCTAssertEqual(found(in: "4111 1111 1111 1111 / 5500 0000 0000 0004"),
                       ["4111 1111 1111 1111", "5500 0000 0000 0004"])
    }

    /// The rule reads ASCII digits only: a number set in Arabic-Indic or full-width digits is not found, and
    /// this is a limit of the rule, not a statement about the number.
    func testDigitsThatAreNotASCIIAreNotRead() {
        XCTAssertEqual(found(in: "٤١١١ ١١١١ ١١١١ ١١١١"), [])
        XCTAssertEqual(found(in: "４１１１ １１１１ １１１１ １１１１"), [])
        XCTAssertEqual(found(in: "4111 1111 1111 1111 ٤"), ["4111 1111 1111 1111"])
    }

    /// The rule sees one line. A card whose digits wrap onto a second line is two numbers of eight digits and is
    /// **not found**, whichever of the two lines holds the check digit.
    func testACardSplitAcrossTwoLinesIsNotFound() {
        XCTAssertEqual(found(in: "4111 1111"), [])
        XCTAssertEqual(found(in: "1111 1111"), [])
        XCTAssertEqual(found(in: "4111 1111\n1111 1111"), [], "a break is no separator either: the groups are not joined")
    }

    func testTheRangesAreInTheTextAndInOrder() {
        let text = "a 4111 1111 1111 1111 b 5500-0000-0000-0004 c"
        let ranges = CardNumbers.ranges(in: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertLessThan(ranges[0].upperBound, ranges[1].lowerBound)
        XCTAssertEqual(CardNumbers.ranges(in: ""), [])
        XCTAssertEqual(CardNumbers.ranges(in: "no digits here"), [])
    }
}
