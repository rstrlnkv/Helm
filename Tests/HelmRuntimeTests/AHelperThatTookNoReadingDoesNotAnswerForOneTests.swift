import AppKit
import HelmTestSupport
import HelmUI
import Observation
import QuartzCore
import SwiftUI
import XCTest

/// A helper that took no reading refuses, or fails at the line that called it, and does not hand back a
/// value that looks like one.
///
/// Readers under `Tests/Support` each have a state in which nothing was measured: a list that never
/// settles, a measurement whose hook is out of its slot, a frame no view has, a band without rows,
/// and a fade whose model value is already final. An answer handed back from that state reads as a fact
/// about the thing under test, and a check that leans on it cannot fail.
///
/// Each row that wants a refusal first asserts that the state happened: the list really grew or swung
/// between the scrolls, the body really made its requests while the hook was out or really put another
/// hook in the slot, the animation really ran. Beside each stand the rows for the right answer. A body
/// that puts another hook in the slot is refused, and the slot is back where `during` found it. A row
/// beside the measurement's states a limit: a body that takes the hook out and puts it back before the end
/// is not refused, and reads the requests the hook heard.
///
/// The rows for the opacities a frame presents give a layer a fade that really runs and take the layer out
/// of sight in one way each: hidden, under a hidden layer, without width, under a layer presenting opacity 0,
/// under an empty layer that clips, beyond the width of the view, outside the band of the photograph. Beside
/// each stands the same fade counted: in sight, under an empty layer that does not clip, inside the band. The
/// rows for `judge` assert the two numbers its failure gives, the turns that moved and those of them that had
/// the settled picture, against a count taken from the frames.
///
/// The failures a helper records are caught by overriding `record` between `startListening` and
/// `stopListening`, as `AGateNobodyArrivedAtFailsTests` does; the windows are built and never put on screen.
final class AHelperThatTookNoReadingDoesNotAnswerForOneTests: XCTestCase {

    private let heard = HeardFailures()

    override func record(_ issue: XCTIssue) {
        guard !heard.take(issue) else { return }
        super.record(issue)
    }

    // MARK: - StripedListEnd.read

    @MainActor
    func testAListStillGrowingAfterTheLastScrollIsNotReadAsSettled() {
        let list = GrowingList(rows: 100)
        defer { list.finish() }
        let initial = list.rows
        list.growEvery(0.001, by: 5, times: nil)

        var threw: Error?
        var answered = "nothing"
        do {
            answered = "\(String(describing: try StripedListEnd.read(list.table, host: list.host, settleTurns: 2)))"
        } catch {
            threw = error
        }

        // The subject first: the list was a different size at (nearly) every scroll, and it was still
        // growing after the last.
        XCTAssertGreaterThanOrEqual(Set(list.rowsAtEachScroll).count, 6,
                                    "the list did not grow between the scrolls (sizes at each: \(list.rowsAtEachScroll)), "
                                    + "so this row is not about a list that never settles")
        XCTAssertGreaterThan(list.rows, list.rowsAtEachScroll.last ?? .max, "the list stopped growing after the last scroll")
        XCTAssertGreaterThan(list.rows, initial + 40, "the list barely grew: \(initial) rows to \(list.rows)")

        XCTAssertNotNil(threw, "read answered \(answered) for a list that was still growing after the last scroll "
                        + "(sizes at each scroll: \(list.rowsAtEachScroll))")
        if let threw {
            XCTAssertTrue(threw is StripedListEnd.NeverSettled, "the refusal is \(type(of: threw)): \(threw)")
        }
    }

    @MainActor
    func testAListThatSwingsBetweenTwoLengthsOnAlternateScrollsIsNotReadAsSettled() {
        let list = SwingingList(low: 100, high: 140)
        defer { list.finish() }

        var threw: Error?
        var answered = "nothing"
        do {
            answered = "\(String(describing: try StripedListEnd.read(list.table, host: list.host, settleTurns: 2)))"
        } catch {
            threw = error
        }

        // The subject first: the list was a different length at every scroll than at the one before it, and
        // the same as at the one before that, so readings agree two apart and never in a row.
        let sizes = list.rowsAtEachScroll
        XCTAssertGreaterThanOrEqual(sizes.count, 8, "fewer than eight scrolls happened: \(sizes)")
        XCTAssertEqual(Set(sizes), [100, 140], "the list was not at both of its lengths: \(sizes)")
        XCTAssertTrue(zip(sizes, sizes.dropFirst()).allSatisfy { $0 != $1 },
                      "two scrolls in a row left the list at one length, so it did not swing: \(sizes)")

        XCTAssertNotNil(threw, "read answered with a reading, \(answered), for a list whose readings agreed two apart "
                        + "and never in a row (lengths at each scroll: \(sizes))")
        if let threw {
            XCTAssertTrue(threw is StripedListEnd.NeverSettled, "the refusal is \(type(of: threw)): \(threw)")
            let text = "\(threw)"
            XCTAssertTrue(text.contains("rows=100") && text.contains("rows=140"),
                          "the refusal does not name both lengths: \(text)")
        }
    }

    @MainActor
    func testTheRefusalNamesTheLastTwoReadings() {
        let list = GrowingList(rows: 100)
        defer { list.finish() }
        list.growEvery(0.001, by: 5, times: nil)

        var threw: Error?
        do {
            _ = try StripedListEnd.read(list.table, host: list.host, settleTurns: 2)
        } catch {
            threw = error
        }

        XCTAssertGreaterThanOrEqual(Set(list.rowsAtEachScroll).count, 6,
                                    "the list did not grow between the scrolls, so there is no refusal to read")
        guard let threw else {
            return XCTFail("read did not refuse a list that was still growing, so there is no text to read")
        }
        XCTAssertTrue(threw is StripedListEnd.NeverSettled, "the refusal is \(type(of: threw)): \(threw)")
        let text = "\(threw)"
        let named = text.components(separatedBy: "maxOffset=").count - 1
        XCTAssertGreaterThanOrEqual(named, 2,
                                    "the refusal names \(named) readings, and the last two are wanted; it says: \(text)")
    }

