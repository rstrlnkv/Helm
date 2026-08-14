import XCTest
@testable import Module_Disk_Engine

/// The confirmation is the only place this module asks for consent, and it was
/// describing a different act.
///
/// Measured en and ru with one cache row in the basket: the dialog said «Move 1
/// item (120 MB) to the Trash?» and named `…/Library/Caches`, while the press
/// sent **four** paths — the folder's children — and left the folder itself
/// exactly where it was. Three things wrong at once: the count (1 against 4, and
/// against several hundred on a real `~/Library/Caches`), the path named, and a
/// refusal list that could come back naming files the question never mentioned.
///
/// So the question is asked of the plan. `DiskRemovalPlan.targets` is already
/// what gets sent; the count, the size and the names now come from the same
/// computation, which is what makes them unable to drift apart.
final class TheQuestionIsAboutWhatIsSentTests: XCTestCase {
    private let caches = "/Users/test/Library/Caches"

    private func cacheAdvice(_ children: [(String, Int)]) -> DiskAdvice {
        DiskAdvice(name: "Caches", path: caches, kind: .cache,
                   targets: children.map { DiskAdvice.Target(path: caches + "/" + $0.0,
                                                             bytes: $0.1) })
    }

    private func entry(_ path: String, bytes: Int) -> DiskEntry {
        DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: bytes,
                  isDirectory: true, noAccess: false, children: [])
    }

    /// The defect itself: one row, four removals.
    func testACacheRowIsAskedAboutAsItsContents() {
        let advice = cacheAdvice([("Firefox", 40), ("Adobe", 30), ("Yarn", 20), ("pip", 10)])
        let question = DiskRemovalPlan.question(basket: [entry(caches, bytes: 100)],
                                                advice: [advice])

        XCTAssertEqual(question.count, 4,
                       "the dialog asked about 1 item and the press sent four paths")
        XCTAssertEqual(question.paths, advice.targets.map(\.path))
        XCTAssertEqual(question.bytes, 100)
    }

    /// And the folder that stays behind is not named as something being removed.
    func testTheFolderThatStaysIsNotNamed() {
        let advice = cacheAdvice([("Firefox", 40)])
        let question = DiskRemovalPlan.question(basket: [entry(caches, bytes: 40)],
                                                advice: [advice])

        XCTAssertFalse(question.paths.contains(caches),
                       "the question named a folder that is still there afterwards")
        XCTAssertFalse(question.named().contains(caches + "\n"),
                       "and it is not in the list of names either: \(question.named())")
    }

    /// A row picked off the ring has no advice behind it and is its own target —
    /// the ordinary case, which must read exactly as it did.
    func testARowPickedOffTheRingIsItsOwnQuestion() {
        let picked = "/Users/test/Movies/raw.mov"
        let question = DiskRemovalPlan.question(basket: [entry(picked, bytes: 700)],
                                                advice: [cacheAdvice([("Firefox", 1)])])

        XCTAssertEqual(question.count, 1)
        XCTAssertEqual(question.paths, [picked])
        XCTAssertEqual(question.bytes, 700)
    }

    /// The question and the act are one computation, not two that agree today.
    func testTheQuestionNamesExactlyWhatWillBeSent() {
        let advice = cacheAdvice([("Firefox", 40), ("Adobe", 30)])
        let basket = [entry(caches, bytes: 70), entry("/Users/test/Movies/raw.mov", bytes: 700)]

        XCTAssertEqual(DiskRemovalPlan.question(basket: basket, advice: [advice]).paths,
                       DiskRemovalPlan.targets(basket: basket.map(\.path), advice: [advice]))
    }

    /// The names the dialog draws: the home prefix shortened the way AppKit does
    /// it, at most four, and an ellipsis when there are more. Paths rather than
    /// display names, because "Library" alone could equally be `/Library`.
    func testTheNamesAreAbbreviatedAndCappedAtFour() {
        let home = NSHomeDirectory()
        let advice = DiskAdvice(name: "Caches", path: home + "/Library/Caches", kind: .cache,
                                targets: (1...5).map {
                                    DiskAdvice.Target(path: home + "/Library/Caches/c\($0)",
                                                      bytes: 10)
                                })
        let question = DiskRemovalPlan.question(basket: [entry(home + "/Library/Caches",
                                                               bytes: 50)],
                                                advice: [advice])

        XCTAssertEqual(question.named(),
                       ["~/Library/Caches/c1", "~/Library/Caches/c2",
                        "~/Library/Caches/c3", "~/Library/Caches/c4"].joined(separator: "\n")
                       + "\n…")
    }

    /// Four is not "four and an ellipsis": the last line must not promise a fifth
    /// path that does not exist.
    func testExactlyFourNamesCarryNoEllipsis() {
        let advice = cacheAdvice([("a", 1), ("b", 1), ("c", 1), ("d", 1)])
        let question = DiskRemovalPlan.question(basket: [entry(caches, bytes: 4)],
                                                advice: [advice])

        XCTAssertFalse(question.named().hasSuffix("…"), question.named())
    }

    /// An empty basket asks about nothing — the state the button is dimmed in,
    /// and the arithmetic must not crash or invent a row in it.
    func testAnEmptyBasketIsAnEmptyQuestion() {
        let question = DiskRemovalPlan.question(basket: [], advice: [])

        XCTAssertEqual(question.count, 0)
        XCTAssertEqual(question.bytes, 0)
        XCTAssertEqual(question.named(), "")
    }
}
