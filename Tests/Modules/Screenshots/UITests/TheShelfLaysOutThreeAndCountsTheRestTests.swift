import AppKit
import CoreGraphics
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The shelf is three slots wide whatever the list holds, and «N more» counts the shots no part of which is seen.**
/// `ShotShelf` is numbers: asked here with counts the window never reaches (0, 1000), offsets and deltas that are
/// not numbers, and every rest the row can stand on. The expected values come from the slot arithmetic written out
/// by hand (the row at rest `k` shows the ages `k`, `k+1`, `k+2`, and the ages from `k+3` on are what «more» counts),
/// not from `ShotShelf`'s own formulas, which both sides of an assertion reading the same declaration would repeat.
///
/// Total failure of the subject prints: a count that is one off at the first or the last rest, a «more» that
/// counts the shot the row's edge cuts, a row that scrolls to a place that is not a number, a list of 21 shots or a
/// shot that is pushed out twice or never.
@MainActor
final class TheShelfLaysOutThreeAndCountsTheRestTests: XCTestCase {

    /// The mockup's numbers; a change of either is one failure here that says to read the arithmetic below again.
    private let slot: CGFloat = 200, gap: CGFloat = 16
    private var pitch: CGFloat { slot + gap }
    private let counts = [0, 1, 2, 3, 4, 5, 6, 19, 20, 21, 25, 1000]
    private func held(_ n: Int) -> Int { min(n, 20) }
    private func more(_ n: Int, _ offset: CGFloat) -> [Int]? { ShotShelf.more(count: n, offset: offset).map { [$0.on, $0.count] } }

    func testTheNumbersTheArithmeticBelowStandsOn() {
        XCTAssertEqual(ShotThumbnail.maxWidth, slot)
        XCTAssertEqual(ShotShelf.gap, gap)
        XCTAssertEqual(ShotShelf.pitch, pitch)
        XCTAssertEqual(ShotShelf.limit, 20)
        XCTAssertEqual(ShotShelf.visible, 3)
    }

    // MARK: Width and reach

    func testTheRowIsAsWideAsTheShotsThereAreUpToThreeAndNoWiderForTwentyOrAThousand() {
        for n in counts {
            let slots = CGFloat(min(n, 3))
            let expected = slots == 0 ? 0 : slots * slot + (slots - 1) * gap
            XCTAssertEqual(ShotShelf.width(count: n), expected, "width of \(n)")
            XCTAssertEqual(ShotShelf.farthest(count: n), CGFloat(max(0, held(n) - 3)) * pitch, "reach of \(n)")
        }
        XCTAssertEqual(ShotShelf.width(count: -4), 0)
        XCTAssertEqual(ShotShelf.width(count: Int.min), 0)
        XCTAssertEqual(ShotShelf.width(count: Int.max), 3 * slot + 2 * gap)
        XCTAssertEqual(ShotShelf.farthest(count: Int.max), 17 * pitch, "a count no list reaches is the list's bound")
        XCTAssertEqual(ShotShelf.farthest(count: Int.min), 0)
    }

    // MARK: «N more»

    /// At a rest `k` the seen shots are the ages `k`…`k+2`, whole; the ones older than that are what is counted.
    func testMoreAtEveryRestCountsTheOlderOnesAndNamesTheFarthestSeen() {
        for n in counts {
            for k in 0...max(0, held(n) - 3) {
                let older = held(n) - (k + 3)
                let expected: [Int]? = older > 0 ? [k + 2, older] : nil
                XCTAssertEqual(more(n, CGFloat(k) * pitch), expected, "\(n) shots at rest \(k)")
            }
        }
    }

    /// A rest that came out of a scroll is a hair off a whole slot, and is still that rest.
    func testARestAHairOffIsStillTheRest() {
        for k in 0...4 {
            let expected = more(9, CGFloat(k) * pitch)
            XCTAssertNotNil(expected)
            for hair: CGFloat in [-0.4, 0.2, 0.4] where CGFloat(k) * pitch + hair >= 0 {
                XCTAssertEqual(more(9, CGFloat(k) * pitch + hair), expected, "rest \(k) \(hair) off")
            }
        }
    }

    /// Between two rests the shot the row's left edge cuts is seen, and is not «more»; once the next one begins
    /// to leave the gap behind it, the count follows it.
    func testBetweenTwoRestsTheCutShotIsSeenAndNotCounted() {
        let n = 12
        for k in 0...(n - 4) {
            // `gap` into the move the shot older than the last whole one is still all in the gap, unseen.
            let inGap: [Int]? = n - (k + 3) > 0 ? [k + 2, n - (k + 3)] : nil
            XCTAssertEqual(more(n, CGFloat(k) * pitch + 10), inGap, "10 into \(k)")
            for d: CGFloat in [17, 54, 108, 200, 215] {
                let older = n - (k + 4)
                let cut: [Int]? = older > 0 ? [k + 2, older] : nil
                XCTAssertEqual(more(n, CGFloat(k) * pitch + d), cut, "\(d) into \(k)")
            }
        }
    }