    @MainActor
    func testAListThatHoldsStillReadsTheSameTwice() throws {
        let list = GrowingList(rows: 100)
        defer { list.finish() }

        let reading = try XCTUnwrap(StripedListEnd.read(list.table, host: list.host, settleTurns: 2))

        XCTAssertEqual(reading.rows, 100)
        XCTAssertTrue(reading.scrollable, "a hundred rows of 20 points in a 200 point clip scroll: \(reading)")
        XCTAssertEqual(reading.lastRowMaxY, list.table.rect(ofRow: 99).maxY, accuracy: 0.5, "\(reading)")
        XCTAssertEqual(reading.documentHeight, list.table.frame.height, accuracy: 0.5, "\(reading)")
        let again = try XCTUnwrap(StripedListEnd.read(list.table, host: list.host, settleTurns: 2))
        XCTAssertEqual(again.description, reading.description, "a list that holds still reads the same twice")
    }

    @MainActor
    func testAListThatGrowsForAMomentAndThenRestsIsReadOnceItRests() throws {
        let list = GrowingList(rows: 100)
        defer { list.finish() }
        list.growEvery(0.001, by: 5, times: 4)

        let reading = try XCTUnwrap(StripedListEnd.read(list.table, host: list.host, settleTurns: 3))

        XCTAssertEqual(list.fired, 4, "the growth did not run its four steps, so the list never rested after one")
        XCTAssertEqual(reading.rows, 120, "the reading is of the list at rest: \(reading)")
        let always = GrowingList(rows: 120)
        defer { always.finish() }
        let steady = try XCTUnwrap(StripedListEnd.read(always.table, host: always.host, settleTurns: 3))
        XCTAssertEqual(reading.description, steady.description, "a list that grew and rested reads as one that was always this long")
    }

    // MARK: - ThreadAllocations.during

    @MainActor
    func testRequestsMadeWhileTheHookWasOutAreNotReadAsNothing() throws {
        let slot = try XCTUnwrap(mallocLoggerSlot())
        let original = address(of: slot)
        defer { restore(slot, to: original) }

        let run = outOfTheHook(slot, requesting: [1000, 1000, 1000, 1000, 1000])

        XCTAssertTrue(run.wasInstalled, "the hook was not in the slot when the body began, so nothing was being measured")
        XCTAssertTrue(run.leftOut, "the body did not take the hook out of the slot")
        XCTAssertEqual(run.made, 5, "the body did not make its five requests")
        XCTAssertNotEqual(run.lastAddress, 0, "the last request was not answered with memory")
        XCTAssertNotNil(run.thrown, "during returned \(String(describing: run.reading)) for a body that made five "
                        + "requests while the hook was out")
        if let error = run.thrown {
            XCTAssertEqual(error as? ThreadAllocations.Unmeasurable, .hookWentDeaf,
                           "the refusal is \(type(of: error)): \(error)")
        }
    }

    @MainActor
    func testBlockSizedRequestsMadeWhileTheHookWasOutAreNotReadAsNothing() throws {
        let slot = try XCTUnwrap(mallocLoggerSlot())
        let original = address(of: slot)
        defer { restore(slot, to: original) }

        let run = outOfTheHook(slot, requesting: [1_000_000, 1_000_000, 1_000_000])

        XCTAssertTrue(run.wasInstalled, "the hook was not in the slot when the body began")
        XCTAssertTrue(run.leftOut, "the body did not take the hook out of the slot")
        XCTAssertEqual(run.made, 3, "the body did not make its three requests")
        XCTAssertNotEqual(run.lastAddress, 0, "the last request was not answered with memory")
        XCTAssertNotNil(run.thrown, "during returned \(String(describing: run.reading)) for a body that made three "
                        + "requests of a megabyte while the hook was out")
        if let error = run.thrown {
            XCTAssertEqual(error as? ThreadAllocations.Unmeasurable, .hookWentDeaf,
                           "the refusal is \(type(of: error)): \(error)")
        }
    }

    /// The limit of the check, as a control: the hook is only asked at the end of the call, so a body that
    /// takes it out and puts it back before then is not refused and reads the requests the hook heard.
    @MainActor
    func testABodyThatTakesTheHookOutAndPutsItBackReadsFewerRequestsThanItMadeAndDoesNotThrow() throws {
        let slot = try XCTUnwrap(mallocLoggerSlot())
        let original = address(of: slot)
        defer { restore(slot, to: original) }

        var wasInstalled = false
        var leftOut = false
        var made = 0
        var thrown: Error?
        var reading: ThreadAllocations.Reading?
        do {
            let (_, taken) = try ThreadAllocations.during(countingBlocksOfAtLeast: 4096) { () -> Int in
                let heardOne = malloc(77)
                free(heardOne)
                made += 1
                let hook = slot.pointee
                wasInstalled = unsafeBitCast(hook, to: Int.self) != 0
                slot.pointee = nil
                leftOut = unsafeBitCast(slot.pointee, to: Int.self) == 0
                var i = 0
                while i < 4 {
                    let p = malloc(1000)
                    free(p)
                    made += 1
                    i += 1
                }
                slot.pointee = hook
                return made
            }
            reading = taken
        } catch {
            thrown = error
        }

        XCTAssertTrue(wasInstalled, "the hook was not in the slot when the body began")
        XCTAssertTrue(leftOut, "the body did not take the hook out of the slot")
        XCTAssertEqual(made, 5, "the body did not make its five requests")
        XCTAssertNil(thrown, "during refused a body that put the hook back before the end: \(String(describing: thrown))")
        let taken = try XCTUnwrap(reading, "during returned no reading")
        XCTAssertLessThan(taken.requests, made, "the reading counts requests the hook did not hear: \(taken)")
        XCTAssertEqual(taken.requests, 1, "the hook heard one request, the one made before it was taken out: \(taken)")
        XCTAssertEqual(taken.requested, 77)
    }

    @MainActor
    func testABodyThatAllocatesNothingReadsNoRequests() throws {
        let (_, reading) = try ThreadAllocations.during(countingBlocksOfAtLeast: 4096) { () -> Int in 0 }

        XCTAssertEqual(reading.requested, 0)
        XCTAssertEqual(reading.requests, 0)
        XCTAssertEqual(reading.largestRequest, 0)
        XCTAssertEqual(reading.requestedInBlocks, 0)
        XCTAssertEqual(reading.blocks, 0)
        XCTAssertEqual(reading.blockFloor, 4096)
    }

