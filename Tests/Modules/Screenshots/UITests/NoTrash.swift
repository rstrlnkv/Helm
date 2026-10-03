import Foundation
import HelmRuntime
import Module_Screenshots_Engine

/// The Trash of a session whose test replaces nothing: it refuses every move, as the real one does on a volume that
/// is read-only, so a test that reached it by mistake would move nothing and say so.
struct NoTrash: ShotTrashing {
    func trash(_ url: URL) throws { throw CocoaError(.fileWriteVolumeReadOnly) }
}