    /// Nothing is more when every shot is seen: a list of three or fewer, and the row scrolled to its oldest.
    func testNothingIsMoreWhenEveryShotIsSeen() {
        for n in 0...3 { XCTAssertNil(more(n, 0), "\(n) shots") }
        XCTAssertNil(more(4, pitch))
        XCTAssertNil(more(20, ShotShelf.farthest(count: 20)))
        XCTAssertNil(more(1000, .infinity), "the farthest rest of a list of any length")
        XCTAssertEqual(more(1000, 0), [2, 17], "a thousand is twenty")
    }

    // MARK: Offsets and deltas that are not numbers

    func testAnOffsetThatIsNotANumberOrIsPastTheEndsIsTheNearerEnd() {
        for n in [0, 1, 3, 4, 7, 25, 1000] {
            let far = ShotShelf.farthest(count: n)
            for odd: CGFloat in [.nan, -.infinity, -1, -1e30, -0.0] {
                XCTAssertEqual(ShotShelf.clamped(odd, count: n), 0, "\(odd) of \(n)")
                XCTAssertEqual(ShotShelf.snapped(odd, count: n), 0)
                XCTAssertEqual(more(n, odd), more(n, 0))
                XCTAssertEqual(ShotShelf.shift(age: 1, offset: odd, count: n), ShotShelf.shift(age: 1, offset: 0, count: n))
            }
            for odd: CGFloat in [.infinity, 1e30, far + 1] {
                XCTAssertEqual(ShotShelf.clamped(odd, count: n), far, "\(odd) of \(n)")
                XCTAssertEqual(ShotShelf.snapped(odd, count: n), far)
                XCTAssertEqual(more(n, odd), more(n, far))
            }
        }
    }

    func testAScrollIsClampedAndOneThatIsNotANumberMovesNothing() {
        let far = ShotShelf.farthest(count: 7)
        XCTAssertEqual(far, 4 * pitch)
        XCTAssertEqual(ShotShelf.scrolled(0, by: .nan, count: 7), 0)
        XCTAssertEqual(ShotShelf.scrolled(300, by: .nan, count: 7), 300)
        XCTAssertEqual(ShotShelf.scrolled(300, by: .nan, precise: false, count: 7), 300)
        XCTAssertEqual(ShotShelf.scrolled(0, by: .infinity, count: 7), far)
        XCTAssertEqual(ShotShelf.scrolled(300, by: -.infinity, count: 7), 0)
        XCTAssertEqual(ShotShelf.scrolled(0, by: -.infinity, count: 7), 0)
        XCTAssertEqual(ShotShelf.scrolled(0, by: 100, count: 7), 100)
        XCTAssertEqual(ShotShelf.scrolled(100, by: -250, count: 7), 0)
        XCTAssertEqual(ShotShelf.scrolled(far, by: 100, count: 7), far)
        XCTAssertEqual(ShotShelf.scrolled(.nan, by: 50, count: 7), 50, "a start that is not a number is the rest by the newest")
        XCTAssertEqual(ShotShelf.scrolled(.infinity, by: -50, count: 7), far - 50)
        // A wheel that counts notches moves a slot a notch, whatever the number, and one at a time.
        XCTAssertEqual(ShotShelf.scrolled(0, by: 0.001, precise: false, count: 7), pitch)
        XCTAssertEqual(ShotShelf.scrolled(0, by: 1e9, precise: false, count: 7), pitch)
        XCTAssertEqual(ShotShelf.scrolled(pitch, by: -0.001, precise: false, count: 7), 0)
        XCTAssertEqual(ShotShelf.scrolled(0, by: -3, precise: false, count: 7), 0)
        XCTAssertEqual(ShotShelf.scrolled(100, by: 0, precise: false, count: 7), 100, "a notch of nothing is nothing")
        XCTAssertEqual(ShotShelf.scrolled(far, by: 1, precise: false, count: 7), far)
        // A list with nothing to scroll to never leaves the rest.
        for n in 0...3 {
            for delta: CGFloat in [-1e9, -1, 0, 1, 1e9, .infinity, -.infinity, .nan] {
                XCTAssertEqual(ShotShelf.scrolled(0, by: delta, count: n), 0, "\(delta) of \(n)")
                XCTAssertEqual(ShotShelf.scrolled(0, by: delta, precise: false, count: n), 0)
            }
        }
        XCTAssertEqual(ShotShelf.scrolled(0, by: .infinity, count: 1000), 17 * pitch)
    }