    @MainActor
    func testOneMallocOfSeventySevenReadsOneRequestOfSeventySeven() throws {
        let (_, reading) = try ThreadAllocations.during(countingBlocksOfAtLeast: 4096) { () -> Int in
            let p = malloc(77)
            free(p)
            return p == nil ? 1 : 0
        }

        XCTAssertEqual(reading.requests, 1, "one request, and nothing the measurement made itself")
        XCTAssertEqual(reading.requested, 77)
        XCTAssertEqual(reading.largestRequest, 77)
        XCTAssertEqual(reading.blocks, 0)
        XCTAssertEqual(reading.requestedInBlocks, 0)
    }

    @MainActor
    func testOneBlockSizedRequestReadsAsOneBlock() throws {
        let (_, reading) = try ThreadAllocations.during(countingBlocksOfAtLeast: 4096) { () -> Int in
            let p = malloc(8192)
            free(p)
            return p == nil ? 1 : 0
        }

        XCTAssertEqual(reading.requests, 1)
        XCTAssertEqual(reading.requested, 8192)
        XCTAssertEqual(reading.blocks, 1)
        XCTAssertEqual(reading.requestedInBlocks, 8192)
    }

    @MainActor
    func testTheSlotIsBackWhereItWasAndTheNextMeasurementWorksAfterOneThatLostItsHook() throws {
        let slot = try XCTUnwrap(mallocLoggerSlot())
        let original = address(of: slot)
        defer { restore(slot, to: original) }

        let first = outOfTheHook(slot, requesting: [1000, 1000])
        XCTAssertTrue(first.wasInstalled, "the hook was not in the slot when the first body began")
        XCTAssertTrue(first.leftOut, "the first body did not take the hook out of the slot")
        XCTAssertEqual(first.made, 2, "the first body did not make its requests")
        XCTAssertEqual(first.thrown as? ThreadAllocations.Unmeasurable, .hookWentDeaf,
                       "the first measurement was not refused: \(String(describing: first.thrown))")

        XCTAssertEqual(address(of: slot), original, "during left the slot where the body put it, not where it found it")
        let (_, second) = try ThreadAllocations.during(countingBlocksOfAtLeast: 4096) { () -> Int in
            let p = malloc(77)
            free(p)
            return p == nil ? 1 : 0
        }
        XCTAssertEqual(second.requests, 1, "the next measurement did not work after one that lost its hook")
        XCTAssertEqual(second.requested, 77)
        XCTAssertEqual(address(of: slot), original, "the second measurement left the slot changed")
    }

    @MainActor
    func testABodyThatPutsAnotherHookInTheSlotIsRefusedAndTheSlotIsBackWhereItWasFound() throws {
        let slot = try XCTUnwrap(mallocLoggerSlot())
        let original = address(of: slot)
        defer { restore(slot, to: original) }

        let other: Logger = { _, _, _, _, _, _ in }
        let otherAddress = unsafeBitCast(other, to: Int.self)
        var wasInstalled = false
        var putIn = false
        var thrown: Error?
        do {
            _ = try ThreadAllocations.during(countingBlocksOfAtLeast: 4096) { () -> Int in
                wasInstalled = address(of: slot) != original
                slot.pointee = other
                putIn = address(of: slot) == otherAddress
                let p = malloc(1000)
                free(p)
                return 0
            }
        } catch {
            thrown = error
        }

        XCTAssertTrue(wasInstalled, "the hook was not in the slot when the body began, so nothing was being measured")
        XCTAssertTrue(putIn, "the body did not put another hook in the slot")
        XCTAssertEqual(thrown as? ThreadAllocations.Unmeasurable, .hookWentDeaf,
                       "the refusal is \(String(describing: thrown))")
        XCTAssertEqual(address(of: slot), original,
                       "during left the other hook in the slot after refusing, not what it found there")
    }

    // MARK: - NSRect.superview(in:)

