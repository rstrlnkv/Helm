import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **The page withholding the switch is half a guard.**
///
/// `LeftoverActions.available` no longer offers «Turn off» where two files register
/// one label (`OneLabelIsOneSwitchTests`), and that is a rule about what is *drawn*.
/// The act is the engine's: a request carrying a label and a path is whatever built
/// it, and `ARCHITECTURE.md § Removal scope` is the standing answer to «the view
/// model already decided». `LaunchLabel.mayBeSwitched` passes both copies of
/// `com.vendor.updater` — each sits in a LaunchAgents folder and each is named
/// after its label — so without this the engine would send `launchctl disable
/// gui/<uid>/com.vendor.updater` for either row, which is the same act on the same
/// job the scan calls «In use».
///
/// The engine asks `LaunchClaims` of the **disk at the press**, not of the list on
/// screen: a scan is as old as the moment it ran, and this is the reading that
/// decides whether somebody's login item stops loading.
final class TheEngineRefusesASharedSwitchTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")
    private let label = "com.vendor.updater"
    private var path: String { "/Users/x/Library/LaunchAgents/\(label).plist" }

    /// The person's own copy of an agent, and root's alongside it when `shared`.
    ///
    /// **Every port is named at every construction**, so what the engine reads is
    /// this fixture and never this Mac's own `/Library/LaunchAgents` — the default
    /// argument is the real filesystem, and a forgetful construction would make the
    /// answer a fact about whoever runs the suite (CLAUDE.md). The promise was
    /// written here before anything held it, and `apps:` and `loaded:` were
    /// defaulting the whole time; `EveryEngineNamesItsPortsTests` holds it now.
    private func files(shared: Bool) -> LeftoversFakeFiles {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["\(label).plist"]
        files.plists[path] = PlistData(["Label": label])
        if shared {
            files.listing["/Library/LaunchAgents"] = ["\(label).plist"]
            files.plists["/Library/LaunchAgents/\(label).plist"] = PlistData(["Label": label])
        }
        return files
    }

    private func send(_ toggle: LeftoversToggle, to engine: LeftoversEngine) async throws {
        _ = try await engine.transport.send(
            EngineCommand(name: LeftoversCommand.setDisabled.rawValue,
                          payload: try JSONEncoder().encode(toggle)))
    }

    /// **The finding, at the port that acts.** Two files, one label, no switch.
    func testTheEngineWillNotDisableALabelTwoFilesRegister() async throws {
        let recorder = LeftoversFakeSwitcher()
        let engine = LeftoversEngine(home: home, files: files(shared: true),
                                     apps: LeftoversFakeApps(), loaded: LeftoversFakeLoaded(),
                                     switcher: recorder)

        try await send(LeftoversToggle(label: label, path: path, disabled: true), to: engine)

        XCTAssertEqual(recorder.labels, [], """
            the engine sent `launchctl disable gui/<uid>/\(label)` for a request naming \
            one of two files that register that label. Which of the two launchd kept is \
            not something this app has read — that needs a `launchctl print` port it does \
            not have — so the press stops whichever it was, including the job the same \
            scan reports as in use.
            """)
    }

    /// **The control.** The same request with nobody else claiming the label goes
    /// through, or the guard has closed the feature rather than the hole.
    func testTheEngineStillDisablesALabelOnlyOneFileRegisters() async throws {
        let recorder = LeftoversFakeSwitcher()
        let engine = LeftoversEngine(home: home, files: files(shared: false),
                                     apps: LeftoversFakeApps(), loaded: LeftoversFakeLoaded(),
                                     switcher: recorder)

        try await send(LeftoversToggle(label: label, path: path, disabled: true), to: engine)

        XCTAssertEqual(recorder.labels, [label])
    }

    /// And the reading is the disk's, not the request's: a request naming the
    /// *other* copy is refused by the same fact.
    func testEitherOfTheTwoFilesIsRefused() async throws {
        let recorder = LeftoversFakeSwitcher()
        let engine = LeftoversEngine(home: home, files: files(shared: true),
                                     apps: LeftoversFakeApps(), loaded: LeftoversFakeLoaded(),
                                     switcher: recorder)

        try await send(LeftoversToggle(label: label,
                                       path: "/Library/LaunchAgents/\(label).plist",
                                       disabled: true), to: engine)

        XCTAssertEqual(recorder.labels, [])
    }

    /// The rule itself, over the shape that made it necessary: a job registered by
    /// one file has one claimant, and a `Label` a *second* file carries — under any
    /// name — makes two.
    ///
    /// Read off `LaunchClaims` rather than off the scan, because this is the half
    /// the engine uses and the scan's half is `OneLabelIsOneSwitchTests`.
    func testALabelIsClaimedByWhateverRegistersIt() {
        let claims = LaunchClaims.onDisk(home: home, files: files(shared: true))

        XCTAssertEqual(LaunchClaims.claimants(of: label, in: claims).count, 2)
        XCTAssertEqual(LaunchClaims.claimants(of: "com.other.agent", in: claims), [])
        // An unlabelled job takes its name from its file, so «no label» is never a
        // claim two files can share — counted together, every such job would be a
        // rival of every other and the switch would vanish from the page.
        XCTAssertEqual(LaunchClaims.claimants(of: "", in: claims), [])
    }

    /// A daemon of the same name is not a second claim: it loads in the system
    /// domain, which `launchctl disable gui/<uid>/…` does not reach.
    func testADaemonOfTheSameNameIsNotASecondClaimOnTheSwitch() throws {
        var files = files(shared: false)
        files.listing["/Library/LaunchDaemons"] = ["\(label).plist"]
        files.plists["/Library/LaunchDaemons/\(label).plist"] = PlistData(["Label": label])

        let agent = try XCTUnwrap(LeftoversScanner(home: home, files: files,
                                                   apps: LeftoversFakeApps(),
                                                   extensions: LeftoversFakeLoaded())
            .scan().first { $0.kind == .launchAgent })

        XCTAssertNil(agent.labelAlsoClaimedBy)
        XCTAssertTrue(agent.canToggle, "the daemon is a different job in a different domain")
        XCTAssertEqual(LaunchClaims.agentFolders(home: home).count, 2,
                       "and the folders the question is asked of are the user's two")
    }
}
