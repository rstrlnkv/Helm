import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The module's front door, folded with `??`.
///
/// `loadVolumes` answered `volumes = await client.request(…) ?? []`, so a read
/// nobody answered drew «Pick a volume, or scan any folder.» over no cards at
/// all — a Mac with no disks. **Every Mac has at least one browsable volume, so
/// "none" is never a true answer**; it is the Uninstaller's «a list nobody
/// answered is not a Mac with no applications on it», one module over.
///
/// The second consequence is quieter and worse. `isVolumeScan` is a membership
/// test against this list and `recomputeSegments` draws free space only for a
/// volume scan — so with the list missing, a scan of a whole volume draws its
/// tree as 100 % of the circle, which is the flat-disc failure that method's own
/// comment says it exists to prevent, arriving from the other side.
@MainActor
final class AnUnansweredVolumeListIsNotZeroTests: XCTestCase {

    private let big = VolumeInfo(name: "Big", path: "/Volumes/Big",
                                 totalBytes: 1000, freeBytes: 100)

    private var renders: [MountedRender] = []

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var logged: [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == DiskEngine.moduleID }
            .map(\.message)
    }

    private func model(_ transport: AnsweringTransport) -> DiskViewModel {
        DiskViewModel(vm: ModuleViewModel(transport: transport),
                      store: ScanStore(directory: scratchDirectory("disk-volumes")))
    }

    /// Both silences the wire has: a throw, and the empty `Data` a cached view
    /// model gets from the transport of an engine that has been switched off.
    private static let silences: [AnsweringTransport.Answer] = [.refuse, .nothing]

    // MARK: - The list that is on screen stays on screen

    func testALostReadKeepsTheVolumesAlreadyRead() async {
        for silence in Self.silences {
            let transport = AnsweringTransport(volumes: [big])
            let dvm = model(transport)
            await dvm.loadVolumes()
            XCTAssertEqual(dvm.volumes.map(\.path), ["/Volumes/Big"],
                           "precondition: the list was read once (\(silence))")

            transport.answers(silence)
            await dvm.loadVolumes()

            XCTAssertEqual(dvm.volumes.map(\.path), ["/Volumes/Big"], """
                a volume list nobody answered (\(silence)) emptied the picker, so the module's \
                front door told somebody their Mac has no disks — and `isVolumeScan` then \
                reports every scan as a folder scan, which takes the free-space wedge off the \
                ring.
                """)
            XCTAssertTrue(dvm.volumeListLost, "and nothing said why (\(silence))")
        }
    }

    /// A first read that was lost has no list to keep — and must still not read
    /// as a Mac with no disks.
    func testAFirstReadNobodyAnsweredSaysSoRatherThanShowingNone() async {
        let transport = AnsweringTransport(volumes: [big])
        transport.answers(.nothing)
        let dvm = model(transport)

        await dvm.loadVolumes()

        XCTAssertTrue(dvm.volumes.isEmpty, "precondition: there is nothing to draw")
        XCTAssertTrue(dvm.volumeListLost, """
            the start screen draws its invitation over an empty picker with no sentence about \
            why, which is indistinguishable from a Mac that really has no volumes — and there \
            is no such Mac.
            """)
    }

    /// The other half, without which the sentence would stand over every list for
    /// ever: an answered read puts it down.
    func testAnAnsweredReadPutsTheSilenceDown() async {
        let transport = AnsweringTransport(volumes: [big])
        let dvm = model(transport)
        transport.answers(.nothing)
        await dvm.loadVolumes()
        XCTAssertTrue(dvm.volumeListLost, "precondition: the first read was lost")

        transport.answers(.reply)
        await dvm.loadVolumes()

        XCTAssertFalse(dvm.volumeListLost, "the sentence outlived the silence it was about")
        XCTAssertEqual(dvm.volumes.map(\.path), ["/Volumes/Big"])
    }

    /// A Mac really can lose a volume — one gets ejected — so an answered *empty*
    /// list is drawn as it is, with no sentence about a silence that did not
    /// happen.
    func testAnAnsweredEmptyListIsNotASilence() async {
        let transport = AnsweringTransport(volumes: [])
        let dvm = model(transport)

        await dvm.loadVolumes()

        XCTAssertTrue(dvm.volumes.isEmpty)
        XCTAssertFalse(dvm.volumeListLost,
                       "an answer of «no volumes» was reported as no answer")
    }

    /// And it reaches the log — counts and outcomes only, nothing named.
    func testALostReadSaysSoInTheLog() async {
        let transport = AnsweringTransport(volumes: [big])
        transport.answers(.nothing)
        let dvm = model(transport)

        await dvm.loadVolumes()

        XCTAssertTrue(dvm.volumeListLost, "precondition: the read really was lost")
        XCTAssertTrue(logged.contains { $0.contains("volume list reply lost") }, """
            a volume list whose reply never came wrote nothing to the log: \(logged)
            """)
        XCTAssertFalse(logged.contains { $0.contains("Big") },
                       "and the line must not name a volume: \(logged)")
    }

    // MARK: - And the page says it

    /// The flag has to be drawn, and the two screens it tells apart are the ones
    /// a person cannot otherwise tell apart: an answered empty list, and no
    /// answer at all. Both draw no cards; only one of them has a reason to give.
    func testTheStartScreenSaysWhyItHasNoVolumes() async throws {
        for appearance in RenderedInk.bothAppearances {
            let answered = await mount(volumes: [], silent: false, appearance: appearance)
            let unanswered = await mount(volumes: [big], silent: true, appearance: appearance)

            // `try`, not `try?`: a reading that never settled is a broken
            // measurement, and folded to 0 it would arrive as «the two screens
            // are the same», which is this test's own verdict.
            let quiet = try XCTUnwrap(answered.render.settledInk(),
                                      "the answered screen never settled")
            let spoken = try XCTUnwrap(unanswered.render.settledInk(),
                                       "the unanswered screen never settled")

            XCTAssertTrue(answered.model.volumes.isEmpty, "precondition: neither draws a card")
            XCTAssertTrue(unanswered.model.volumes.isEmpty)
            XCTAssertTrue(unanswered.model.volumeListLost, "precondition: one of them is a silence")
            XCTAssertGreaterThan(spoken, quiet, """
                the start screen after a volume list nobody answered is the same drawing as \
                after a list that answered «none» (\(RenderedInk.label(of: appearance))): the \
                page claims this Mac has no disks and gives no reason.
                """)
        }
    }

    /// The real page, on a view model of its own — `DiskViewModel.shared(vm:)` is
    /// keyed to the `ModuleViewModel` it was built against, so two transports give
    /// two models and the two screens compared above are not one screen twice.
    private func mount(volumes: [VolumeInfo], silent: Bool,
                       appearance: NSAppearance.Name) async
        -> (model: DiskViewModel, render: MountedRender) {
        let transport = AnsweringTransport(volumes: volumes)
        if silent { transport.answers(.nothing) }
        let vm = ModuleViewModel(transport: transport)
        let dvm = DiskViewModel.shared(vm: vm)
        let render = mountedDiskPage(vm: vm, width: 744, height: 400, appearance: appearance)
        renders.append(render)
        await dvm.loadVolumes()
        render.settle(20)
        return (dvm, render)
    }
}
