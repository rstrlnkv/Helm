import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import Vision
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **The page, drawn, and read back: a titled card over nothing is not on it.**
///
/// `ANamelessHistoryCardIsNotDrawnTests` holds `drawsHistory` on the model, and
/// the model is only half of the change: the page has to *ask* it, and nothing
/// but a rendering can see whether it does. So the whole page is mounted over a
/// wire in a named appearance (Aqua) and a named language (English), and the
/// words a person would read are recovered with Vision's text recogniser — an
/// `NSHostingView`'s accessibility tree is empty in a test process, and a
/// SwiftUI `Text` leaves no view of its own to find.
///
/// **Two things about the bench, both measured.** The window never orders in,
/// and there SwiftUI's cross-fade from the empty screen to the folder list
/// crawls: after 240 turns of the run loop the list was still a pale overlay on
/// the empty state, which reads as neither. So the page is mounted under a
/// transaction that disables animations — what is drawn is the settled page,
/// which is the claim here. And a suite run has no preset folders
/// (`SystemPresetFolders` answers nil under `TestProcess`), so the block of
/// starting rules is not on these renders; the subject every absence is asserted
/// after is the folder's own «No rules yet», which sits in the same list.
///
/// The second half is the order in `load()`: the engineer hid the block when a
/// reading brings rules rather than re-deciding it before the status arrives,
/// and the reason given — a refused set answers `[]` for its folders, so a
/// decision taken on the stale status would *offer* the block for a frame — is
/// the thing tested there, with the status held at the wire so the frame
/// between the two answers is read on purpose rather than by the sampler's luck.
@MainActor
final class TheHistoryCardOnThePageTests: XCTestCase {

    private let home = NSHomeDirectory()
    private let cardTitle = "Last 30 days"
    private let noRules = "No rules yet"

    // MARK: - The page