    @MainActor
    func testAFrameNoViewHasRecordsAFailureAtTheLineThatAsked() {
        let tree = Tree()
        let nobody = NSRect(x: 7, y: 7, width: 7, height: 7)
        XCTAssertFalse(tree.root.everyView.contains { $0.frame == nobody }, "a view has the frame, so this row is not about a frame nobody has")

        var askedAt: UInt = 0
        heard.startListening()
        askedAt = #line; _ = nobody.superview(in: tree.root)
        let failures = heard.stopListening()

        XCTAssertFalse(failures.isEmpty, "superview(in:) answered the root for a frame no view under it has, and said nothing")
        let here = URL(fileURLWithPath: #filePath).standardized.path
        XCTAssertTrue(failures.contains(HeardFailure(path: here, line: Int(askedAt))),
                      "the failures were \(failures.map { "\($0.path):\($0.line)" }), and one is wanted at this file, line \(askedAt)")
    }

    @MainActor
    func testAFrameOnlyTheRootHasRecordsAFailureAtTheLineThatAsked() {
        let tree = Tree()
        let onlyRoot = tree.root.frame
        let owners = tree.root.everyView.filter { $0.frame == onlyRoot }
        XCTAssertEqual(owners.count, 1, "more than one view has the root's frame, so this row is not about a frame only the root has")
        XCTAssertTrue(owners.first === tree.root, "the one view with the frame is not the root")

        var askedAt: UInt = 0
        heard.startListening()
        askedAt = #line; _ = onlyRoot.superview(in: tree.root)
        let failures = heard.stopListening()

        XCTAssertFalse(failures.isEmpty, "superview(in:) answered the root for the root's own frame, and said nothing: "
                       + "only the root has the frame, so the space it was read in is no view under the root")
        let here = URL(fileURLWithPath: #filePath).standardized.path
        XCTAssertTrue(failures.contains(HeardFailure(path: here, line: Int(askedAt))),
                      "the failures were \(failures.map { "\($0.path):\($0.line)" }), and one is wanted at this file, line \(askedAt)")
    }

    @MainActor
    func testAFrameNoViewHasAndAFrameOnlyTheRootHasStillAnswerTheRoot() {
        let tree = Tree()
        heard.startListening()
        let forNobody = NSRect(x: 7, y: 7, width: 7, height: 7).superview(in: tree.root)
        let forRoot = tree.root.frame.superview(in: tree.root)
        _ = heard.stopListening()

        XCTAssertTrue(forNobody === tree.root, "a frame no view has was not answered with the root")
        XCTAssertTrue(forRoot === tree.root, "the root's own frame was not answered with the root")
    }

    @MainActor
    func testACardAndItsRowWithOneFrameAnswerTheCardAndSayNothing() {
        let tree = Tree()
        XCTAssertEqual(tree.root.everyView.filter { $0.frame == tree.row.frame }.count, 2,
                       "the card and its row do not share a frame, so this row is not about the last of two matches")

        heard.startListening()
        let found = tree.row.frame.superview(in: tree.root)
        let failures = heard.stopListening()

        XCTAssertTrue(found === tree.card, "the last match is the row, and its superview is the card")
        XCTAssertEqual(failures, [], "a frame a view under the root has was refused")
    }

    @MainActor
    func testAFrameOneViewHasAnswersItsSuperviewAndSaysNothing() {
        let tree = Tree()
        heard.startListening()
        let found = tree.other.frame.superview(in: tree.root)
        let failures = heard.stopListening()

        XCTAssertTrue(found === tree.section, "the view's superview is the section")
        XCTAssertEqual(failures, [], "a frame a view under the root has was refused")
    }

    // MARK: - RenderedLines.read

    @MainActor
    func testABandWithNoRowsIsNotAnEmptyPage() {
        let view = InkedView()
        let drawn = RenderedLines.read(view, points: 25...45)
        XCTAssertEqual(drawn?.count, 1, "the view drew no line in the band 25 to 45, so there is nothing to mistake for empty")
        XCTAssertEqual(RenderedLines.read(view, points: 31...32)?.count, 1, "no ink in the band 31...32, beside which the empty band 32...32 sits")

        var answered: [String] = []
        for n in [0, 32, 99, 100] {
            let lines = RenderedLines.read(view, points: n...n)
            if lines != nil { answered.append("\(n)...\(n) answered \(String(describing: lines))") }
        }
        XCTAssertEqual(answered, [], "a band with no rows was answered, and the doc comment promises nil for a guess")
    }

    @MainActor
    func testABandThatWasReadAndHeldNothingAnswersAnEmptyList() {
        let view = InkedView()
        XCTAssertEqual(RenderedLines.read(view, points: 25...45)?.count, 1, "the view drew no line, so the empty band proves nothing")

        let lines = RenderedLines.read(view, points: 50...60)
        XCTAssertNotNil(lines, "a band of ten rows that held no ink was not read")
        XCTAssertEqual(lines?.count, 0)
    }

    @MainActor
    func testABandWithInkAnswersItsLine() throws {
        let view = InkedView()
        let lines = try XCTUnwrap(RenderedLines.read(view, points: 25...45))

        XCTAssertEqual(lines.count, 1)
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.top, 30, accuracy: 1)
        XCTAssertEqual(line.bottom, 40, accuracy: 1)
        XCTAssertEqual(line.left, 20, accuracy: 1)
        XCTAssertEqual(line.right, 80, accuracy: 1)
    }

    @MainActor
    func testABandRunningOffTheEndOfTheImageIsNil() {
        let view = InkedView()
        XCTAssertNil(RenderedLines.read(view, points: 50...200))
        XCTAssertNil(RenderedLines.read(view, points: -1...5))
    }

    // MARK: - FrameRecorder.photograph and judge

    @MainActor
    func testALayerFadeWhoseModelValueIsFinalIsNotReadAsACut() throws {
        let run = try layerFadeWithTheModelAlreadyFinal()

        let issues = judged(run, "layer opacity animated with the model already final")
        XCTAssertTrue(issues.sawTheCall, "judge raised nothing for a layer animation that ran for 0.4 s across "
                      + "\(run.shots.count) turns: it read a fade as a cut (issues: \(issues.all))")
    }

    @MainActor
    func testAnAnimatorFadeWhoseModelValueIsFinalIsNotReadAsACut() throws {
        let (root, child) = try layerBackedFixture()
        let layer = try XCTUnwrap(child.layer)
        let run = try fade(of: root, presenting: { layer.presentation()?.opacity }) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                context.allowsImplicitAnimation = true
                child.animator().alphaValue = 0
            }
        }
        try assertTheFadeRan(run, label: "animator fade")

