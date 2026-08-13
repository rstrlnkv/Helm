import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// What this page promises before it acts, and what it says afterwards.
@MainActor
final class LeftoversPageContractTests: XCTestCase {

    private final class ScanTransport: EngineTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var items: [StaleItem]
        private var removal: LeftoversRemoval
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

        init(items: [StaleItem],
             removal: LeftoversRemoval = LeftoversRemoval(removed: [], refused: [], freedBytes: 0)) {
            self.items = items
            self.removal = removal
        }

        /// What the rescan after a removal will see.
        func setItems(_ next: [StaleItem]) { lock.lock(); items = next; lock.unlock() }

        private var current: [StaleItem] { lock.lock(); defer { lock.unlock() }; return items }
        private var currentRemoval: LeftoversRemoval {
            lock.lock(); defer { lock.unlock() }; return removal
        }

        /// The enum, not the two literals this used to switch on. A fake that
        /// answers names of its own is a fake that goes on answering after the
        /// module renames one — and what it answers then is `Data()`, which this
        /// codebase spells «the module could not answer».
        func send(_ command: EngineCommand) async throws -> Data {
            switch LeftoversCommand(rawValue: command.name) {
            case .scan: return (try? JSONEncoder().encode(current)) ?? Data()
            case .trash: return (try? JSONEncoder().encode(currentRemoval)) ?? Data()
            case .setDisabled, .none: return Data()
            }
        }
    }

    private func agent(_ name: String, bytes: Int, status: ItemStatus = .orphaned) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: bytes, status: status)
    }

    // MARK: - The bottom bar's two quantities

    /// The bar read "1 объект · 0 Б" with nothing ticked, above a visible row
    /// saying 4 КБ: the count was everything found and removable, the size was
    /// the selection, and the middle dot made them look like one measurement.
    func testTheBarsCountAndSizeAreBothAboutTheSelection() async {
        let transport = ScanTransport(items: [agent("one", bytes: 4_096),
                                              agent("two", bytes: 8_192)])
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await lvm.scan()
        XCTAssertEqual(lvm.leftoverCount, 2, "precondition: two removable rows were found")

        XCTAssertEqual(lvm.selectedCount, 0, "nothing is ticked, so the bar counts nothing")
        XCTAssertEqual(lvm.selectedBytes, 0)

        lvm.selected.insert(lvm.visibleItems[0].path)

        XCTAssertEqual(lvm.selectedCount, 1)
        XCTAssertEqual(lvm.selectedBytes, 4_096)
    }

    /// A tick on a row that is no longer shown counts for neither figure — the
    /// same rule `removeSelected` follows when it decides what may go.
    func testAHiddenTickIsCountedByNeitherFigure() async {
        let transport = ScanTransport(items: [agent("kept", bytes: 4_096),
                                              agent("busy", bytes: 8_192, status: .inUse)])
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        lvm.showAll = true
        await lvm.scan()
        lvm.selected = Set(lvm.visibleItems.map(\.path))
        XCTAssertEqual(lvm.selectedCount, 2, "precondition: both rows are shown and ticked")

        lvm.showAll = false     // back to leftovers only

        XCTAssertEqual(lvm.selectedCount, 1,
                       "a row the list no longer shows was still counted in the bar")
        XCTAssertEqual(lvm.selectedBytes, 4_096)
    }

    // MARK: - What the page says when the list is empty

    /// **The ordinary first impression, and it was 515 pt of nothing.** A scan of
    /// a clean Mac finds hundreds of settings files and no leftovers: the page had
    /// rows in `items`, none in `visibleItems`, and drew the list's branch — an
    /// empty area under «Found: 0 items» and the note about nothing being ticked.
    func testAScanThatFoundNoLeftoversHasSomethingToSay() async {
        let transport = ScanTransport(items: [agent("busy", bytes: 4_096, status: .inUse),
                                              agent("system", bytes: 8_192, status: .protectedItem)])
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await lvm.scan()

        XCTAssertFalse(lvm.items.isEmpty, "precondition: the scan found something")
        XCTAssertTrue(lvm.visibleItems.isEmpty, "precondition: none of it is a leftover")
        XCTAssertEqual(lvm.nothingToShow, .nothingFound,
                       "the page draws its list against no rows, so the screen is the note "
                       + "about nothing being ticked over an empty area")
    }

    /// And when the kind filter is what emptied it, the page says *that* — the
    /// menu is on screen above the message, and «No leftovers found» would be a
    /// claim about the Mac where the truth is a claim about a menu.
    func testRowsHiddenByTheKindFilterAreNotReportedAsACleanMac() async {
        let transport = ScanTransport(items: [agent("gone", bytes: 4_096)])
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await lvm.scan()
        XCTAssertNil(lvm.nothingToShow, "precondition: there is a row to draw")

        lvm.hiddenKinds.insert(.launchAgent)

        XCTAssertEqual(lvm.nothingToShow, .hiddenByFilter)
    }

    /// Before the first scan it is the invitation, whatever is in the model.
    func testAnUnscannedPageInvites() {
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: ScanTransport(items: [])))

        XCTAssertEqual(lvm.nothingToShow, .notScanned)
    }

    // MARK: - One act, one name

    /// The ellipsis is a promise of a dialog. For a leftover there is none, and
    /// the row deleted on the click — while the bar three inches away called the
    /// same act "Move to Trash".
    func testTheRowNamesTheActItPerforms() {
        let leftover = agent("gone", bytes: 4_096)
        let inUse = agent("busy", bytes: 4_096, status: .inUse)
        XCTAssertFalse(LeftoverActions.needsConfirmation(leftover),
                       "precondition: a leftover is deleted without a dialog")
        XCTAssertTrue(LeftoverActions.needsConfirmation(inUse))

        XCTAssertEqual(LeftoversSettingsPage.deleteLabel(for: leftover), LfStr.removeSelected,
                       "the ellipsis promised a step that never comes")
        XCTAssertEqual(LeftoversSettingsPage.deleteLabel(for: inUse), LfStr.deleteItem)
    }

    // MARK: - What the Trash is

    /// The Trash is a folder on the same volume: nothing is free until it is
    /// emptied. Disk's `movedToTrash` says where the files went, in Finder's own
    /// words for the act, and this module now says the same thing.
    func testTheBannerReportsTheMoveRatherThanFreedSpace() async {
        let item = agent("gone", bytes: 4_096)
        let transport = ScanTransport(
            items: [item],
            removal: LeftoversRemoval(removed: [item.path], refused: [], freedBytes: 4_096))
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await lvm.scan()
        lvm.selected.insert(item.path)
        transport.setItems([])

        await lvm.removeSelected()

        XCTAssertEqual(lvm.banner, LfStr.movedToTrash(Bytes(4_096)),
                       "the banner promises space that only emptying the Trash gives back")
        XCTAssertEqual(lvm.removedCount, 1)
    }

    // MARK: - What a refusal says

    /// The refusal reaches the page with its reason as a **reason**, not as a
    /// word inside a field called `message`. That field was this module's own
    /// copy of the shared refusal, and what it carried was `reason.rawValue` by
    /// convention — nothing in the type said so, and the page handed it to
    /// `TrashReasonText.sentence`, which answers its `default` for anything else.
    /// This is the one place the module ever names a refusal.
    func testARefusalArrivesWithItsReasonRatherThanAWordInAMessage() async {
        let item = agent("locked", bytes: 4_096)
        let refusal = HelmTrash.Refusal(path: item.path, reason: .needsFullDiskAccess)
        let transport = ScanTransport(
            items: [item],
            removal: LeftoversRemoval(removed: [], refused: [refusal], freedBytes: 0))
        let lvm = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await lvm.scan()
        lvm.selected.insert(item.path)

        await lvm.removeSelected()

        XCTAssertEqual(lvm.failures.map(\.path), [item.path],
                       "the refused path is not named anywhere the page can reach")
        XCTAssertEqual(lvm.failures.map(\.reason), [TrashFailure.Reason.needsFullDiskAccess])
        XCTAssertEqual(lvm.removedCount, 0)
    }

    /// And the question asked first is one question. It carried a second
    /// sentence — "It will free 4 KB." — about something that had not happened
    /// and would not happen by pressing the button.
    func testTheConfirmationIsOneQuestionAndClaimsNothingAfterIt() {
        let question = LfStr.confirmSelected(2, Bytes(4_096)).trimmingCharacters(in: .whitespaces)

        XCTAssertTrue(question.hasSuffix("?") || question.hasSuffix("？"),
                      "the confirmation carries a claim after the question: \(question)")
        XCTAssertTrue(question.contains(Bytes(4_096)),
                      "the confirmation stopped saying how much is going")
    }
}
