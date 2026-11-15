import Foundation
@testable import Module_Screenshots_Engine

/// The shutter of a session whose test does not listen for it: it plays nothing. A scene that counts the plays uses
/// `CountingShutter`.
struct NoShutter: ShutterPlaying {
    func play() {}
}

/// The shutter of a scene that counts the plays.
final class CountingShutter: ShutterPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var plays: Int { lock.withLock { count } }
    func play() { lock.withLock { count += 1 } }
}