        let issues = judged(run, "animator alphaValue over 0.4 s")
        XCTAssertTrue(issues.sawTheCall, "judge raised nothing for an animator fade that ran for 0.4 s across "
                      + "\(run.shots.count) turns: it read a fade as a cut (issues: \(issues.all))")
    }

    @MainActor
    func testASwiftUIFadeIsStillReadAsAFade() throws {
        let model = FadeSwitch()
        let host = NSHostingView(rootView: Fading(model: model).helmMeasuringBench())
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        let run = try fade(of: host, presenting: nil) {
            withAnimation(.easeInOut(duration: 0.4)) { model.on = true }
        }
        XCTAssertGreaterThanOrEqual(Set(run.shots.map(\.pixels)).count, 5, "the fade drew fewer than five distinct images: it did not run")
        XCTAssertNotEqual(run.before, run.shots.last?.pixels, "the drawing did not change")

        let issues = judged(run, "swiftui opacity withAnimation")
        XCTAssertTrue(issues.sawTheCall, "judge raised nothing for a SwiftUI fade: it read a fade as a cut (issues: \(issues.all))")
    }

    @MainActor
    func testASwiftUICrossFadeIsStillReadAsAFade() throws {
        let model = FadeSwitch()
        let host = NSHostingView(rootView: CrossFading(model: model).helmMeasuringBench())
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        let run = try fade(of: host, presenting: nil) {
            withAnimation(.easeInOut(duration: 0.4)) { model.on = true }
        }
        XCTAssertGreaterThanOrEqual(Set(run.shots.map(\.pixels)).count, 5, "the cross-fade drew fewer than five distinct images: it did not run")
        XCTAssertNotEqual(run.before, run.shots.last?.pixels, "the drawing did not change")

        let issues = judged(run, "swiftui transition cross-fade")
        XCTAssertTrue(issues.sawTheCall, "judge raised nothing for a SwiftUI cross-fade: it read a fade as a cut (issues: \(issues.all))")
    }

    @MainActor
    func testASwiftUIChangeWithNoAnimationIsStillACut() throws {
        let model = FadeSwitch()
        let host = NSHostingView(rootView: Fading(model: model).helmMeasuringBench())
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        let run = try fade(of: host, presenting: nil) { model.on = true }
        XCTAssertNotEqual(run.before, run.shots.last?.pixels, "the drawing did not change, so a cut proves nothing")

        let issues = judged(run, "swiftui opacity with no animation")
        XCTAssertEqual(issues.all, [], "judge raised an issue for a change with no animation: a cut was read as a fade")
    }

    @MainActor
    func testALayerChangeWithNoAnimationIsStillACut() throws {
        let (root, child) = try layerBackedFixture()
        let layer = try XCTUnwrap(child.layer)
        let run = try fade(of: root, presenting: { layer.presentation()?.opacity }) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 0
            CATransaction.commit()
        }
        XCTAssertNotEqual(run.before, run.shots.last?.pixels, "the drawing did not change, so a cut proves nothing")
        XCTAssertEqual(Set(run.presented).count, 1, "the presented opacity moved without an animation: \(run.presented)")

        let issues = judged(run, "layer opacity with no animation")
        XCTAssertEqual(issues.all, [], "judge raised an issue for a change with no animation: a cut was read as a fade")
    }

    // MARK: - FrameRecorder.Frame.presented

    @MainActor
    func testAHiddenLayerIsNotCountedAndTheSameLayerInSightIs() throws {
        let hidden = try faded(.hidden, label: "hidden layer")
        let seen = try faded(.inSight, label: "layer in sight")

        XCTAssertGreaterThanOrEqual(turnsCounted(seen.shots), 5, "the layer in sight was counted at too few turns: \(everyOpacityCounted(seen.shots))")
        XCTAssertEqual(everyOpacityCounted(hidden.shots), [], "a hidden layer was counted")
    }

    @MainActor
    func testALayerUnderAHiddenLayerIsNotCountedAndTheSameLayerInSightIs() throws {
        let underHidden = try faded(.underHidden, label: "layer under a hidden layer")
        let seen = try faded(.inSight, label: "layer in sight")

        XCTAssertGreaterThanOrEqual(turnsCounted(seen.shots), 5, "the layer in sight was counted at too few turns: \(everyOpacityCounted(seen.shots))")
        XCTAssertEqual(everyOpacityCounted(underHidden.shots), [], "a layer under a hidden layer was counted")
    }

    @MainActor
    func testALayerWithNoWidthIsNotCountedAndTheSameLayerWithWidthIs() throws {
        let narrow = try faded(.withoutWidth, label: "layer with no width")
        let seen = try faded(.inSight, label: "layer with width")

        XCTAssertGreaterThanOrEqual(turnsCounted(seen.shots), 5, "the layer with width was counted at too few turns: \(everyOpacityCounted(seen.shots))")
        XCTAssertEqual(everyOpacityCounted(narrow.shots), [], "a layer with no width was counted")
    }

    @MainActor
    func testALayerUnderALayerPresentingOpacityZeroIsNotCountedAndTheSameLayerInSightIs() throws {
        let underZero = try faded(.underOpacityZero, label: "layer under opacity zero")
        let seen = try faded(.inSight, label: "layer in sight")

        XCTAssertGreaterThanOrEqual(turnsCounted(seen.shots), 5, "the layer in sight was counted at too few turns: \(everyOpacityCounted(seen.shots))")
        XCTAssertEqual(everyOpacityCounted(underZero.shots), [], "a layer under a layer presenting opacity 0 was counted")
    }

    @MainActor
    func testALayerUnderAnEmptyParentIsCountedUnlessTheParentClips() throws {
        let clipped = try faded(.underEmptyParent(clipping: true), label: "layer under an empty parent that clips")
        let open = try faded(.underEmptyParent(clipping: false), label: "layer under an empty parent that does not clip")

        XCTAssertGreaterThanOrEqual(turnsCounted(open.shots), 5, "the layer under the parent that does not clip was counted at too few turns: \(everyOpacityCounted(open.shots))")
        XCTAssertEqual(everyOpacityCounted(clipped.shots), [], "a layer under an empty parent that clips was counted")
    }

    @MainActor
    func testALayerBeyondTheViewIsNotCountedAndTheSameLayerInSightIs() throws {
        let (view, fader, start) = try fadingLayer(.inSight)
        fader.frame = CGRect(x: 250, y: fader.frame.minY, width: 100, height: 30)
        let beyond = try fade(of: view, presenting: { fader.presentation()?.opacity }, change: start)
        try assertTheLayerFadedUnderOneDrawing(beyond, label: "layer beyond the view")
        let seen = try faded(.inSight, label: "layer in sight")

        XCTAssertGreaterThanOrEqual(turnsCounted(seen.shots), 5, "the layer in sight was counted at too few turns: \(everyOpacityCounted(seen.shots))")
        XCTAssertEqual(everyOpacityCounted(beyond.shots), [], "a layer beyond the view's 200 points of width was counted")
    }

    @MainActor
    func testAFadingLayerOutsideTheBandIsNotCountedAndInsideItIsInAnUnflippedView() throws {
        try assertTheBandCountsTheLayerInItsRowsOnly(flipped: false)
    }

    @MainActor
    func testAFadingLayerOutsideTheBandIsNotCountedAndInsideItIsInAFlippedView() throws {
        try assertTheBandCountsTheLayerInItsRowsOnly(flipped: true)
    }

    /// The layer sits in the top 30 rows of the view whichever way the layer space runs. Photographed in
    /// one run with three bands: rows 10 to 50, which hold it in part; rows 60 to 100, which do not; and the
    /// whole view.
    @MainActor
    private func assertTheBandCountsTheLayerInItsRowsOnly(flipped: Bool) throws {
        let (view, fader, start) = try fadingLayer(.inSight, flipped: flipped, duration: 1.0)
        let run = try fade(of: view, presenting: { fader.presentation()?.opacity },
                           bands: [10...50, 60...100, nil], change: start)
        try assertTheLayerFadedUnderOneDrawing(run, label: flipped ? "flipped view" : "unflipped view")
        let (inside, outside, whole) = (run.byBand[0], run.byBand[1], run.byBand[2])

        XCTAssertGreaterThanOrEqual(turnsCounted(whole), 5, "the layer was counted at too few turns in the whole view: \(everyOpacityCounted(whole))")
        XCTAssertGreaterThanOrEqual(turnsCounted(inside), 5, "the layer was counted at too few turns in the band 10...50, which holds its rows 10 to 30: \(everyOpacityCounted(inside))")
        XCTAssertEqual(everyOpacityCounted(outside), [], "the layer was counted in the band 60...100, which holds none of its rows")
    }

    // MARK: - FrameRecorder.judge

    @MainActor
    func testTheFailureForALayerFadeCountsTheTurnsThatDifferedInTheLayersAlone() throws {
        let run = try layerFadeWithTheModelAlreadyFinal()
        let expected = try turnsAfterTheGraceThatDifferedInTheLayersAlone(run)
        XCTAssertGreaterThanOrEqual(expected.layersAlone, 5, "fewer than five turns differed in the layers alone: \(expected)")

        let issues = judged(run, "layer fade whose picture is the settled one")
        let counted = try XCTUnwrap(numbersInTheFailure(issues.atTheCall), "no failure at the call says how many turns differed in the layers alone: \(issues.atTheCall)")

        XCTAssertEqual(counted.layersAlone, expected.layersAlone, "\(issues.atTheCall)")
        XCTAssertEqual(counted.moving, expected.moving, "\(issues.atTheCall)")
    }

    @MainActor
    func testTheFailureForASwiftUICrossFadeCountsOnlyTheTurnsThatDifferedInTheLayersAlone() throws {
        let model = FadeSwitch()
        let host = NSHostingView(rootView: CrossFading(model: model).helmMeasuringBench())
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        let run = try fade(of: host, presenting: nil) {
            withAnimation(.easeInOut(duration: 0.4)) { model.on = true }
        }
        let expected = try turnsAfterTheGraceThatDifferedInTheLayersAlone(run)
        XCTAssertGreaterThan(expected.moving, expected.layersAlone,
                             "every turn that differed had the settled picture, so this row does not tell the count of the layers alone from the count of all: \(expected)")

        let issues = judged(run, "swiftui cross-fade whose picture moves")
        let counted = try XCTUnwrap(numbersInTheFailure(issues.atTheCall), "no failure at the call says how many turns differed in the layers alone: \(issues.atTheCall)")

        XCTAssertEqual(counted.layersAlone, expected.layersAlone, "\(issues.atTheCall)")
        XCTAssertEqual(counted.moving, expected.moving, "\(issues.atTheCall)")
    }

    /// Counted here from the frames, apart from `judge`: the turns after the grace that are not the last
    /// frame's picture and layers, and of them those that have the last frame's picture.
    @MainActor
    private func turnsAfterTheGraceThatDifferedInTheLayersAlone(_ run: FadeRun) throws -> (moving: Int, layersAlone: Int) {
        let settled = try XCTUnwrap(run.shots.last)
        let moving = run.shots.dropFirst(FrameRecorder.grace).filter {
            $0.pixels != settled.pixels || $0.presented != settled.presented
        }
        return (moving.count, moving.filter { $0.pixels == settled.pixels }.count)
    }

    /// The two numbers the failure puts side by side, "X of the Y": X turns of the Y that moved had the
    /// settled picture.
    private func numbersInTheFailure(_ texts: [String]) -> (layersAlone: Int, moving: Int)? {
        for text in texts {
            guard let range = text.range(of: #"\d+ of the \d+"#, options: .regularExpression) else { continue }
            let numbers = text[range].components(separatedBy: " of the ").compactMap { Int($0) }
            if numbers.count == 2 { return (numbers[0], numbers[1]) }
        }
        return nil
    }

    // MARK: - Fixtures

    /// One fade of the layer of `fadingLayer`, with its subject asserted.
    @MainActor
    private func faded(_ sight: Sight, label: String) throws -> FadeRun {
        let (view, fader, start) = try fadingLayer(sight)
        let run = try fade(of: view, presenting: { fader.presentation()?.opacity }, change: start)
        try assertTheLayerFadedUnderOneDrawing(run, label: label)
        return run
    }

    /// What the layer tree presented at each turn, and what the recorder photographed.
    private struct FadeRun {
        let before: Data
        /// The frames of the first band asked for, the whole view when none was.
        let shots: [FrameRecorder.Frame]
        /// The frames of every band asked for, in the order asked.
        let byBand: [[FrameRecorder.Frame]]
        let presented: [Float]
    }

    /// The view is put in a window that is built and never put on screen, settled, photographed, changed, and
    /// photographed once per turn with the recorder itself, once for each of `bands` (nil is the whole view).
    /// `presenting` reads what the layer tree is presenting after each turn, independently of the recorder.
    @MainActor
    private func fade(of view: NSView, presenting: (() -> Float?)?, bands: [ClosedRange<Int>?] = [nil],
                      change: () -> Void) throws -> FadeRun {
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil }
        for _ in 0..<30 {
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        let before = try XCTUnwrap(RenderedInk.bytes(view))
        let began = Date()
        change()
        var byBand = [[FrameRecorder.Frame]](repeating: [], count: bands.count)
        var presented: [Float] = []
        for _ in 0..<45 {
            for (index, band) in bands.enumerated() {
                byBand[index] += try FrameRecorder.photograph(view, turns: 1, band: band, since: began)
            }
            if let presenting { presented.append(presenting() ?? -1) }
        }
        return FadeRun(before: before, shots: byBand[0], byBand: byBand, presented: presented)
    }

    // MARK: Layers a person could not see

    /// Where the faded layer sits and how it is kept out of sight.
    private enum Sight {
        case inSight
        case hidden
        case underHidden
        case withoutWidth
        case underOpacityZero
        case underEmptyParent(clipping: Bool)
    }

    /// A white view of 200 by 120 points with a faded layer in its top 30 rows, 50 to 150 across, kept out of
    /// sight as asked. The layer's model opacity is 0 and an opacity animation from 1 to 0 runs over
    /// `duration`, so its presented opacity moves through partial values while the picture, which draws model
    /// values, holds one drawing.
    @MainActor
    private func fadingLayer(_ sight: Sight, flipped: Bool = false, duration: CFTimeInterval = 0.4) throws -> (view: NSView, fader: CALayer, start: () -> Void) {
        let root: NSView = flipped ? FlippedView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
                                   : NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        root.wantsLayer = true
        let rootLayer = try XCTUnwrap(root.layer)
        rootLayer.backgroundColor = NSColor.white.cgColor
        XCTAssertEqual(rootLayer.isGeometryFlipped, flipped, "the layer space does not run the way the view's does")

        // The top 30 rows are y 0...30 where the layer space is flipped, and 90...120 where it is not.
        let top: CGFloat = flipped ? 0 : 90
        let fader = CALayer()
        fader.backgroundColor = NSColor.black.cgColor
        var width: CGFloat = 100
        if case .withoutWidth = sight { width = 0 }
        fader.frame = CGRect(x: 50, y: top, width: width, height: 30)
        switch sight {
        case .inSight, .withoutWidth:
            rootLayer.addSublayer(fader)
        case .hidden:
            fader.isHidden = true
            rootLayer.addSublayer(fader)
        case .underHidden:
            let parent = CALayer()
            parent.frame = rootLayer.bounds
            parent.isHidden = true
            parent.addSublayer(fader)
            rootLayer.addSublayer(parent)
        case .underOpacityZero:
            let parent = CALayer()
            parent.frame = rootLayer.bounds
            parent.opacity = 0
            parent.addSublayer(fader)
            rootLayer.addSublayer(parent)
        case .underEmptyParent(let clipping):
            let parent = CALayer()
            parent.frame = CGRect(x: 0, y: 0, width: 0, height: 0)
            parent.masksToBounds = clipping
            parent.addSublayer(fader)
            rootLayer.addSublayer(parent)
        }
        let start = {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fader.opacity = 0
            CATransaction.commit()
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.0
            animation.duration = duration
            fader.add(animation, forKey: "fade")
        }
        return (root, fader, start)
    }

    /// The subject of a layer row: the layer really presented partial values over the turns, the picture was
    /// one drawing at every turn, and every band asked for was photographed.
    @MainActor
    private func assertTheLayerFadedUnderOneDrawing(_ run: FadeRun, label: String) throws {
        try assertThePresentedOpacityWentFromOneToZero(run, label: label)
        for (index, frames) in run.byBand.enumerated() {
            XCTAssertEqual(frames.count, 45, "\(label): the frames of band \(index) were not recorded")
            XCTAssertEqual(Set(frames.map(\.pixels)).count, 1, "\(label): the picture of band \(index) changed during the fade")
        }
    }

    /// The subject both kinds of fade row share: 45 turns were photographed, and the layer tree presented an
    /// opacity above one half at the first, below a twentieth at the last, and between a tenth and nine
    /// tenths at five or more turns.
    @MainActor
    private func assertThePresentedOpacityWentFromOneToZero(_ run: FadeRun, label: String) throws {
        XCTAssertEqual(run.shots.count, 45, "\(label): the frames were not recorded")
        XCTAssertGreaterThan(try XCTUnwrap(run.presented.first), 0.5, "\(label): the animation had not begun at the first turn: \(run.presented)")
        XCTAssertLessThan(try XCTUnwrap(run.presented.last), 0.05, "\(label): the animation had not ended: \(run.presented)")
        XCTAssertGreaterThanOrEqual(run.presented.filter { $0 > 0.1 && $0 < 0.9 }.count, 5,
                                    "\(label): the presented opacity did not pass through the middle: \(run.presented)")
    }

    /// How many turns the recorder counted a layer in the middle of its fade.
    private func turnsCounted(_ frames: [FrameRecorder.Frame]) -> Int {
        frames.filter { $0.presented.contains { $0 > 0.1 && $0 < 0.9 } }.count
    }

    private func everyOpacityCounted(_ frames: [FrameRecorder.Frame]) -> [[Float]] {
        frames.map(\.presented).filter { !$0.isEmpty }
    }

    /// The subject of the two AppKit fades: the animation ran, the layer was presenting values between the
    /// two ends, and the drawing before differs from the settled one.
    @MainActor
    private func assertTheFadeRan(_ run: FadeRun, label: String) throws {
        try assertThePresentedOpacityWentFromOneToZero(run, label: label)
        XCTAssertNotEqual(run.before, run.shots.last?.pixels, "\(label): the drawing before the change is the settled one, so this case proves nothing")
    }

    /// What `judge` recorded for these frames, and whether any of it landed on the line that called it.
    private struct Judged {
        let all: [String]
        let sawTheCall: Bool
        /// The texts of the failures that landed on the line that called `judge`.
        let atTheCall: [String]
    }

    @MainActor
    private func judged(_ run: FadeRun, _ label: String) -> Judged {
        var askedAt: UInt = 0
        heard.startListening()
        do {
            askedAt = #line; try FrameRecorder.judge(run.shots, before: run.before, label)
        } catch {
            XCTFail("judge threw: \(error)")
        }
        let failures = heard.stopListening()
        let here = URL(fileURLWithPath: #filePath).standardized.path
        return Judged(all: failures.map { "\($0.path):\($0.line) \($0.text)" },
                      sawTheCall: failures.contains { $0.path == here && $0.line == Int(askedAt) },
                      atTheCall: failures.filter { $0.path == here && $0.line == Int(askedAt) }.map(\.text))
    }

    /// A black layer-backed view on white whose opacity is set to 0 in the model and animated from 1 to 0
    /// over 0.4 s, photographed per turn, with the subject asserted.
    @MainActor
    private func layerFadeWithTheModelAlreadyFinal() throws -> FadeRun {
        let (root, child) = try layerBackedFixture()
        let layer = try XCTUnwrap(child.layer)
        let run = try fade(of: root, presenting: { layer.presentation()?.opacity }) {
            layer.opacity = 0
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.0
            animation.duration = 0.4
            layer.add(animation, forKey: "fade")
        }
        try assertTheFadeRan(run, label: "layer fade")
        return run
    }

    @MainActor
    private func layerBackedFixture() throws -> (NSView, NSView) {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor
        let child = NSView(frame: NSRect(x: 50, y: 30, width: 100, height: 60))
        child.wantsLayer = true
        child.layer?.backgroundColor = NSColor.black.cgColor
        root.addSubview(child)
        return (root, child)
    }

    private typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

    /// libmalloc's `malloc_logger` slot, found the way the helper finds it.
    private func mallocLoggerSlot() -> UnsafeMutablePointer<Logger?>? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else { return nil }
        return symbol.assumingMemoryBound(to: Logger?.self)
    }

    private func address(of slot: UnsafeMutablePointer<Logger?>) -> Int {
        unsafeBitCast(slot.pointee, to: Int.self)
    }

    private func restore(_ slot: UnsafeMutablePointer<Logger?>, to address: Int) {
        slot.pointee = unsafeBitCast(address, to: Logger?.self)
    }

    private struct OutOfTheHook {
        var wasInstalled = false
        var leftOut = false
        var made = 0
        var lastAddress = 0
        var thrown: Error?
        var reading: ThreadAllocations.Reading?
    }

    /// A body that takes the hook out of the slot itself and then makes one request per size.
    private func outOfTheHook(_ slot: UnsafeMutablePointer<Logger?>, requesting sizes: [Int]) -> OutOfTheHook {
        var run = OutOfTheHook()
        do {
            let (_, reading) = try ThreadAllocations.during(countingBlocksOfAtLeast: 4096) { () -> Int in
                run.wasInstalled = unsafeBitCast(slot.pointee, to: Int.self) != 0
                slot.pointee = nil
                run.leftOut = unsafeBitCast(slot.pointee, to: Int.self) == 0
                var i = 0
                while i < sizes.count {
                    let p = malloc(sizes[i])
                    run.lastAddress = Int(bitPattern: p)
                    free(p)
                    run.made += 1
                    i += 1
                }
                return run.made
            }
            run.reading = reading
        } catch {
            run.thrown = error
        }
        return run
    }
}

