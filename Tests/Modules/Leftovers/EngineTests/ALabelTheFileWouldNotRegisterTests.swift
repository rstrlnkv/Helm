import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Leftovers_Engine

/// **The row acts on the label of the job a file defines, not on whatever label
/// the file claims.**
///
/// `LaunchAgentReader.read` takes `Label` verbatim — rightly, it is reading a
/// document — and that string is both what the row offers «Turn off» for and what
/// reaches `launchctl` as the service target. launchd's convention is that a
/// job's file is named after its label: a file called `zz-innocent.plist` whose
/// `Label` is `com.securityvendor.agent` must not be switchable, or the press
/// runs `launchctl disable` and `bootout` against the **real** job of that name.
///
/// Deception rather than escalation — the attacker needs write access to a
/// LaunchAgents folder either way — but Helm-shaped, and with no undo on screen.
/// The offer and the engine both refuse: a view model is not the last word on
/// somebody's login items (Architecture/Removal.md § Removal).
final class ALabelTheFileWouldNotRegisterTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")
    private let victim = "com.securityvendor.agent"

    private func agent(file: String, label: String) throws -> StaleItem {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = [file]
        files.plists["/Users/x/Library/LaunchAgents/\(file)"] =
            PlistData(["Label": label, "Program": "/Applications/Gone.app/Contents/MacOS/x"])
        return try firstAgent(home: home, files: files)
    }

    /// **The guard.** A file wearing somebody else's label is not offered the switch.
    func testAnAgentWearingAnotherJobsLabelIsNotOfferedTheSwitch() throws {
        let item = try agent(file: "zz-innocent.plist", label: victim)

        XCTAssertEqual(item.status, .orphaned,
                       "precondition: an ordinary leftover row, not one another rule protects")
        XCTAssertFalse(item.canToggle, """
            the row offers «Turn off» for «\(item.identifier)» on the strength of a `Label` key in \
            `zz-innocent.plist` — and the press aims `launchctl disable gui/<uid>/\(victim)` at the \
            real job of that name, which is a different file entirely. A label is the file's own \
            only when the file is named after it, which is launchd's own convention.
            """)
    }

    /// The control: the ordinary shape, which every real login item has and which
    /// must keep its switch.
    func testAnAgentNamedAfterItsOwnLabelKeepsTheSwitch() throws {
        let item = try agent(file: "com.vendor.updater.plist", label: "com.vendor.updater")

        XCTAssertTrue(item.canToggle,
                      "a fix that takes «Turn off» off every row would pass the test above")
        XCTAssertEqual(item.actions.contains(.turnOff), item.canToggle,
                       "the two answers are one answer, or they will part")
    }

    /// A job that omits `Label` altogether takes its name from the file, which is
    /// launchd's own reading — so it is its own label by definition.
    func testAJobWithNoLabelOfItsOwnKeepsTheSwitch() throws {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.vendor.updater.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.vendor.updater.plist"] =
            PlistData(["Program": "/Applications/Gone.app/Contents/MacOS/x"])
        let items = LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                                     extensions: LeftoversFakeLoaded()).scan()

        XCTAssertTrue(try XCTUnwrap(items.first).canToggle)
    }

    // MARK: - The engine's own last word

    /// The agent this Mac is *not* asked about.
    ///
    /// **Every port is named at every construction** (`EveryEngineNamesItsPortsTests`):
    /// `ActiveExtensions` shells out to `launchctl print-disabled gui/$(getuid())`,
    /// so a defaulted port would make these answers facts about whoever ran the
    /// suite (Architecture/TestsAndMeasurement.md § Fakes).
    private var switchable: LeftoversFakeFiles {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.vendor.updater.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.vendor.updater.plist"] =
            PlistData(["Label": "com.vendor.updater"])
        return files
    }

    private func send(_ toggle: LeftoversToggle, to engine: LeftoversEngine) async {
        await engine.setDisabled(toggle)
    }

    /// The page is not the guard. A request naming a label that is not the one its
    /// file would register is refused by the engine, whoever asked.
    func testTheEngineRefusesALabelThatIsNotTheFilesOwn() async throws {
        let recorder = LeftoversFakeSwitcher()
        let engine = LeftoversEngine(home: home, files: switchable, apps: LeftoversFakeApps(),
                                     loaded: LeftoversFakeLoaded(), switcher: recorder,
                                     store: freshLeftoversStore())

        await send(LeftoversToggle(label: victim,
                                   path: "/Users/x/Library/LaunchAgents/zz-innocent.plist",
                                   disabled: true), to: engine)

        XCTAssertEqual(recorder.labels, [], """
            the engine passed «\(victim)» to `launchctl` because a request said so — and a request \
            is built by a view model, which `RemovableScope`'s doc comment calls the wrong \
            place for the last word.
            """)
    }

    /// And it still switches the ordinary row, or the guard has closed the feature
    /// rather than the hole.
    func testTheEngineStillSwitchesAJobUnderItsOwnName() async throws {
        let recorder = LeftoversFakeSwitcher()
        let engine = LeftoversEngine(home: home, files: switchable, apps: LeftoversFakeApps(),
                                     loaded: LeftoversFakeLoaded(), switcher: recorder,
                                     store: freshLeftoversStore())

        await send(LeftoversToggle(label: "com.vendor.updater",
                                   path: "/Users/x/Library/LaunchAgents/com.vendor.updater.plist",
                                   disabled: true), to: engine)

        XCTAssertEqual(recorder.labels, ["com.vendor.updater"])
    }

    /// A path that is in no LaunchAgents folder defines no user agent at all, whatever
    /// it is called — so a request carrying one is not a switch request.
    func testTheEngineRefusesAPathThatDefinesNoLoginItem() async throws {
        let recorder = LeftoversFakeSwitcher()
        let engine = LeftoversEngine(home: home, files: switchable, apps: LeftoversFakeApps(),
                                     loaded: LeftoversFakeLoaded(), switcher: recorder,
                                     store: freshLeftoversStore())

        await send(LeftoversToggle(label: "com.vendor.updater",
                                   path: "/tmp/com.vendor.updater.plist",
                                   disabled: true), to: engine)

        XCTAssertEqual(recorder.labels, [])
    }
}
