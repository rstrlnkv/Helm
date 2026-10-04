import Foundation
import HelmRuntime
import Module_Screenshots_Engine

/// The reading of no file at all, for a fake disk that only counts its writes and keeps none: it hands this back with
/// each `.written`. Such a disk names `reading(of:)` and `claim(_:as:)` itself, as every fake of a port does: the
/// port has no default and neither has a fake of it.
enum NoFile {
    static let reading = ShotReading(identity: PathCanonical.FileIdentity(device: 0, inode: 0), size: 0,
                                     modifiedSeconds: 0, modifiedNanoseconds: 0, isRegularFile: true)
}
