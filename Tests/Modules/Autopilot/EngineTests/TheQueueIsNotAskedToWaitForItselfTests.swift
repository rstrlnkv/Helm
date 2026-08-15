import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Autopilot_Engine

/// Nothing the engine dispatches onto `helm.rules` may then ask `helm.rules` to
/// wait for it.
///
/// **This is the gate for a defect whose runtime reproduction aborts the
/// process.** `dispatch_sync` targeting the queue the calling block is already
/// running on is not reentrancy and is not a hang that resolves: libdispatch
/// detects it and traps. Measured on 2026-08-15 by sending
/// `AutopilotCommand.undo` over the engine's own transport — `xctest` exited on
/// signal 5, and the triggered thread reads
///
/// ```
/// __DISPATCH_WAIT_FOR_QUEUE__
/// OS_dispatch_queue.sync<A>(execute:)
/// AutopilotEngine.undo(_:)
/// closure #1 in AutopilotEngine.answer(_:_:)
/// closure #1 in AutopilotEngine.putBack(_:_:)
/// closure #1 in closure #1 in AutopilotEngine.offQueue<A>(_:)
/// ```
///
/// In the app that is `HelmApp` terminating when somebody presses «Put back»,
/// which is the whole of the wave's undo feature. The reproduction lives in
/// `AReturnAskedForOverTheWireAnswersTests` and is gated, because a test that
/// aborts takes the other two hundred cases in this bundle with it and reports
/// them as nothing. So the *gate* is here, where it can fail without crashing.
///
/// **Why the source and not the behaviour**, in a suite that prefers behaviour:
/// the behaviour cannot be observed from inside the process it kills. This reads
/// the composition instead — `offQueue` dispatches, the command arm goes through
/// it, and the method the arm calls takes the queue synchronously — which is
/// three facts, each of them a line somebody can open.
///
/// It is not a rule about `queue.sync` in general. `undo(_:)` called from a
/// thread that does not own the queue is correct and is what
/// `AHistoryNotHelmsPutsNothingBackTests` does throughout; what cannot stand is
/// that same method being reachable from *inside* a block `offQueue` put on the
/// queue.
final class TheQueueIsNotAskedToWaitForItselfTests: XCTestCase {

    private static let engineFile = "Sources/Modules/Autopilot/Engine/AutopilotEngine.swift"

    private var source: String {
        get throws { SwiftSource.code(try RepoSource.text(of: Self.engineFile)) }
    }

    // MARK: - The three facts the scan is built on

    /// A scan that has stopped matching is a green test about nothing, so each
    /// name it depends on is asserted to exist before it is read.
    func testTheEngineStillHasTheMethodsThisRuleIsAbout() throws {
        let bodies = SwiftSource.functionBodies(in: try source).map(\.name)
        for name in ["offQueue", "answer", "putBack", "undo", "undoRun"] {
            XCTAssertTrue(bodies.contains(name), """
                AutopilotEngine has no \(name) any more, so this rule is reading a file that has \
                moved on — it found \(Set(bodies).sorted())
                """)
        }
    }

    /// `offQueue` is what puts work on the module's queue. If it stops doing
    /// that, the rule below is about nothing and should be re-read rather than
    /// left passing.
    func testOffQueuePutsWorkOnTheQueue() throws {
        let body = try XCTUnwrap(SwiftSource.body(of: "offQueue", in: try source))
        XCTAssertTrue(body.contains("queue.async"), """
            offQueue no longer dispatches onto queue — whatever it does now, the reasoning below \
            is stale
            """)
    }

    // MARK: - The rule

    /// The composition, spelled out: a command handled through `offQueue` must
    /// not call a method that takes the queue synchronously.
    func testNothingReachedThroughOffQueueTakesTheQueueSynchronously() throws {
        let source = try source
        let dispatched = Self.methodsCalledFromOffQueue(in: source)
        XCTAssertFalse(dispatched.isEmpty, """
            nothing in AutopilotEngine is dispatched through offQueue any more, so this rule \
            matches nothing — read it rather than leaving it green
            """)

        let waiting = dispatched.filter { name in
            SwiftSource.bodiesNamed(name, in: source).contains { $0.contains("queue.sync") }
        }
        XCTAssertEqual(waiting.sorted(), [], """
            these are called from inside a block offQueue put on helm.rules, and each opens with \
            queue.sync on that same serial queue. dispatch_sync targeting the queue the caller \
            already owns traps — the process aborts, and helm.rules carries the hourly sweep, the \
            FSEvents batch and clearHistory as well as this. Reproduced over the real transport \
            in AReturnAskedForOverTheWireAnswersTests (gated: it aborts the bundle).
            """)
    }

