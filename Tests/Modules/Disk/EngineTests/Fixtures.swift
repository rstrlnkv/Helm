import Foundation
@testable import Module_Disk_Engine

/// One tree node, named after the last component of its path unless told
/// otherwise. A folder by default; a test that needs a file says so.
func entry(_ path: String, _ bytes: Int = 1, _ children: [DiskEntry] = [],
           name: String? = nil, isDirectory: Bool = true,
           isFolded: Bool = false) -> DiskEntry {
    DiskEntry(name: name ?? (path as NSString).lastPathComponent, path: path, bytes: bytes,
              isDirectory: isDirectory, noAccess: false, children: children,
              isFolded: isFolded)
}

/// A capacity port that answers with the volumes it was given: none by
/// default, which is a port with nothing mounted and no answer for any path.
struct FakeCapacity: VolumeCapacityPort {
    var volumes: [VolumeReadout] = []
    func mounted() -> [VolumeReadout] { volumes }
    func readout(at path: String) -> VolumeReadout? { volumes.first { $0.path == path } }
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject { NSObject() }
}
