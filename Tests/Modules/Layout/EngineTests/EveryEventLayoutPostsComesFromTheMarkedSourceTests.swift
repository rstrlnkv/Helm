import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// Every event this module builds takes its source from `helmEventSource()`, the one
/// place that sets the event marker `CGKeyTap.deliver` drops.
///
/// Defect class kept: the engine reading its own output back as typing (data
/// overwritten; REQUIRED in ARCHITECTURE.md § What proves what). The marker is
/// guarded where events are *built* by `HelmsOwnKeystrokesAreNotReadAsTypingTests`;
/// `SystemCommandKeys.press` (the ⌘C and ⌘V of the clipboard route) builds its own pair
/// and no test constructs it, so a bare `CGEventSource(stateID:)` there would send
/// the echo to the tap unmarked, read as a chord, and end the undo chance.
///
/// A source-reading check, because posting a key from a test types into the window
/// in front. Its subject is the count of `CGEventSource(` in code (comments are
/// stripped): exactly one, in `helmEventSource()`.
final class EveryEventLayoutPostsComesFromTheMarkedSourceTests: XCTestCase {

    func testTheOnlyEventSourceIsTheMarkedOne() throws {
        let path = "Sources/Modules/Layout/Engine/SystemPorts.swift"
        let source = SwiftSource.code(try RepoSource.text(of: path))
        let helper = SwiftSource.bodiesNamed("helmEventSource", in: source)
        XCTAssertEqual(helper.count, 1,
                       "\(path) no longer holds exactly one helmEventSource() — this check has "
                       + "lost its subject and is guarding nothing")
        XCTAssertEqual(try XCTUnwrap(helper.first).components(separatedBy: "CGEventSource(").count - 1, 1,
                       "helmEventSource() no longer builds the one source")
        let all = source.components(separatedBy: "CGEventSource(").count - 1
        XCTAssertEqual(all, 1, """
            \(path) calls CGEventSource( \(all) times in code. Any call outside \
            helmEventSource() makes events without the marker, and the tap reads Helm's own \
            keystrokes as the person's.
            """)
    }
}
