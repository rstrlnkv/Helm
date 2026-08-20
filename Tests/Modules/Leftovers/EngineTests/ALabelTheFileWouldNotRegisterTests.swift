import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **The row acts on the label the file claims, not on the label of the job that
/// file defines.**
///
/// `LaunchAgentReader.read` takes `Label` verbatim — rightly, it is reading a
/// document — and that string is then both what the row offers «Turn off» for and
/// what reaches `launchctl` as the service target. launchd's own convention is that
/// a job's file is named after its label, and nothing checked it: a file called
/// `zz-innocent.plist` whose `Label` is `com.securityvendor.agent` comes back
/// orphaned, switchable and removable, and the press runs `launchctl disable` and
/// `bootout` against the **real** job of that name.
///
/// Deception rather than escalation — the attacker needs write access to a
/// LaunchAgents folder either way — but Helm-shaped, and with no undo on screen.
/// The offer and the engine are both fixed, because the offer is what a person sees
/// and the engine is what acts: a view model is not allowed to be the last word on
/// what happens to somebody's login items, the same rule `RemovableScope` states one
/// verb over (ARCHITECTURE.md § Removal scope).
final class ALabelTheFileWouldNotRegisterTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")
    private let victim = "com.securityvendor.agent"

    private func agent(file: String, label: String) throws -> StaleItem {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = [file]
        files.plists["/Users/x/Library/LaunchAgents/\(file)"] =
            PlistData(["Label": label, "Program": "/Applications/Gone.app/Contents/MacOS/x"])
        let items = LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                                     extensions: LeftoversFakeLoaded()).scan()
        return try XCTUnwrap(items.first { $0.kind == .launchAgent },
                            "precondition: the agent is listed at all")
    }

    /// **The finding.** A file wearing somebody else's label is offered the switch.
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

    /// A switch port that records what it was asked and does nothing.
    private final class Recorder: LoginItemSwitchPort, @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String] = []
        func setDisabled(_ disabled: Bool, label: String) {
            lock.lock(); defer { lock.unlock() }
            seen.append(label)
        }
        var labels: [String] {
            lock.lock(); defer { lock.unlock() }
            return seen
        }
    }

    /// The agent this Mac is *not* asked about.
    ///
    /// **The port is named at every construction.** `LeftoversEngine`'s `files:`
    /// defaults to `FileSystemLeftovers`, and the engine reads the two LaunchAgents
    /// folders before it switches anything (`LaunchClaims`) — so a forgetful
    /// construction here would make these three answers facts about whoever runs
    /// the suite (CLAUDE.md: a default argument naming a real port makes every
    /// forgetful construction an integration test).
    private var switchable: LeftoversFakeFiles {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.vendor.updater.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.vendor.updater.plist"] =
            PlistData(["Label": "com.vendor.updater"])
        return files
    }

    private func send(_ toggle: LeftoversToggle, to engine: LeftoversEngine) async throws {
        _ = try await engine.transport.send(
            EngineCommand(name: LeftoversCommand.setDisabled.rawValue,
                          payload: try JSONEncoder().encode(toggle)))
    }

    /// The page is not the guard. A request naming a label that is not the one its
    /// file would register is refused by the engine, whoever asked.
    func testTheEngineRefusesALabelThatIsNotTheFilesOwn() async throws {
        let recorder = Recorder()
        let engine = LeftoversEngine(home: home, files: switchable, switcher: recorder)

        try await send(LeftoversToggle(label: victim,
                                       path: "/Users/x/Library/LaunchAgents/zz-innocent.plist",
                                       disabled: true), to: engine)

        XCTAssertEqual(recorder.labels, [], """
            the engine passed «\(victim)» to `launchctl` because a request said so — and a request \
            is built by a view model, which ARCHITECTURE.md § Removal scope says may not be the \
            last word on what is done to somebody's machine.
            """)
    }

    /// And it still switches the ordinary row, or the guard has closed the feature
    /// rather than the hole.
    func testTheEngineStillSwitchesAJobUnderItsOwnName() async throws {
        let recorder = Recorder()
        let engine = LeftoversEngine(home: home, files: switchable, switcher: recorder)

        try await send(LeftoversToggle(label: "com.vendor.updater",
                                       path: "/Users/x/Library/LaunchAgents/com.vendor.updater.plist",
                                       disabled: true), to: engine)

        XCTAssertEqual(recorder.labels, ["com.vendor.updater"])
    }

    /// A path that is in no LaunchAgents folder defines no user agent at all, whatever
    /// it is called — so a request carrying one is not a switch request.
    func testTheEngineRefusesAPathThatDefinesNoLoginItem() async throws {
        let recorder = Recorder()
        let engine = LeftoversEngine(home: home, files: switchable, switcher: recorder)

        try await send(LeftoversToggle(label: "com.vendor.updater",
                                       path: "/tmp/com.vendor.updater.plist",
                                       disabled: true), to: engine)

        XCTAssertEqual(recorder.labels, [])
    }
}
