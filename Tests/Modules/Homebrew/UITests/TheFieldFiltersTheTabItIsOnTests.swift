import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **One field, three tabs, one rule.**
///
/// The owner's decision, 2026-09-22: the search field filters whichever list
/// is on screen, on every tab, by the same substring rule — `ListFilter`'s own
/// doc comment. This file holds that rule per tab, and the one consequence
/// that follows from filtering a list a selection and a pending ask can both
/// point into: a row the filter hides is a row that stops being selected, and
/// dropping the selection is what retires an uninstall ask still out over the
/// wire (`HomebrewViewModel.reconcileVisible`'s own doc comment).
@MainActor
final class TheFieldFiltersTheTabItIsOnTests: XCTestCase {

    private final class Fake: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        var installed: [BrewPackage] = []
        var outdated: [OutdatedPackage] = []
        var issues: [DoctorIssue] = []
        var config: [ConfigLine] = []
        var descriptions: [String: String] = [:]
        /// Held until the test releases it — a fake that answered at once
        /// would make the mutation this file guards against unreachable: the
        /// ask would be over before the filter ever moved (CLAUDE.md § What
        /// not to do, and what breaks if you do).
        private let lock = NSLock()
        private var dependentsAsked = 0
        private let gate = DispatchSemaphore(value: 0)
        var dependentsAskCount: Int { lock.withLock { dependentsAsked } }
        func releaseDependents() { gate.signal() }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode(installed)
            case .outdated: return try JSONEncoder().encode(outdated)
            case .doctor: return try JSONEncoder().encode(issues)
            case .config:
                return try JSONEncoder().encode(BrewConfig(lines: config, text: ""))
            case .descriptions:
                guard let req = try? JSONDecoder().decode(DescriptionsRequest.self,
                                                          from: command.payload)
                else { return try JSONEncoder().encode([String: String]()) }
                let answer = req.names.reduce(into: [String: String]()) { acc, name in
                    let key = BrewKey.of(name: name, isCask: req.isCask)
                    if let d = descriptions[key] { acc[name] = d }
                }
                return try JSONEncoder().encode(answer)
            case .dependents:
                lock.withLock { dependentsAsked += 1 }
                // Off the cooperative pool the way the real wait is: a
                // semaphore parked inside an `async` function would hold one
                // of its threads.
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().async { self.gate.wait(); c.resume() }
                }
                return try JSONEncoder().encode([String]())
            default: return Data()
            }
        }
    }

    // MARK: - Installed

    func testInstalledFiltersByNameAndByDescription() async {
        let fake = Fake()
        fake.installed = [BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false),
                          BrewPackage(name: "wget", version: "1.25.0", isCask: false)]
        fake.descriptions = [BrewKey.of(name: "wget", isCask: false): "Grabs a cup of Café"]
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: fake))
        await vm.loadIfNeeded()

        vm.query = "SSL"
        XCTAssertEqual(vm.shownInstalled.map(\.name), ["openssl@3"],
                       "a case-insensitive substring of the name did not match")

        vm.query = "cafe"
        XCTAssertEqual(vm.shownInstalled.map(\.name), ["wget"],
                       "a diacritic-insensitive substring of the description did not match")

        vm.query = "   "
        XCTAssertEqual(vm.shownInstalled.count, 2, "a whitespace-only query must show everything")
    }

    // MARK: - Updates

    func testUpdatesFiltersTheSameWay() async {
        let fake = Fake()
        fake.outdated = [OutdatedPackage(name: "node", installed: "26.8.2", latest: "26.9.0",
                                         isCask: false),
                         OutdatedPackage(name: "git", installed: "2.54.0", latest: "2.55.0",
                                        isCask: false)]
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: fake))
        await vm.loadIfNeeded()
        await vm.refreshOutdated()

        vm.query = "node"
        XCTAssertEqual(vm.shownOutdated.map(\.name), ["node"])
        vm.query = ""
        XCTAssertEqual(vm.shownOutdated.count, 2)
    }

    // MARK: - Health

    func testHealthFiltersFindingsByTitleAndBody() async {
        let fake = Fake()
        fake.issues = [DoctorIssue(severity: .caution, title: "Xcode CLT out of date",
                                   body: "run xcode-select --install"),
                      DoctorIssue(severity: .danger, title: "Something else entirely",
                                 body: "nothing to do with the first one")]
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: fake))
        await vm.loadIfNeeded()
        await vm.refreshDoctor()

        vm.query = "xcode"
        XCTAssertEqual(vm.shownIssues.map(\.title), ["Xcode CLT out of date"])
    }

    func testHealthFiltersConfigGroupsByALineValue() async {
        let fake = Fake()
        fake.config = [ConfigLine(key: "HOMEBREW_VERSION", value: "7.0.1", section: .brew),
                      ConfigLine(key: "macOS", value: "27.0-arm64", section: .machine)]
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: fake))
        await vm.loadIfNeeded()
        await vm.refreshConfig()

        vm.query = "7.0.1"
        XCTAssertEqual(vm.shownConfigGroups.map(\.section), [.brew],
                       "a group matching on one line's value kept the group whole")
        vm.query = "arm64"
        XCTAssertEqual(vm.shownConfigGroups.map(\.section), [.machine])
    }

    /// A finding hidden by the filter must read as "no match", never as
    /// "clean" — `brew doctor` never even asked about that word.
    func testFilteredOutFindingsReadAsNoMatchesNeverClean() async {
        let fake = Fake()
        fake.issues = [DoctorIssue(severity: .caution, title: "A real finding", body: "…")]
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: fake))
        await vm.loadIfNeeded()
        await vm.refreshDoctor()

        let filtered = HealthScreen.of(vm.doctor, config: vm.configGroups,
                                       needle: ListFilter.needle("zzqqnope"))
        XCTAssertEqual(filtered, .sentence(.noMatches), """
            \(filtered) — a finding the filter hides must not be reported as "Nothing to \
            fix", which is a claim about the machine and not about the query
            """)
    }

    // MARK: - Selection dropped when the filter hides the row

    /// Selecting openssl, then typing a word that hides it, drops the
    /// selection at once — and takes a fresh token from `uninstallAsks`, so
    /// the dependents answer that was already out when the filter moved lands
    /// on nothing rather than raising the app's only irreversible deletion
    /// over a list that no longer shows the package.
    func testAFilteredOutSelectionRetiresAPendingAskEvenAfterItAnswers() async {
        let fake = Fake()
        fake.installed = [BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false),
                          BrewPackage(name: "wget", version: "1.25.0", isCask: false)]
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: fake))
        await vm.loadIfNeeded()

        vm.select(BrewKey.of(name: "openssl@3", isCask: false))
        let asking = Task {
            await vm.askToUninstall(BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false))
        }
        while fake.dependentsAskCount < 1 { try? await Task.sleep(for: .milliseconds(5)) }

        vm.query = "wget"
        XCTAssertNil(vm.selected, "a row the filter hides must stop being selected at once")

        // The held answer arrives *after* the filter moved — the case the
        // token exists for.
        fake.releaseDependents()
        await asking.value

        XCTAssertNil(vm.pendingUninstall, """
            an uninstall ask still out when the filter hid its row landed anyway and raised \
            the dialog over a package the list no longer shows
            """)
    }

    // MARK: - What is installed is not offered again

    /// The one place a hit already on this Mac is excluded — by `BrewKey` id,
    /// never by name. `docker` is both a formula and a cask, so an installed
    /// formula must not hide an offered cask of the same name, and the
    /// reverse.
    func testWhatIsInstalledIsNeverOfferedAgain() {
        let installedFormula = BrewPackage(name: "docker", version: "1.0.0", isCask: false)
        let hits = [SearchHit(name: "wget", isCask: false),      // already installed
                   SearchHit(name: "docker", isCask: true),     // its formula is installed, not it
                   SearchHit(name: "ripgrep", isCask: false)]   // not installed at all
        let installed = [BrewPackage(name: "wget", version: "1.25.0", isCask: false), installedFormula]

        let shown = PackageStanding.notInstalled(hits, installed: installed)

        XCTAssertEqual(shown.map(\.id), [SearchHit(name: "docker", isCask: true).id,
                                         SearchHit(name: "ripgrep", isCask: false).id], """
            \(shown.map(\.name)) — the installed formula `docker` must not have hidden the \
            cask hit of the same name, and an installed hit must still be excluded
            """)
    }
}