    private func mount(_ wire: AutopilotWire) -> MountedRender {
        let page = AutopilotSettingsPage(vm: ModuleViewModel(transport: wire))
            .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted))
            .transaction { $0.disablesAnimations = true; $0.animation = nil }
        return MountedRender(page, width: 846, height: 900, appearance: .aqua)
    }

    /// Every line of text Vision reads in what the page draws right now.
    private func lines(_ render: MountedRender) -> [String] {
        let host = render.host
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return [] }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let image = rep.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private func reads(_ lines: [String], _ text: String) -> Bool {
        lines.contains { $0.contains(text) }
    }

    /// Pumps until `condition` holds of what is read, and hands back the last
    /// reading either way — bounded by turns, so a page that never gets there
    /// fails on the assertion that follows rather than hanging.
    private func settle(_ render: MountedRender, until condition: ([String]) -> Bool) -> [String] {
        var read: [String] = []
        for _ in 0..<30 {
            render.settle(10)
            read = lines(render)
            if condition(read) { break }
        }
        return read
    }

    private func record() -> ActionRecord {
        ActionRecord(at: Date(), rule: "Sort", file: "a.pdf", kind: .trashed,
                     detail: "", path: home + "/Music/a.pdf", run: "pass-1")
    }

    private var folderWithNoRules: WatchedFolder { WatchedFolder(path: home + "/Music") }

    /// A watched folder, no rule in it, nothing done: the folder says «No rules
    /// yet», and no card titled «Last 30 days» stands under it with nothing in it.
    func testAFolderWithNoRulesAndNoHistoryDrawsNoHistoryCard() {
        AppLanguage.only(.en) {
            let render = mount(AutopilotWire(folders: [folderWithNoRules]))
            let read = settle(render) { reads($0, noRules) }

            XCTAssertTrue(reads(read, noRules), "precondition: the folder list is drawn — \(read)")
            XCTAssertFalse(reads(read, cardTitle), "a titled card over nothing is on the page — \(read)")
        }
    }

    /// The control: a history something else wrote is a card with its way out
    /// on it, over the same folder with no rules and no passes. Without this the
    /// test above would pass for a page that had simply stopped drawing the card.
    func testARefusedHistoryStillDrawsItsCardWithTheWayOut() {
        AppLanguage.only(.en) {
            let wire = AutopilotWire(folders: [folderWithNoRules],
                                     status: AutopilotStatus(refusal: nil, historyRefused: true))
            let render = mount(wire)
            let read = settle(render) { reads($0, cardTitle) && reads($0, "Clear the record") }

            XCTAssertTrue(reads(read, noRules), "precondition: the folder list is drawn — \(read)")
            XCTAssertTrue(reads(read, cardTitle), "the refused history's card is gone — \(read)")
            XCTAssertTrue(reads(read, "Clear the record and start again"),
                          "the card is drawn without its way out — \(read)")
        }
    }

    /// The card is decided on every change, not once at the first frame: a pass
    /// the engine announces while the page is up brings the card in, and a
    /// record emptied under it takes the card away again.
    func testTheCardComesWithAPassAndGoesWithIt() {
        AppLanguage.only(.en) {
            let wire = AutopilotWire(folders: [folderWithNoRules])
            let render = mount(wire)
            let before = settle(render) { reads($0, noRules) }
            XCTAssertTrue(reads(before, noRules), "precondition: the folder list is drawn — \(before)")
            XCTAssertFalse(reads(before, cardTitle), "precondition: no card before a pass — \(before)")

            // The subscription has to exist before the announcement, or the
            // event is replayed to nobody and nothing below tests anything.
            for _ in 0..<200 where wire.eventReaderCount == 0 { render.settle(1) }
            XCTAssertGreaterThan(wire.eventReaderCount, 0, "the page never subscribed to the engine")

            wire.holds([record()])
            wire.announce(AutopilotEvent.history)
            let after = settle(render) { reads($0, cardTitle) && reads($0, "a.pdf") }
            XCTAssertTrue(reads(after, cardTitle), "a pass arrived and no card came with it — \(after)")
            XCTAssertTrue(reads(after, "a.pdf"), "the card came without the pass in it — \(after)")

            wire.holds([ActionRecord]())
            wire.announce(AutopilotEvent.history)
            let emptied = settle(render) { !reads($0, cardTitle) && reads($0, noRules) }
            XCTAssertTrue(reads(emptied, noRules), "precondition: the page is still drawn — \(emptied)")
            XCTAssertFalse(reads(emptied, cardTitle), "the record emptied and the card stayed — \(emptied)")
        }
    }

    // MARK: - The order in load()

    /// The wire with the status answer held on demand: `load()` is parked
    /// between the folders' answer and the status's, which is the frame the
    /// order is about, and the test reads the model there on purpose rather than
    /// hoping a sampler gets a turn in it.
    private final class StatusHeld: EngineTransport, @unchecked Sendable {
        let wire: AutopilotWire
        private let lock = NSLock()
        private var holding = false
        private var asked = false
        private var parked: CheckedContinuation<Void, Never>?

        init(_ wire: AutopilotWire) { self.wire = wire }

        var events: AsyncStream<EngineEvent> { wire.events }
        var statusAsked: Bool { lock.withLock { asked } }

        /// The next status request waits until `release()`.
        func hold() { lock.withLock { holding = true; asked = false } }

        func release() {
            let waiting: CheckedContinuation<Void, Never>? = lock.withLock {
                holding = false
                defer { parked = nil }
                return parked
            }
            waiting?.resume()
        }

        func send(_ command: EngineCommand) async throws -> Data {
            if AutopilotCommand(rawValue: command.name) == .status {
                await withCheckedContinuation { (go: CheckedContinuation<Void, Never>) in
                    let now: Bool = lock.withLock {
                        asked = true
                        guard holding else { return true }
                        parked = go
                        return false
                    }
                    if now { go.resume() }
                }
            }
            return try await wire.send(command)
        }
    }

    private struct Frame: Equatable {
        let hasRules: Bool
        let refused: Bool
        let block: Bool
    }

    private func frame(_ model: AutopilotViewModel) -> Frame {
        Frame(hasRules: model.folders.contains { !$0.rules.isEmpty },
              refused: model.refusal != nil,
              block: !model.presets.isEmpty)
    }

    private func rule() -> Rule {
        Rule(id: "r", name: "r", enabled: true, conditions: [.kind(.image)], action: .trash)
    }

    private func model(on held: StatusHeld) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: held),
                           presetFolders: FakePresetFolders(home: "/Users/x"), home: "/Users/x")
    }

    /// Runs a `load()` with the status held, and hands back the frame the page
    /// stands on while it is held and the frame it ends on.
    private func loadHeld(_ model: AutopilotViewModel, _ held: StatusHeld) async -> (between: Frame, end: Frame) {
        held.hold()
        let loading = Task { @MainActor in await model.load() }
        for _ in 0..<400 where !held.statusAsked {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(held.statusAsked, "the load never reached the status — nothing below is the frame between")
        let between = frame(model)
        held.release()
        await loading.value
        return (between, frame(model))
    }

    /// Rules arriving with a reading hide the block in the frame they land in,
    /// not one answer later — the half of the repair the engineer kept.
    func testRulesArrivingWithAReadingHideTheBlockBeforeTheStatus() async {
        let held = StatusHeld(AutopilotWire())
        let model = model(on: held)
        await model.firstLoad?.value
        XCTAssertEqual(frame(model), Frame(hasRules: false, refused: false, block: true),
                       "precondition: the block is on screen and no rule is")

        held.wire.holds([WatchedFolder(path: "/Users/x/Music", rules: [rule()])])
        let (between, end) = await loadHeld(model, held)

        XCTAssertEqual(between, Frame(hasRules: true, refused: false, block: false),
                       "the rule landed beside the block, in the frame before the status answered")
        XCTAssertEqual(end, Frame(hasRules: true, refused: false, block: false))
    }

    /// **The engineer's reason for hiding rather than re-deciding, tested.** A
    /// page with a rule has no block; the rule set is then rewritten by
    /// something else, so the engine answers `[]` for the folders and says so
    /// only in the status. Deciding the block when the folders land would read
    /// the stale status — no refusal — and offer the block over a set that is
    /// about to be refused.
    func testARuleSetRefusedUnderThePageNeverOffersTheBlock() async {
        let held = StatusHeld(AutopilotWire(folders: [WatchedFolder(path: "/Users/x/Music", rules: [rule()])]))
        let model = model(on: held)
        await model.firstLoad?.value
        XCTAssertEqual(frame(model), Frame(hasRules: true, refused: false, block: false),
                       "precondition: a page with a rule, no block")

        held.wire.holds([WatchedFolder]())
        held.wire.answers(AutopilotStatus(refusal: .tampered))
        let (between, end) = await loadHeld(model, held)

        XCTAssertEqual(end, Frame(hasRules: false, refused: true, block: false),
                       "precondition: the load ended on the refusal")
        XCTAssertFalse(between.block, "the block was offered over a set about to be refused: \(between)")
    }

    /// A set that stays refused across a reading never offers the block in the
    /// frame between the two answers either.
    func testAReadingOfAStillRefusedSetNeverOffersTheBlock() async {
        let held = StatusHeld(AutopilotWire(folders: [], status: AutopilotStatus(refusal: .tampered)))
        let model = model(on: held)
        await model.firstLoad?.value
        XCTAssertEqual(model.refusal, .tampered, "precondition: the set is refused")

        let (between, end) = await loadHeld(model, held)
        XCTAssertFalse(between.block, "the block was offered over a refused set: \(between)")
        XCTAssertFalse(end.block)
    }

    /// **What the hide-only choice costs.** Rules taken away by a reading
    /// (another writer emptied the set, nothing refused) leave a frame with
    /// neither rules nor block until the status answers — measured, and the
    /// safe direction, so not asserted either way. What is held is that the
    /// block does come back with the status, the half a hide-only repair could
    /// lose.
    func testRulesTakenAwayByAReadingBringTheBlockBackWithTheStatus() async {
        let held = StatusHeld(AutopilotWire(folders: [WatchedFolder(path: "/Users/x/Music", rules: [rule()])]))
        let model = model(on: held)
        await model.firstLoad?.value
        XCTAssertEqual(frame(model), Frame(hasRules: true, refused: false, block: false),
                       "precondition: a page with a rule, no block")

        held.wire.holds([WatchedFolder(path: "/Users/x/Music")])
        let (between, end) = await loadHeld(model, held)

        XCTAssertFalse(between.hasRules, "precondition: the reading without rules landed before the status")
        XCTAssertEqual(end, Frame(hasRules: false, refused: false, block: true),
                       "the block never came back once the rules were gone")
    }
}