    func testARestIsAWholeSlotTheNearestOneAndRestingTwiceMovesNothing() {
        for n in [4, 7, 20, 21, 1000] {
            let far = ShotShelf.farthest(count: n)
            var offset: CGFloat = -60
            while offset < far + 60 {
                let rest = ShotShelf.snapped(offset, count: n)
                XCTAssertEqual(rest / pitch, (rest / pitch).rounded(), accuracy: 1e-9, "\(offset) of \(n) is no whole slot")
                XCTAssertTrue((0...far).contains(rest))
                XCTAssertEqual(ShotShelf.snapped(rest, count: n), rest)
                let near = ShotShelf.clamped(offset, count: n)
                XCTAssertLessThanOrEqual(abs(rest - near), pitch / 2 + 1e-9, "\(offset) of \(n) went to the far rest")
                offset += 7.3
            }
        }
        XCTAssertEqual(ShotShelf.snapped(107.9, count: 7), 0)
        XCTAssertEqual(ShotShelf.snapped(108, count: 7), pitch, "half a slot goes toward the older shots, as `rounded()` does")
        XCTAssertEqual(ShotShelf.snapped(324, count: 7), 2 * pitch)
        XCTAssertEqual(ShotShelf.snapped(50, count: 3), 0, "three shots have no rest but the first")
    }

    // MARK: Where a slot stands

    func testASlotStandsWhereItsAgeAndTheOffsetPutIt() {
        // 7 shots: the row is 632 wide, the newest's slot (age 0) at the trailing end, 432.
        XCTAssertEqual(ShotShelf.leading(age: 0, offset: 0, count: 7), 2 * pitch)
        XCTAssertEqual(ShotShelf.leading(age: 2, offset: 0, count: 7), 0)
        XCTAssertEqual(ShotShelf.leading(age: 3, offset: 0, count: 7), -pitch)
        XCTAssertEqual(ShotShelf.leading(age: 3, offset: pitch, count: 7), 0, "a rest on a slot brings it to the leading edge")
        XCTAssertEqual(ShotShelf.leading(age: -3, offset: 0, count: 7), 2 * pitch, "an age below zero is the newest's")
        XCTAssertEqual(ShotShelf.shift(age: 0, offset: 0, count: 7), 0, "the newest stays at the corner at rest")
        XCTAssertEqual(ShotShelf.shift(age: 1, offset: 0, count: 7), -pitch)
        XCTAssertEqual(ShotShelf.shift(age: 1, offset: .nan, count: 7), -pitch)
        XCTAssertEqual(ShotShelf.shift(age: Int.max, offset: 0, count: 7).isFinite, true)
    }

    // MARK: The pile

    func testTheSheetsOfAPileGoBackAndFadeForThreeAndTheRestLieUnderTheLastSeen() {
        let sheets = (0..<3).map { ShotShelf.sheet(age: $0) }
        XCTAssertEqual(sheets[0].offset, .zero)
        XCTAssertEqual(sheets[0].scale, 1)
        XCTAssertEqual(sheets[0].opacity, 1)
        for i in 1..<3 {
            XCTAssertLessThan(sheets[i].offset.width, sheets[i - 1].offset.width, "sheet \(i) is not up and left of the one over it")
            XCTAssertLessThan(sheets[i].offset.height, sheets[i - 1].offset.height)
            XCTAssertLessThan(sheets[i].scale, sheets[i - 1].scale)
            XCTAssertLessThan(sheets[i].opacity, sheets[i - 1].opacity)
            XCTAssertGreaterThan(sheets[i].opacity, 0, "a sheet of the three is seen")
        }
        for age in [3, 4, 19, 20, 1000, Int.max] {
            let sheet = ShotShelf.sheet(age: age)
            XCTAssertEqual(sheet.opacity, 0, "age \(age) is drawn")
            XCTAssertEqual(sheet.offset, sheets[2].offset, "age \(age) does not lie under the last seen")
            XCTAssertEqual(sheet.scale, sheets[2].scale)
        }
        for age in [-1, -1000, Int.min] { XCTAssertEqual(ShotShelf.sheet(age: age), sheets[0], "age \(age)") }
    }

    // MARK: The list

    func testEveryShotPushedOutIsReturnedOnceInOrderAndTheNewestTwentyStay() {
        for total in counts {
            var list: [Int] = []
            var out: [Int] = []
            for i in 0..<total {
                let pushed = ShotShelf.add(i, to: &list)
                XCTAssertLessThanOrEqual(pushed.count, 1, "one shot in pushes out at most one")
                XCTAssertLessThanOrEqual(list.count, 20)
                XCTAssertEqual(list.last, i, "the new shot is the newest")
                out += pushed
            }
            XCTAssertEqual(out, Array(0..<max(0, total - 20)), "\(total) in: the oldest went, each once, in order")
            XCTAssertEqual(list, Array(max(0, total - 20)..<total), "\(total) in: what stays is the newest twenty, oldest first")
        }
    }

