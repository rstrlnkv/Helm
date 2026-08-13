import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **The two places this module turns «the engine did not answer» into a
/// statement about somebody's Mac.**
///
/// `TransportClient.request` answers `nil` for a request that threw and for a
/// reply that would not decode — «the module could not answer», in this
/// codebase's own words. Both of this module's requests fold that nil into a
/// positive claim:
///
///     let found: [StaleItem] = await client.request(LeftoversCommand.scan) ?? []
///     …
///     items = found; scanned = true
///
/// so a scan nobody answered is «No leftovers found» over an empty list — a
/// sentence about the machine — and it also *replaces* whatever the person was
/// working through. And:
///
///     failures = result?.refused ?? []
///     removedCount = result?.removed.count ?? 0
///     banner = LfStr.movedToTrash(Bytes(result?.freedBytes ?? 0))
///
/// so a removal nobody answered is «Moved to the Trash — Zero KB» with no
/// refusals in it, which `HelmRemovalOutcome.verdict` reads as `.silent` and draws
/// as nothing at all. The files are still where they were.
///
/// **The state is not hypothetical, and this module's own two files name it.**
/// `LeftoversEngine.wireTransport` answers empty `Data` when the engine has been
/// deallocated under a page that is still up, and again for a command name it does
/// not parse — the door `LeftoversCommand`'s doc leaves open on purpose.
/// `LeftoversViewModel.shared(vm:)` says the same thing from the other end: a
/// cached model outliving its engine holds a transport that «answers every request
/// with empty Data from then on». So one layer of this module says «I could not
/// answer» and the layer above reads it as an answer. Disk, walking the same
/// ground, refuses the fold on the reading side —
/// `guard let scan else { phase = .start; return }` — and keeps the tree it has.
///
/// **Both silences, because the wire has two.** Empty `Data` is the one this
/// module reaches today; a throw is what `EngineTransport.send` is declared to do
/// and what `TransportClient` already folds to the same nil. The view model cannot
/// tell them apart, which is exactly why a test that tried only one would leave
/// the other unmeasured.
///
/// These are the tester's tests and they are **expected to fail** until the fold
/// is refused. What a fix looks like is the engine's own precedent: keep the list,
/// leave `scanned` alone, and say nothing about the Trash that did not happen.
@MainActor
final class AnUnansweredRequestIsNotAnAnswerTests: XCTestCase {

    private static let silences: [LeftoversWire.Answer] = [.refuse, .nothing]

    private func agent(_ name: String, bytes: Int = 4_096) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: bytes, status: .orphaned)
    }

    // MARK: - The scan

    /// A first scan that was never answered must not read as a clean Mac.
    ///
    /// «No leftovers found.» is the module's strongest claim: it is the one screen
    /// that tells somebody there is nothing here to look at. Reached, today, by a
    /// request that never came back.
    func testAScanThatWasNeverAnsweredDoesNotClaimACleanMac() async {
        for silence in Self.silences {
            let wire = LeftoversWire(items: [agent("com.vendor.updater")], answering: silence)
            let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))

            await model.scan()

            XCTAssertEqual(wire.commands, [.scan],
                           "precondition: the scan really was sent (\(silence))")
            XCTAssertNotEqual(model.nothingToShow, .nothingFound, """
                a scan the engine never answered (\(silence)) draws «\(LfStr.nothingFound)» — the \
                page's one claim about the state of the Mac, made from a request that came back \
                with nothing. `DiskViewModel.scan` keeps its screen where it was for the same nil.
                """)
        }
    }

    /// And a rescan that was never answered must not throw away the list the
    /// person is working through.
    ///
    /// **The Scan button is not the only caller**, which is what makes this worth a
    /// test of its own: `setDisabled` rescans after every «Turn off», and `trash`
    /// rescans after every removal. So an engine that goes away mid-session takes
    /// the list *and* every tick on it at the next toggle — `dropHiddenSelections`
    /// intersects the selection with a list that is now empty — and leaves «No
    /// leftovers found» in their place.
    func testARescanThatWasNeverAnsweredKeepsTheListItAlreadyHas() async {
        for silence in Self.silences {
            let wire = LeftoversWire(items: [agent("com.vendor.updater"),
                                             agent("com.vendor.quiet", bytes: 8_192)])
            let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
            await model.scan()
            model.selected = model.selectablePaths
            XCTAssertEqual(model.items.count, 2, "precondition: the first scan found two rows")
            XCTAssertEqual(model.selected.count, 2, "precondition: both are ticked")

            wire.answers(silence)
            await model.scan()

            XCTAssertEqual(model.items.count, 2, """
                a rescan the engine never answered (\(silence)) emptied a list of two rows, so a \
                «Turn off» after the engine went away replaces the page with «\
                \(LfStr.nothingFound)».
                """)
            XCTAssertEqual(model.selected.count, 2,
                           "and every tick the person had made went with it")
        }
    }

    // MARK: - The removal

    /// A removal that was never answered must not report that anything moved.
    ///
    /// What the page says today: `banner` is set to «Moved to the Trash — Zero KB»
    /// whatever came back, `removedCount` is 0 and `failures` is empty — and
    /// `HelmRemovalOutcome.verdict(removed: 0, failed: 0)` is `.silent`, so the row
    /// above the bar draws `EmptyView`. Press the button, wait, and the page has
    /// nothing to say while the files sit exactly where they were.
    func testARemovalThatWasNeverAnsweredDoesNotReportAMove() async {
        for silence in Self.silences {
            let item = agent("com.vendor.updater")
            let wire = LeftoversWire(items: [item])
            let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
            await model.scan()
            model.selected = [item.path]

            wire.answers(silence)
            await model.removeSelected()

            XCTAssertTrue(wire.commands.contains(.trash),
                          "precondition: the batch really was sent (\(silence))")
            XCTAssertNotEqual(model.banner, LfStr.movedToTrash(0, Bytes(0)), """
                a removal the engine never answered (\(silence)) reports «\
                \(LfStr.movedToTrash(0, Bytes(0)))» with no refusal beside it, which the outcome row \
                draws as nothing at all — so the one thing the person is told about a batch that \
                never happened is that it did.
                """)
        }
    }
}