// MARK: - Fixtures outside the class

/// A table in a scroll view that can go on growing while the run loop turns.
@MainActor
private final class GrowingList: NSObject, NSTableViewDataSource {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    private(set) var rows: Int
    private(set) var fired = 0
    /// How many rows the list had each time the clip view's bounds moved, which is each scroll.
    private(set) var rowsAtEachScroll: [Int] = []
    private var timer: Timer?
    private var watcher: NSObjectProtocol?

    init(rows: Int) {
        self.rows = rows
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("only"))
        column.width = 300
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 20
        table.dataSource = self
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        host.addSubview(scroll)
        table.reloadData()
        host.layoutSubtreeIfNeeded()
        scroll.contentView.postsBoundsChangedNotifications = true
        watcher = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rowsAtEachScroll.append(self.rows)
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows }

    /// `times` steps of `count` rows each, one every `interval` seconds, or for as long as the run loop turns.
    func growEvery(_ interval: TimeInterval, by count: Int, times: Int?) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rows += count
                self.fired += 1
                self.table.noteNumberOfRowsChanged()
                if let times, self.fired >= times { self.timer?.invalidate() }
            }
        }
    }

    func finish() {
        timer?.invalidate()
        if let watcher { NotificationCenter.default.removeObserver(watcher) }
    }
}

