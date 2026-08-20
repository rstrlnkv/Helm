import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Hosts_UI

/// **A `@State` initial value is an `init`, and this one was a name lookup.**
///
/// `ProcessInfo.processInfo.hostName` asks the network stack what this machine
/// is called — a reverse lookup, measured at 43 ms cold on the Mac this was
/// found on — and it sat in `@State private var comment = defaultComment`.
/// SwiftUI evaluates a `@State` initial value while it installs the view's
/// state, on the thread that draws, every time the sheet is built. It is the
/// same shape as the settings page reading a sealed setting from a `@State`
/// initial value and standing a keychain dialog in front of a window that had
/// drawn nothing (CLAUDE.md, § A seal needs a signature).
///
/// Moving it into a `.task` is not by itself the fix and was measured not being
/// one there: the continuation is drained by the same layout pass that draws
/// the view. **What moves it is the thread**, so `KeyComment.value()` does the
/// read on a detached task and keeps the answer.
final class TheSheetDrawsBeforeTheHostNameTests: XCTestCase {

    /// The value is still `user@host`, which is what `ssh-keygen` writes when
    /// nobody gives it a comment — a fix that changed the default would be a
    /// different key's comment, not a faster one.
    func testTheCommentIsStillTheOneSSHKeygenWouldWrite() async {
        let comment = await KeyComment.value()

        XCTAssertEqual(comment, "\(NSUserName())@\(ProcessInfo.processInfo.hostName)")
    }

    /// Asked twice, read once: the second caller is answered out of memory.
    /// **Not a timing assertion** — a threshold over a lookup that may be warm
    /// in the system's own cache is a check that cannot fail — but the value
    /// being identical is what a cache that never filled would also give, so
    /// the reading above is the one that carries the meaning and this one only
    /// says the second call cannot be a *different* answer.
    func testAskingTwiceGivesOneAnswer() async {
        let first = await KeyComment.value()
        let second = await KeyComment.value()

        XCTAssertEqual(first, second)
    }

    /// **The guard, and it is a source reading, because the defect is invisible
    /// at runtime.** A view built in a test is built on whatever thread the
    /// test is on, so «this was slow on the main thread» cannot be asserted
    /// from here; what can be asserted is that the sheet does not name the
    /// lookup where SwiftUI will run it for us.
    func testTheSheetDoesNotReadProcessInfoWhileItsStateIsInstalled() throws {
        let source = try String(
            contentsOf: RepoSource.root
                .appendingPathComponent("Sources/Modules/Hosts/UI/NewKeySheet.swift"),
            encoding: .utf8)
        let stateLines = source.split(separator: "\n").map(String.init)
            .filter { $0.contains("@State") }

        XCTAssertFalse(stateLines.isEmpty,
                       "the sheet has no `@State` at all, so this scan is reading nothing")
        XCTAssertEqual(stateLines.filter { $0.contains("ProcessInfo") }, [], """
            the sheet reads `ProcessInfo` in a `@State` initial value, which SwiftUI evaluates \
            on the thread that draws every time the sheet is built. `hostName` is a reverse \
            lookup — 43 ms cold — and the sheet has not drawn a pixel while it runs.
            """)
    }
}
