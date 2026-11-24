import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **The engine's last word on a shared switch counts rivals it could not see.**
///
/// `TheEngineRefusesASharedSwitchTests` holds the rule: `launchctl disable
/// gui/<uid>/<label>` is aimed at a label, two files can register one label, Helm
/// cannot read which of the two launchd kept, so neither may be switched. The
/// engine asks it of the disk at the moment of the press, through
/// `LaunchClaims.onDisk`.
///
/// `contents(of:).entries` is the list with the reason for an empty one thrown
/// away — fine for a caller that draws no conclusion from an empty answer, wrong
/// for `onDisk`, which concludes from it that no second file registers the label
/// and the press may go through. A folder that would not open would take the
/// rival with it, and the switch would be aimed at a label two files register.
///
/// **Either agent folder can refuse a listing** —
/// `DirectoryListing.Contents.refused` names a mode, an ACL, a folder belonging
/// to somebody else, or a TCC grant. So `onDisk` reads `contents(of:)` and
/// carries `everyFolderOpened`, and a switch may not be aimed at a label whose
/// rivals were never counted.
final class ARivalTheEngineCouldNotSeeIsNotAbsentTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")
    private let label = "com.vendor.updater"
    private var mine: String { "/Users/x/Library/LaunchAgents/\(label).plist" }
    private var roots: String { "/Library/LaunchAgents/\(label).plist" }

    /// Both agent folders hold the same label — the ordinary shape on a Mac with a
    /// vendor updater installed for the person and for everybody.
    ///
    /// `unopenable` names folders whose `contents(of:)` answers `.refused`, the
    /// port's third answer: the fake can be in that state because the port can
    /// (Architecture/TestsAndMeasurement.md § Fakes).
    private func files(refusing refused: Set<String> = []) -> LeftoversFakeFiles {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["\(label).plist"]
        files.plists[mine] = PlistData(["Label": label])
        files.listing["/Library/LaunchAgents"] = ["\(label).plist"]
        files.plists[roots] = PlistData(["Label": label])
        files.unopenable = refused
        return files
    }

    /// Every port named at every construction, so nothing here is a reading of the
    /// Mac running the suite — `EveryEngineNamesItsPortsTests` holds the rule.
    private func engine(_ files: LeftoversFakeFiles,
                        _ recorder: LeftoversFakeSwitcher) -> LeftoversEngine {
        LeftoversEngine(home: home, files: files, apps: LeftoversFakeApps(),
                        loaded: LeftoversFakeLoaded(), switcher: recorder,
                        store: freshLeftoversStore())
    }

    private func press(_ path: String, on engine: LeftoversEngine) async {
        await engine.setDisabled(LeftoversToggle(label: label, path: path, disabled: true))
    }

    /// What `LaunchClaims` reports to the engine, for the failure message: the count
    /// is the whole mechanism, and printing it saves the reader a second run.
    private func claimsSeen(_ files: LeftoversFakeFiles) -> [String] {
        LaunchClaims.claimants(of: label, in: LaunchClaims.onDisk(home: home, files: files).claims)
    }

    // MARK: - The finding

    /// **Root's agent folder would not open, and the switch does not go through.**
    func testASwitchIsRefusedWhenAnAgentFolderWouldNotOpen() async throws {
        let files = files(refusing: ["/Library/LaunchAgents"])
        let recorder = LeftoversFakeSwitcher()

        await press(mine, on: engine(files, recorder))

        XCTAssertEqual(recorder.labels, [], """
            `/Library/LaunchAgents` answered `.refused` — a folder that would not open \
            (`DirectoryListing.Contents.refused`: a mode, an ACL, a folder belonging to \
            somebody else, or a TCC grant; on the Mac this was written on it lists \
            openly, `drwxr-xr-x root wheel`, so this is the fixture's refusal) — \
            and the engine sent `launchctl disable gui/<uid>/\(label)` anyway.

            `LaunchClaims.onDisk` reported \(claimsSeen(files).count) claimant(s): \
            \(claimsSeen(files)). There are two files carrying that Label in this \
            fixture; the second is in the folder that did not open, and \
            `LaunchClaims.onDisk` reads that folder through \
            `LeftoversFilePort.contents(of:)`, which answers `.refused`; a read \
            that took only its `.entries` counted it as an empty list.

            So the guard that exists because Helm cannot read which of two \
            registrations launchd kept was passed by never counting the second one. A \
            press on the row badged «Leftover» stops whichever job launchd kept, \
            including the one the same scan reports «In use» — which is what happens \
            with a folder that refuses to open.
            """)
    }

    /// The person's own folder is the other half, and it is behind the TCC grant:
    /// the same hole, entered from the other side.
    func testASwitchIsRefusedWhenTheUsersOwnAgentFolderWouldNotOpen() async throws {
        let files = files(refusing: ["/Users/x/Library/LaunchAgents"])
        let recorder = LeftoversFakeSwitcher()

        await press(roots, on: engine(files, recorder))

        XCTAssertEqual(recorder.labels, [], """
            `~/Library/LaunchAgents` answered `.refused` and the engine switched \
            \(label) off on the strength of \(claimsSeen(files).count) claimant(s) it \
            could count. The folder holding the other one was never opened, and an \
            unopened folder is not an empty one.
            """)
    }

    /// And a refusal is not cured by there being only one file to find in what did
    /// open: a folder that did not open could have held anything, including the
    /// rival, which is the whole reason `.refused` is a case of its own.
    func testASwitchIsRefusedEvenWhenTheReadableFolderHoldsTheOnlyKnownCopy() async throws {
        var files = files(refusing: ["/Library/LaunchAgents"])
        files.listing["/Library/LaunchAgents"] = []
        files.plists[roots] = nil
        let recorder = LeftoversFakeSwitcher()

        await press(mine, on: engine(files, recorder))

        XCTAssertEqual(recorder.labels, [], """
            the fixture's `/Library/LaunchAgents` is empty and refused, and the engine \
            went ahead. Whether that folder really held a rival is unknowable to Helm \
            precisely because it did not open — the fixture knows, the app does not, and \
            the app is what must refuse.
            """)
    }

    // MARK: - Controls

    /// **The control that keeps the feature.** Both folders opened, one file
    /// registers the label — the switch works.
    ///
    /// Without it, a guard that refused every press would pass the tests above
    /// and this module would lose «Turn off» entirely.
    func testALabelOnlyOneOpenedFolderRegistersIsStillSwitched() async throws {
        var files = files()
        files.listing["/Library/LaunchAgents"] = []
        files.plists[roots] = nil
        let recorder = LeftoversFakeSwitcher()

        await press(mine, on: engine(files, recorder))

        XCTAssertEqual(recorder.labels, [label],
                       "both agent folders opened and only one file registers the label, "
                       + "so there is nothing to refuse")
    }

    /// **The control that fixes the address.** A folder the switch's question is not
    /// asked of — `/Library/LaunchDaemons`, whose jobs load in the system domain
    /// that `launchctl disable gui/<uid>/…` does not reach — may be refused without
    /// withholding anything.
    ///
    /// This tells «the engine counts rivals it could not see» from «the engine
    /// gives up on any unreadable folder anywhere»: both would be green on the
    /// tests above.
    func testARefusedFolderThatIsNotAnAgentFolderWithholdsNothing() async throws {
        var files = files()
        files.listing["/Library/LaunchAgents"] = []
        files.plists[roots] = nil
        files.listing["/Library/LaunchDaemons"] = ["\(label).plist"]
        files.plists["/Library/LaunchDaemons/\(label).plist"] = PlistData(["Label": label])
        files.unopenable = ["/Library/LaunchDaemons"]
        let recorder = LeftoversFakeSwitcher()

        await press(mine, on: engine(files, recorder))

        XCTAssertEqual(recorder.labels, [label],
                       "a daemon is a different job in a different domain, so "
                       + "`LaunchClaims.agentFolders` never asks that folder anything and "
                       + "its refusal is not this switch's business")
    }

    /// **The control that proves the fixture is loaded at all.** Both folders opened
    /// and both hold the label — the engine refuses, as
    /// `TheEngineRefusesASharedSwitchTests` already records.
    ///
    /// Every assertion above is an *absence* — `recorder.labels == []` — and an
    /// absence passes just as well when the press never reached the engine, the
    /// request was built wrong, or the label was dropped on the way. This is the
    /// same press arriving.
    func testTheSwitchIsRefusedWhenBothFoldersOpenedAndBothHoldTheLabel() async throws {
        let files = files()
        let recorder = LeftoversFakeSwitcher()

        await press(mine, on: engine(files, recorder))

        XCTAssertEqual(recorder.labels, [])
        XCTAssertEqual(claimsSeen(files).count, 2,
                       "and the two claims are what the engine read, so the refusal above "
                       + "is this rule and not a press that never arrived")
    }
}