/// A clip view that tells what it is about to be scrolled.
private final class ScrollTellingClip: NSClipView {
    var beforeScroll: (() -> Void)?

    override func scroll(to newOrigin: NSPoint) {
        beforeScroll?()
        super.scroll(to: newOrigin)
    }
}

/// A table in a scroll view that is `low` rows long after every second scroll and `high` rows long after the
/// others, starting from `low`.
@MainActor
private final class SwingingList: NSObject, NSTableViewDataSource {
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    private let clip = ScrollTellingClip()
    private let low: Int
    private let high: Int
    private var rows: Int
    private var changing = false
    /// How many rows the list had once each scroll had changed it.
    private(set) var rowsAtEachScroll: [Int] = []

    init(low: Int, high: Int) {
        self.low = low
        self.high = high
        self.rows = low
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("only"))
        column.width = 300
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 20
        table.dataSource = self
        scroll.contentView = clip
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        host.addSubview(scroll)
        table.reloadData()
        host.layoutSubtreeIfNeeded()
        clip.beforeScroll = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.changing else { return }
                self.changing = true
                defer { self.changing = false }
                self.rows = self.rows == self.low ? self.high : self.low
                self.table.noteNumberOfRowsChanged()
                self.rowsAtEachScroll.append(self.rows)
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows }

    func finish() {
        clip.beforeScroll = nil
    }
}

