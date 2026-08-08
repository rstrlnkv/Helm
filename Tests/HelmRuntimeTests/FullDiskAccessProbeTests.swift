import Foundation
import XCTest
@testable import HelmRuntime

/// The Full Disk Access probe opens four files and reads a byte from each. Four
/// blocking `open`s are not something to do on the thread that draws — and not
/// on the cooperative pool either, which has one thread per core and no spare
/// one to give a syscall that decides to take its time.
///
/// The probe is passed in, so these can assert from inside it, where the thread
/// is the thing being judged. Each assertion fails for a different edit: marking
/// the function `@MainActor` lands it on `com.apple.main-thread`, and dropping
/// `offTheCooperativePool` for a plain `async` body lands it on the pool, whose
/// queue label ends in `.cooperative`.
///
/// **The answer is the control.** Assertions inside a closure that never runs
/// prove nothing at all, so every test here reads the verdict back: it can only
/// be the sentinel if the closure produced it.
///
/// `pthread_main_np` rather than `Thread.isMainThread`, which Swift 6 makes
/// unavailable from an asynchronous context.
final class FullDiskAccessProbeTests: XCTestCase {

    private static var queueLabel: String { String(cString: __dispatch_queue_get_label(nil)) }

    @MainActor func testTheProbeRunsNeitherOnTheThreadThatDrawsNorOnTheCooperativePool() async {
        let answer = await PermissionCheck.fullDiskAccess(probing: {
            let queue = Self.queueLabel
            XCTAssertFalse(pthread_main_np() != 0, "probed on the thread that draws: \(queue)")
            XCTAssertFalse(queue.hasSuffix(".cooperative"),
                           "a blocking read is parked on the cooperative pool: \(queue)")
            return .denied
        })

        XCTAssertEqual(answer, .denied, "the probe never ran, so nothing above was judged")
    }

    /// The hop must not invent a verdict — both of them, so this could not pass
    /// on a stub that always answers the same thing.
    func testTheAnswerIsWhateverTheProbeSaid() async {
        let denied = await PermissionCheck.fullDiskAccess(probing: { .denied })
        let granted = await PermissionCheck.fullDiskAccess(probing: { .granted })

        XCTAssertEqual(denied, .denied)
        XCTAssertEqual(granted, .granted)
    }

    /// And the default is the probe this app actually ships, so the async form
    /// cannot drift from the synchronous one every other caller uses.
    func testTheDefaultProbeAgreesWithTheSynchronousOne() async {
        let asked = await PermissionCheck.fullDiskAccess()

        XCTAssertEqual(asked, PermissionCheck.currentFullDiskAccess())
    }
}
