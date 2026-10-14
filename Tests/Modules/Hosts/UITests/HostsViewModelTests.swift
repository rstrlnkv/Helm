import XCTest
import Combine
import HelmContract
import HelmTestSupport
import HelmRuntime
import HelmUI
import Module_Hosts_Engine
@testable import Module_Hosts_UI

@MainActor
final class HostsViewModelTests: XCTestCase {

    /// What `WireSSHConfig` reads, which is what the first snapshot carries.
    private let config = "Host a\n    HostName a.example\n"

    /// The wire, and the model built on it. The engine is held for the test's
    /// life: it wires the transport's handler with `[weak self]`.
    private struct Wire {
        let hosted: HostsUIWire
        let model: HostsViewModel
        var transport: LocalTransport { hosted.transport }
    }

    private func wire() -> Wire {
        let hosted = HostsUIWire.make()
        let model = HostsViewModel(vm: hosted.vm)
        addTeardownBlock { await MainActor.run { model.stop() } }
        return Wire(hosted: hosted, model: model)
    }

    /// A model with its first load already over, so a test that counts
    /// something is not racing the load that fills it. **Hold and await
    /// whatever moves before counting what it moves.**
    private func loaded() async -> Wire {
        let wired = wire()
        await wired.model.firstLoad?.value
        await waitUntil("the first snapshot arrived") { wired.model.sshOnDisk == config }
        return wired
    }

    // MARK: - The wire

    /// The load fired from `init` is **held**, and it fills the page.
    ///
    /// A load fired and forgotten leaves every later load racing it on one wire
    /// — 8 failures in 200 constructions in Autopilot before its model kept the
    /// task.
    func testTheFirstLoadIsHeldAndFillsTheModel() async {
        let wired = wire()
        XCTAssertNotNil(wired.model.firstLoad, "the first load was fired and forgotten")
        await wired.model.firstLoad?.value
        await waitUntil("the snapshot arrived") { wired.model.sshOnDisk == config }

        XCTAssertEqual(wired.model.sshText, config)
        XCTAssertEqual(wired.model.sshOnDisk, config)
        XCTAssertTrue(wired.model.sshReadable)
    }

    // MARK: - Teardown

    /// `stop()` ends the subscription, measured on the transport's own count
    /// rather than on a flag the model keeps about itself.
    ///
    /// `Task { [weak self] … }` captures weakly only at the top: once the
    /// `for await` starts it holds the object for as long as it runs, and this
    /// stream has no `.finish()`, so it runs for the life of the app. The task
    /// has to be cancelled from outside.
    func testStopEndsTheSubscription() async {
        let wired = await loaded()
        XCTAssertEqual(wired.transport.subscriberCount, 1, "the model never subscribed")

        wired.model.stop()
        await waitUntil("the subscription ended") { wired.transport.subscriberCount == 0 }
        XCTAssertEqual(wired.transport.subscriberCount, 0)
    }

}