    // MARK: The model holds the same bound and lets a pushed-out picture go

    private final class Watch { weak var image: CGImage? }

    /// A picture that is alive only in the list it is put on.
    private func addWatched(_ model: ShotToastModel, _ watches: inout [Watch], caption: String) throws {
        let watch = Watch()
        let id: ShotToastModel.Shot.ID
        do {
            let full = try ShotToastRig.picture(width: 64 + watches.count, height: 40)
            watch.image = full
            id = model.add(try ShotToastRig.picture(width: 32, height: 20), caption: caption, file: nil, full: full)
        }
        _ = id
        watches.append(watch)
    }

    func testThePushedOutShotsFullPictureIsReleasedWithItAndTheOthersStayHeld() throws {
        let model = ShotToastModel()
        var watches: [Watch] = []
        for i in 1...20 { try addWatched(model, &watches, caption: "c\(i)") }
        XCTAssertEqual(model.shots.count, 20)
        XCTAssertTrue(watches.allSatisfy { $0.image != nil }, "the control: a held picture is alive while it is on the list")

        try addWatched(model, &watches, caption: "c21")
        XCTAssertEqual(model.shots.count, 20)
        XCTAssertNil(watches[0].image, "the pushed-out shot's full picture is still held")
        XCTAssertTrue(watches[1...].allSatisfy { $0.image != nil }, "a shot that stayed lost its picture")

        for i in 22...25 { try addWatched(model, &watches, caption: "c\(i)") }
        XCTAssertEqual(model.shots.map(\.caption), (6...25).map { "c\($0)" })
        XCTAssertEqual(model.shots.map(\.id), Array(6...25))
        XCTAssertTrue(watches[0..<5].allSatisfy { $0.image == nil }, "five were pushed out; each lets its picture go")
        XCTAssertTrue(watches[5...].allSatisfy { $0.image != nil })
    }

    // MARK: What the counts say

    /// The three sentences that carry a count are Swift tables (`ScStr.copyAll`, `more`, `screenshots`) and a language
    /// that is missing from one falls back to English without a word: each language, each count of a list (and the
    /// counts none reaches), the number once and nothing of the template left.
    func testTheCountedSentencesCarryTheirNumberOnceInEveryLanguageAndNoneIsTheEnglishOne() {
        let numbers = [0, 1, 2, 3, 4, 5, 11, 20, 21, 22, 25, 101, 1000]
        let sentences: [(String, (Int) -> String)] = [("copyAll", ScStr.copyAll), ("more", ScStr.more), ("screenshots", ScStr.screenshots)]
        var english: [String: String] = [:]
        AppLanguage.only(.en) {
            for (name, sentence) in sentences { for n in numbers { english["\(name)\(n)"] = sentence(n) } }
        }
        AppLanguage.each { language in
            for (name, sentence) in sentences {
                for n in numbers {
                    let text = sentence(n)
                    XCTAssertEqual(text.components(separatedBy: String(n)).count, 2, "\(language) \(name)(\(n)) is \(text)")
                    XCTAssertFalse(text.contains("\\(") || text.contains("%") || text.contains("$"), "\(language) \(name)(\(n)): \(text)")
                    if language != .en {
                        XCTAssertNotEqual(text, english["\(name)\(n)"], "\(language) \(name)(\(n)) fell back to English")
                    }
                }
            }
        }
    }

    /// The German «N more» is «N mehr» (not «N weitere», which a narrow shot's width could not hold in one line), the
    /// German Share… holds one no-break space before its ellipsis so that it never breaks there, and the Spanish
    /// «Replaced» ends on the Trash, in the built tables the app reads and not only in the Swift table above.
    func testTheGermanSpellingsOfTheStageAreThoseOfTheBuiltTables() {
        AppLanguage.only(.de) {
            for n in [1, 9, 17] { XCTAssertEqual(ScStr.more(n), "\(n) mehr") }
            XCTAssertEqual(ScStr.share, "Teilen\u{00A0}…")
            XCTAssertEqual(ScStr.share.unicodeScalars.filter { $0.value == 0xA0 }.count, 1)
            XCTAssertFalse(ScStr.share.contains(" …"), "an ordinary space before the ellipsis may break the line there")
        }
        AppLanguage.only(.es) { XCTAssertEqual(ScStr.replaced, "Reemplazada. El original está en la papelera.") }
    }
}