    // MARK: - Which methods those are

    /// The methods named inside a closure handed to `offQueue`, anywhere in the
    /// engine.
    ///
    /// Reads the *arguments* of each `offQueue` call rather than the enclosing
    /// function, because the closure is the argument — `offQueue { self.sweep(folder) }`
    /// — and because the interesting one is passed in from a command arm two
    /// calls up: `answer` builds `{ self.undo($0) }` and hands it to
    /// `putBack(_ command:_ work:)`, which is what calls `offQueue`. So the
    /// closures handed to *either* are what this collects.
    static func methodsCalledFromOffQueue(in source: String) -> Set<String> {
        let closures = SwiftSource.callSites(of: "offQueue", in: source).flatMap(\.arguments)
            + trailingClosures(of: "offQueue", in: source)
            + SwiftSource.callSites(of: "putBack", in: source).flatMap(\.arguments)
            + trailingClosures(of: "putBack", in: source)
        var out: Set<String> = []
        for closure in closures {
            // `self.name(` and `self.name {` alike: the second is a call with a
            // trailing closure and nothing else, which is the shape one of the
            // two plausible repairs produces — a rule blind to it would report
            // «this scan matches nothing» at the fixed tree instead of passing.
            for match in closure.ranges(ofPattern: #"self\.([A-Za-z_]\w*)\s*[({]"#) {
                out.insert(match)
            }
        }
        return out
    }

    /// A trailing closure is not inside the parentheses, so `callSites` never
    /// sees it — and every call in this file is written that way.
    ///
    /// Without this the scan reads `offQueue { self.sweep(folder) }` as a call
    /// with no arguments and reports nothing, which is precisely the silent-zero
    /// failure a guard must not have. `testNothingReachedThroughOffQueue…` asserts
    /// the set is non-empty for that reason.
    private static func trailingClosures(of callee: String, in source: String) -> [String] {
        let characters = Array(source)
        var out: [String] = []
        for call in SwiftSource.callSites(of: callee, in: source, wholeWords: false) {
            // Past the callee's own closing parenthesis, then whatever brace
            // follows on the same line.
            var index = call.characterOffset
            var depth = 0
            var opened = false
            while index < characters.count {
                if characters[index] == "(" { depth += 1; opened = true }
                if characters[index] == ")" {
                    depth -= 1
                    if opened, depth == 0 { index += 1; break }
                }
                index += 1
            }
            while index < characters.count, characters[index] == " " { index += 1 }
            guard index < characters.count, characters[index] == "{" else { continue }
            var braces = 0
            let start = index
            while index < characters.count {
                if characters[index] == "{" { braces += 1 }
                if characters[index] == "}" {
                    braces -= 1
                    if braces == 0 { out.append(String(characters[start...index])); break }
                }
                index += 1
            }
        }
        return out
    }

    // MARK: - And the reader can fail

    /// A fixture with the defect in it, so the rule is provably able to see it —
    /// and one without, so it is provably able not to.
    func testTheRuleRecognisesTheShapeAndOnlyThatShape() {
        let broken = SwiftSource.code("""
        private func offQueue<T>(_ work: @escaping () -> T) async -> T {
            await withCheckedContinuation { c in queue.async { c.resume(returning: work()) } }
        }
        func answer() async -> Data { await putBack(command) { self.undo($0) } }
        public func undo(_ id: String) -> UndoReport { queue.sync { putBack { $0.id == id } } }
        """)
        XCTAssertEqual(Self.methodsCalledFromOffQueue(in: broken), ["undo"],
                       "the reader did not see the closure handed to putBack")

        let sound = SwiftSource.code("""
        private func offQueue<T>(_ work: @escaping () -> T) async -> T {
            await withCheckedContinuation { c in queue.async { c.resume(returning: work()) } }
        }
        func answer() async -> Data { await putBack(command) { self.undoing($0) } }
        public func undo(_ id: String) -> UndoReport { queue.sync { undoing(id) } }
        private func undoing(_ id: String) -> UndoReport { UndoReport(lines: []) }
        """)
        let waiting = Self.methodsCalledFromOffQueue(in: sound).filter { name in
            SwiftSource.bodiesNamed(name, in: sound).contains { $0.contains("queue.sync") }
        }
        XCTAssertEqual(waiting, [], """
            the rule reported a shape that is correct: the public entry point takes the queue and \
            the wire calls the inner method, which is one of the two ways to fix this
            """)
    }
}

private extension String {
    /// Every capture group 1 of `pattern` in this string.
    func ranges(ofPattern pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return expression.matches(in: self, range: range).compactMap {
            Range($0.range(at: 1), in: self).map { String(self[$0]) }
        }
    }
}
