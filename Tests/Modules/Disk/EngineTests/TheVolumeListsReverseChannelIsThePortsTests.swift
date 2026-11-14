import AppKit
import Foundation
import XCTest
@testable import Module_Disk_Engine

/// The volume list's change channel lives on the capacity port. Two halves are
/// held here: the engine hands the port's own token out, and the system port's
/// token stops the observers when it is dropped.
final class TheVolumeListsReverseChannelIsThePortsTests: XCTestCase {

    private final class Recording: VolumeCapacityPort, @unchecked Sendable {
        private let lock = NSLock()
        private var asked = 0
        let token = NSObject()
        var timesAsked: Int { lock.withLock { asked } }
        func mounted() -> [VolumeReadout] { [] }
        func readout(at path: String) -> VolumeReadout? { nil }
        func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
            lock.withLock { asked += 1 }
            return token
        }
    }

    func testTheEngineAnswersFromThePort() {
        let port = Recording()
        let engine = DiskEngine(capacity: port, trashing: { _ in })
        let token = engine.watchMounts {}
        XCTAssertEqual(port.timesAsked, 1, "the engine did not ask the port")
        XCTAssertTrue(token === port.token, "the engine handed out something other than the port's token")
    }

    @MainActor
    func testTheSystemPortCallsOnAMountUntilTheTokenIsDropped() {
        let calls = Counter()
        var token: AnyObject? = SystemVolumeCapacity().observeChanges { calls.bump() }
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.didMountNotification, object: nil)
        settle()
        XCTAssertEqual(calls.value, 1, "control: a mount did not reach a held token")
        center.post(name: NSWorkspace.didUnmountNotification, object: nil)
        settle()
        XCTAssertEqual(calls.value, 2, "an unmount did not reach a held token")
        token = nil
        center.post(name: NSWorkspace.didMountNotification, object: nil)
        center.post(name: NSWorkspace.didUnmountNotification, object: nil)
        settle()
        XCTAssertEqual(calls.value, 2, "a dropped token still heard a disk")
        _ = token
    }

    /// The observers deliver on the main queue; let it run.
    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.withLock { n += 1 } }
        var value: Int { lock.withLock { n } }
    }
}
