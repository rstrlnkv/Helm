import Foundation
import XCTest
import Module_Uninstaller_Engine

// The same two placeholders the engine's tests share, and they are here rather
// than shared with that target because a test target cannot depend on another
// one. The duplication that is left is this file against
// `EngineTests/Fakes.swift`; the duplication that was here was five copies
// under two names across three files.

/// **Nothing here removes anything.** These tests are about what the view model
/// shows, and the engine behind it takes a `TrashPort` whether or not anybody
/// is going to remove something.
///
/// **And that claim has a runner now.** The engine's copy at least carried a
/// measurement saying an unconditional refusal changed nothing there; this one
/// carried the claim with nothing behind it at all — and this is the target
/// where it could hide, because a view model handed a `.success` it never
/// earned shows a removal that did not happen. A test that wants a refusal, or
/// wants to know what was asked for, wants `FakeTrash` in the engine's tests or
/// a double of its own here. The return is unreachable by the time it is read.
struct NoTrash: TrashPort {
    func trashItem(_ url: URL) -> TrashOutcome {
        XCTFail("no test here trashes — this test wants a trash double of its own")
        return .success
    }
}

/// **Nothing here is running**, and nothing is asked to quit.
///
/// `isRunning` answers `false` because that is a real answer to a question
/// these tests really ask. `quit` is not an answer: a view model test that
/// cares whether an app is up, and how long it takes to go, wants `FakeRunning`
/// with a `quitAfter` — zero would make the wait vacuous.
struct NoRunning: RunningAppsPort {
    func isRunning(bundleID: String) -> Bool { false }
    func quit(bundleID: String, force: Bool) {
        XCTFail("no test here quits anything — this test wants FakeRunning")
    }
}
