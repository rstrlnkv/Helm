import XCTest
import HelmContract
import HelmTestSupport
@testable import HelmApp

/// **`willDisable()` belongs to the person's switch and to nothing else.**
///
/// The two routes out of a live engine look alike and are not: `disable` is
/// somebody in Settings turning a module off, and `shutdown` is the process
/// ending — `applicationWillTerminate` calls it. An engine may ask its owner
/// something on the first and must not on the second, because on the second there
/// is nobody there: Keep Awake shipped an `osascript` administrator password
/// dialog raised from the quit path, for a `/etc/sudoers.d` rule it was trying to
/// take back out, and the consequence was that the rule then had to be left behind
/// on *every* route — including the one where somebody had just said they did not
/// want the feature.
///
/// **Read off the source, and the reason is worth stating.** Driving it would mean
/// `setEnabled` on the shared host, which writes the enabled flag into
/// `UserDefaults.standard` (the domain this house keeps tests out of) and builds
/// the *real* engines — and for this module the real port would go and look at
/// `/etc/sudoers.d`, on the machine running the suite. So the behaviour is pinned
/// where it can be: `ALidThatDidNotWorkSaysSoTests` drives the engine's own
/// `willDisable()` and `deactivate()` against a fake, and this pins the half that
/// decides which of them the host calls. Neither test sees what the other does.
@MainActor
final class OnlyThePersonsSwitchAsksTheEngineTests: XCTestCase {

    private func host() throws -> String {
        let source = try RepoSource.text(of: "Sources/HelmApp/ModuleHost.swift")
        XCTAssertGreaterThan(source.count, 2000, "the host was not read at all")
        return source
    }

    /// The body of one function, from its signature to the next one — so a call
    /// in `disable` cannot be counted as a call in `shutdown` and the other way
    /// round.
    private func body(of signature: String, in source: String) throws -> String {
        let after = try XCTUnwrap(source.range(of: signature),
                                  "`\(signature)` is not in ModuleHost any more")
        let rest = source[after.upperBound...]
        // The *nearest* next declaration, not the first spelling of one that
        // happens to be searched for: taking `func ` before `private func ` swept
        // three later methods into `shutdown`'s body and the check read clean on a
        // call that was not there.
        let end = [rest.range(of: "\n    func "), rest.range(of: "\n    private func ")]
            .compactMap { $0?.lowerBound }
            .min()
        return String(end.map { rest[..<$0] } ?? rest)
    }

    func testThePersonsSwitchTellsTheEngineBeforeTearingItDown() throws {
        let source = try host()
        let disable = try body(of: "private func disable(", in: source)
        XCTAssertTrue(disable.contains("willDisable()"),
                      "switching a module off in Settings no longer tells its engine, so the "
                      + "one moment there is somebody at the screen to answer a dialog goes by "
                      + "unused — and whatever the engine needed to ask about is left behind")
        let before = try XCTUnwrap(disable.range(of: "willDisable()"))
        let after = try XCTUnwrap(disable.range(of: "deactivate()"))
        XCTAssertLessThan(before.lowerBound, after.lowerBound,
                          "the engine was torn down before it was told, so anything it wanted "
                          + "to do with a person present ran against its own dropped state")
    }

    func testQuittingTellsItNothing() throws {
        let source = try host()
        let shutdown = try body(of: "func shutdown()", in: source)
        XCTAssertTrue(shutdown.contains("deactivate()"),
                      "precondition: shutdown still tears the engines down, or the absence "
                      + "below is an absence of everything")
        XCTAssertFalse(shutdown.contains("willDisable()"),
                       "quitting asks the engines whether they want anything from the person — "
                       + "which is an administrator password dialog belonging to an app that is "
                       + "already gone, the exact defect this split exists to prevent")
    }

    /// And the contract carries a default, so this is a question only the engines
    /// that care have to answer. Without it, `willDisable` would be nine new empty
    /// methods and the one that matters would be indistinguishable from them.
    func testEveryEngineAnswersItWithoutHavingToImplementIt() {
        final class Bare: ModuleEngine {
            let transport: EngineTransport = LocalTransport()
            func activate() {}
            func deactivate() {}
        }
        Bare().willDisable()
    }
}
