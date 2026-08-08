import Foundation
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
/// Unconditional `.success` is the whole claim. A test that wants a refusal —
/// or wants to know what was asked for — wants `FakeTrash` in the engine's
/// tests, or a double of its own here.
struct NoTrash: TrashPort {
    func trashItem(_ url: URL) -> TrashOutcome { .success }
}

/// **Nothing here is running**, and nothing is asked to quit. A view model test
/// that cares whether an app is up, and how long it takes to go, wants
/// `FakeRunning` with a `quitAfter` — zero would make the wait vacuous.
struct NoRunning: RunningAppsPort {
    func isRunning(bundleID: String) -> Bool { false }
    func quit(bundleID: String, force: Bool) {}
}
