import Foundation
@testable import Module_Screenshots_Engine

/// The shutter of a session whose test does not listen for it: it plays nothing. A scene that counts the plays keeps
/// its own.
struct NoShutter: ShutterPlaying {
    func play() {}
}
