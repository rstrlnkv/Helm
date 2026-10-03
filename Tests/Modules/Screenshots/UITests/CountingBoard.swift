import Foundation
import XCTest
import Module_Screenshots_Engine

/// The clipboard of a scene that copies one picture at a time: it takes every single copy and counts it. **It was
/// taught no group, and says so:** a group written to it fails the test that wrote it, as a port that was never
/// shown a group would. It stood as thirteen identical local `Board` fakes (`private typealias Board =
/// CountingBoard` in each file that has one); a scene whose board must refuse, hold or cancel keeps its own, and the
/// pile's (`PileBoard`) counts groups, which this one does not.
final class CountingBoard: ShotPasteboard, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var copies: Int { lock.withLock { count } }
    func copy(png: Data) -> PasteOutcome { lock.withLock { count += 1 }; return .accepted }
    func copy(pngs: [Data]) -> PasteOutcome { XCTFail("this test's board was never taught a group"); return .refused }
}