/// A root, a section in it, a card in the section, a row in the card with the card's own frame, and a view
/// beside the card.
@MainActor
private final class Tree {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let section = NSView(frame: NSRect(x: 10, y: 10, width: 380, height: 200))
    let card = NSView(frame: NSRect(x: 20, y: 20, width: 300, height: 100))
    let row = NSView(frame: NSRect(x: 20, y: 20, width: 300, height: 100))
    let other = NSView(frame: NSRect(x: 20, y: 150, width: 100, height: 40))

    init() {
        root.addSubview(section)
        section.addSubview(card)
        card.addSubview(row)
        section.addSubview(other)
    }
}

/// White, with one black bar from 30 to 40 points down, 20 to 80 across.
private final class InkedView: NSView {
    override var isFlipped: Bool { true }

    init() { super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 100)) }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSColor.black.setFill()
        NSRect(x: 20, y: 30, width: 60, height: 10).fill()
    }
}

/// A plain view whose coordinates run from the top.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@Observable
private final class FadeSwitch {
    var on = false
}

private struct Fading: View {
    let model: FadeSwitch
    var body: some View {
        ZStack {
            Color.white
            Color.black.frame(width: 100, height: 60).opacity(model.on ? 0 : 1)
        }.frame(width: 200, height: 120)
    }
}

private struct CrossFading: View {
    let model: FadeSwitch
    var body: some View {
        ZStack {
            Color.white
            if model.on {
                Color.black.frame(width: 100, height: 60).transition(.opacity)
            } else {
                Color.gray.frame(width: 100, height: 60).transition(.opacity)
            }
        }.frame(width: 200, height: 120)
    }
}

/// A failure heard while a case listened: where it was recorded and what it said. Equal when the place is.
struct HeardFailure: Equatable {
    let path: String
    let line: Int
    var text = ""

    static func == (a: HeardFailure, b: HeardFailure) -> Bool { a.path == b.path && a.line == b.line }
}

/// Written from whatever thread records the failure and read from the test's own, so it holds a lock.
final class HeardFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var listening = false
    private var kept: [HeardFailure] = []

    func startListening() {
        lock.lock()
        defer { lock.unlock() }
        kept = []
        listening = true
    }

    /// True while listening, which is the case's cue not to pass the issue on.
    func take(_ issue: XCTIssue) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard listening else { return false }
        if let location = issue.sourceCodeContext.location {
            kept.append(HeardFailure(path: location.fileURL.standardized.path, line: location.lineNumber,
                                     text: issue.compactDescription))
        } else {
            kept.append(HeardFailure(path: "(no location)", line: 0, text: issue.compactDescription))
        }
        return true
    }

    func stopListening() -> [HeardFailure] {
        lock.lock()
        defer { lock.unlock() }
        listening = false
        return kept
    }
}
