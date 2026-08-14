import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// The page's half of the Trash-offer switch.
///
/// The switch said on with nothing behind it, and the page could not have said
/// otherwise: `watchingTrash` answered a `Bool`, so «on» was the whole of what
/// reached the UI, and the one sentence that names what the missing grant costs
/// here — `UnStr.accessNeededWithWatch` — stood only on `PermissionCheck`'s probe
/// of the grant.
///
/// A refused `contentsOfDirectory` on the Trash is the better evidence of the two:
/// reading `~/.Trash` is precisely what that grant covers, and the engine has
/// really tried. So the note stands over the engine's reading as well, with the
/// page's own probe left saying what it says.
///
/// **What the switch's row itself says in the two blind states is not written
/// here.** It needs a new sentence in eight languages and that is the localizer's;
/// this file wires and guards the state it will be drawn from.
@MainActor
final class TheOfferSwitchIsNotJustAFlagTests: XCTestCase {

    private let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                    path: "/Applications/Tool.app", sizeBytes: 4_096)

    private func page(_ wire: UninstallerWire) -> (UninstallerSettingsPage, UninstallerViewModel) {
        let vm = ModuleViewModel(transport: wire)
        return (UninstallerSettingsPage(vm: vm), UninstallerViewModel.shared(vm: vm))
    }

    // MARK: -

    /// **The measurement this file exists for.** The probe says the grant is there
    /// — the page's `diskAccess` starts `.granted` and nothing mounted has changed
    /// it — and the engine says the read was refused. The note is drawn.
    func testARefusedTrashReadPutsTheNoteUpEvenWhenTheProbeIsHappy() async {
        let wire = UninstallerWire(apps: [tool], watching: .cannotReadTrash)
        let (page, uvm) = page(wire)

        await uvm.refreshTrashWatch()

        XCTAssertEqual(uvm.trashWatch, .cannotReadTrash,
                       "precondition: the engine's reading reached the page's model")
        XCTAssertEqual(page.permissionNote, UnStr.accessNeededWithWatch, """
            a switch that is on over a Trash Helm was refused the read of, and the page has \
            nothing at all to say about it
            """)
    }

    /// And a switch that is on and working says nothing, so the note is about a
    /// refusal rather than about the feature being enabled.
    func testAWorkingOfferDrawsNoNote() async {
        let wire = UninstallerWire(apps: [tool], watching: .on)
        let (page, uvm) = page(wire)

        await uvm.refreshTrashWatch()

        XCTAssertEqual(uvm.trashWatch, .on, "precondition: the engine reported a working offer")
        XCTAssertNil(page.permissionNote,
                     "a permission note over a permission nobody was refused: "
                     + "«\(page.permissionNote ?? "")»")
    }

    /// The switch draws from the same value, so it cannot disagree with the note
    /// beside it.
    func testTheSwitchReadsTheEngineNotAFlagOfItsOwn() async {
        for state in TrashWatch.allCases {
            let wire = UninstallerWire(apps: [tool], watching: state)
            let (_, uvm) = page(wire)

            await uvm.refreshTrashWatch()

            XCTAssertEqual(uvm.trashWatch.isOn, state != .off,
                           "\(state) drew the switch the wrong way round")
        }
    }

    /// A reading nobody answered leaves the switch where it was. Folded to
    /// `false`, an unanswered read drew it as **off** — a claim about a setting, on
    /// the control a person would press to change it.
    func testAnUnansweredReadingDoesNotFlipTheSwitchOff() async {
        for silence in [UninstallerWire.Answer.refuse, .nothing] {
            let wire = UninstallerWire(apps: [tool], watching: .on)
            let (_, uvm) = page(wire)
            await uvm.refreshTrashWatch()
            XCTAssertTrue(uvm.trashWatch.isOn, "precondition: it is on (\(silence))")

            wire.answers(silence, to: .watchingTrash)
            await uvm.refreshTrashWatch()

            XCTAssertTrue(uvm.trashWatch.isOn,
                          "the switch drew itself off over an answer that never came (\(silence))")
        }
    }

    /// Pressing it answers the switch at once — a `Toggle` whose binding waits for
    /// a round trip snaps back under the pointer — and then takes the engine's own
    /// reading of what it is doing.
    func testThePressAnswersAtOnceAndThenTakesTheEnginesReading() async {
        let wire = UninstallerWire(apps: [tool], watching: .off)
        let (_, uvm) = page(wire)
        wire.setWatch(.cannotReadTrash)

        await uvm.setWatchingTrash(true)

        XCTAssertTrue(wire.commands.contains(.setWatchingTrash),
                      "precondition: the press reached the engine")
        XCTAssertEqual(uvm.trashWatch, .cannotReadTrash,
                       "the press left the page believing its own optimistic answer")
    }
}
