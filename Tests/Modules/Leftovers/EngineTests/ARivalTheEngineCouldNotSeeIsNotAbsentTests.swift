import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **The engine's last word on a shared switch is read through the one call that
/// folds «refused» back into «empty».**
///
/// `TheEngineRefusesASharedSwitchTests` holds the rule: `launchctl disable
/// gui/<uid>/<label>` is aimed at a label, two files can register one label, Helm
/// cannot read which of the two launchd kept, so neither may be switched. The
/// engine asks it of the disk at the moment of the press, through
/// `LaunchClaims.onDisk`, and `onDisk` opened the two agent folders with
/// `files.children(of:)` until 2026-09-08.
///
/// `children(of:)` is `contents(of:).entries`, and the port's own documentation
/// says what that costs:
///
/// > What is in the directory, for a caller that walks what it finds and **draws
/// > no conclusion from an empty answer** — every reader of a *source* draws one,
/// > so every reader of a source asks `contents(of:)`.
///
/// `onDisk` draws the strongest conclusion in the module from an empty answer: no
/// second file registers this label, therefore the press may go through. A folder
/// that would not open comes back with nothing in it, the rival vanishes with the
/// folder, and the switch is aimed at a label two files register — which is the
/// exact act the guard exists to refuse. `DirectoryListing.Contents.refused` was
/// added for this fold one layer up (`ASourceNobodyWalkedIsNotACleanMacTests`);
/// this is the same fold left in place at the port that *acts*.
///
/// **It is not a hypothetical folder.** `/Library/LaunchAgents` is root's and Helm
/// is not root; `~/Library/LaunchAgents` is behind a TCC grant that is denied on 23
/// of the 42 launches ARCHITECTURE.md records. Either one going unread turns «two
/// files claim this switch» into «one does», silently, on the safe-direction side
/// of a guard whose whole subject is the unsafe direction.
///
/// The refusal the engine already has for a rival it *can* see was the shape of the
/// repair, and it is what shipped: `LaunchClaims.onDisk` now reads `contents(of:)`
/// and carries `everyFolderOpened`, and a switch may not be aimed at a label whose
/// rivals were never counted. What holds it is below — this file is the mutation
/// that said the hole was real, kept as the guard that says it is closed.
final class ARivalTheEngineCouldNotSeeIsNotAbsentTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")
    private let label = "com.vendor.updater"
    private var mine: String { "/Users/x/Library/LaunchAgents/\(label).plist" }
    private var roots: String { "/Library/LaunchAgents/\(label).plist" }

    /// Both agent folders hold the same label — the ordinary shape on a Mac with a
    /// vendor updater installed for the person and for everybody.
    ///
    /// `unopenable` names folders whose `contents(of:)` answers `.refused`, which is
    /// the port's third answer: the fake can be in that state because the port can
    /// (CLAUDE.md § A fake simpler than the thing it stands for).
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
                        loaded: LeftoversFakeLoaded(), switcher: recorder)
    }

    private func press(_ path: String, on engine: LeftoversEngine) async throws {
        _ = try await engine.transport.send(
            EngineCommand(name: LeftoversCommand.setDisabled.rawValue,
                          payload: try JSONEncoder().encode(
                            LeftoversToggle(label: label, path: path, disabled: true))))
    }

    /// What `LaunchClaims` reports to the engine, for the failure message: the count
    /// is the whole mechanism, and printing it saves the reader a second run.
    private func claimsSeen(_ files: LeftoversFakeFiles) -> [String] {
        LaunchClaims.claimants(of: label, in: LaunchClaims.onDisk(home: home, files: files))
    }

    // MARK: - The finding

    /// **Root's agent folder would not open, and the switch went through.**
    func testASwitchIsRefusedWhenAnAgentFolderWouldNotOpen() async throws {
        let files = files(refusing: ["/Library/LaunchAgents"])
        let recorder = LeftoversFakeSwitcher()

        try await press(mine, on: engine(files, recorder))

        XCTAssertEqual(recorder.labels, [], """
            `/Library/LaunchAgents` answered `.refused` — a folder Helm may not open, \
            which is root's own and an ordinary answer for a process that is not root — \
            and the engine sent `launchctl disable gui/<uid>/\(label)` anyway.

            `LaunchClaims.onDisk` reported \(claimsSeen(files).count) claimant(s): \
            \(claimsSeen(files)). There are two files carrying that Label in this \
            fixture; the second is in the folder that did not open, and \
            `LeftoversFilePort.children(of:)` hands a refusal back as an empty list.

            So the guard that exists because Helm cannot read which of two \
            registrations launchd kept was passed by never counting the second one. A \
            press on the row badged «Leftover» stops whichever job launchd kept, \
            including the one the same scan reports «In use» — which is what happens \
            with Full Disk Access denied, 23 launches out of the 42 ARCHITECTURE.md \
            records.
            """)
    }

    /// The person's own folder is the other half, and it is behind the TCC grant:
    /// the same hole, entered from the other side.
    func testASwitchIsRefusedWhenTheUsersOwnAgentFolderWouldNotOpen() async throws {
        let files = files(refusing: ["/Users/x/Library/LaunchAgents"])
        let recorder = LeftoversFakeSwitcher()

        try await press(roots, on: engine(files, recorder))

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

        try await press(mine, on: engine(files, recorder))

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
    /// Without it, a guard that refused every press would pass the three tests above
    /// and this module would lose «Turn off» entirely.
    func testALabelOnlyOneOpenedFolderRegistersIsStillSwitched() async throws {
        var files = files()
        files.listing["/Library/LaunchAgents"] = []
        files.plists[roots] = nil
        let recorder = LeftoversFakeSwitcher()

        try await press(mine, on: engine(files, recorder))

        XCTAssertEqual(recorder.labels, [label],
                       "both agent folders opened and only one file registers the label, "
                       + "so there is nothing to refuse")
    }

    /// **The control that fixes the address.** A folder the switch's question is not
    /// asked of — `/Library/LaunchDaemons`, whose jobs load in the system domain
    /// that `launchctl disable gui/<uid>/…` does not reach — may be refused without
    /// withholding anything.
    ///
    /// This is what tells «the engine counts rivals it could not see» from «the
    /// engine gives up on any unreadable folder anywhere». Both would be green on
    /// the tests above; only one of them is the finding.
    func testARefusedFolderThatIsNotAnAgentFolderWithholdsNothing() async throws {
        var files = files()
        files.listing["/Library/LaunchAgents"] = []
        files.plists[roots] = nil
        files.listing["/Library/LaunchDaemons"] = ["\(label).plist"]
        files.plists["/Library/LaunchDaemons/\(label).plist"] = PlistData(["Label": label])
        files.unopenable = ["/Library/LaunchDaemons"]
        let recorder = LeftoversFakeSwitcher()

        try await press(mine, on: engine(files, recorder))

        XCTAssertEqual(recorder.labels, [label],
                       "a daemon is a different job in a different domain, so "
                       + "`LaunchClaims.agentFolders` never asks that folder anything and "
                       + "its refusal is not this switch's business")
    }

    /// **The control that proves the fixture is loaded at all.** Both folders opened
    /// and both hold the label — the engine refuses, as
    /// `TheEngineRefusesASharedSwitchTests` already records.
    ///
    /// Green today and green after the repair. It is here because every assertion
    /// above is an *absence* — `recorder.labels == []` — and an absence passes just
    /// as well when the press never reached the engine, the command name was wrong,
    /// or the transport dropped the payload. This is the same press arriving.
    func testTheSwitchIsRefusedWhenBothFoldersOpenedAndBothHoldTheLabel() async throws {
        let files = files()
        let recorder = LeftoversFakeSwitcher()

        try await press(mine, on: engine(files, recorder))

        XCTAssertEqual(recorder.labels, [])
        XCTAssertEqual(claimsSeen(files).count, 2,
                       "and the two claims are what the engine read, so the refusal above "
                       + "is this rule and not a press that never arrived")
    }
}
