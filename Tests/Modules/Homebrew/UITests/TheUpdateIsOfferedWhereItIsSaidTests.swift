import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **«Доступно обновление» with nothing on the screen that updates.**
///
/// Measured 2026-09-16 on the Установленные inspector at 984 pt: «Удалить» was
/// 75.5 × 24 at y 61…85 and the line announcing an update sat 12 pt under it at
/// y 97…111, with no control anywhere on the screen that acted on what it said.
/// The upgrade was a segment away — the person had to leave the package they
/// were reading to reach the thing the page had just told them about.
///
/// The capability was never missing: `HomebrewViewModel.upgrade` is the
/// Обновления segment's own action, gated and tested. What was missing was the
/// button beside the sentence.
///
/// **The two actions and the order between them.** The destructive one keeps
/// the title row where it belongs to the name; the constructive one joins the
/// sentence it answers, a row below. A press meant for one cannot land on the
/// other, the uninstall question is untouched, and the weight runs the right
/// way — the marked control is the one that cannot be taken back.
@MainActor
final class TheUpdateIsOfferedWhereItIsSaidTests: XCTestCase {

    nonisolated(unsafe) static let caddy = BrewPackage(name: "caddy", version: "2.11.3",
                                                       isCask: false)
    private static let newer = OutdatedPackage(name: "caddy", installed: "2.11.3",
                                               latest: "2.11.4", isCask: false)
    private static let held = OutdatedPackage(name: "caddy", installed: "2.11.3",
                                              latest: "2.11.4", isCask: false, pinned: true)

    private func subject(outdated: [OutdatedPackage]) -> InspectorSubject? {
        guard case let .package(subject) = InspectorState.of(
            segment: .installed, selected: Self.caddy.id, installed: [Self.caddy],
            outdated: outdated, loadedOutdated: true, hits: [], issues: [], config: [],
            descriptions: [:]) else { return nil }
        return subject
    }

    /// **The fact and whether it can be acted on are one value.** A pinned
    /// formula still has a newer version — the sentence and the row's marker are
    /// unchanged — and `brew upgrade` answers it with "…is pinned", so the
    /// button that would be offered could only ever fail. Both readings are
    /// asserted, or "pinned offers nothing" passes over a page that offers
    /// nothing to anybody.
    func testTheSentenceCarriesWhetherTheUpdateCanBeTaken() {
        XCTAssertEqual(subject(outdated: [Self.newer])?.updates, .available("2.11.4", pinned: false))
        XCTAssertEqual(subject(outdated: [Self.held])?.updates, .available("2.11.4", pinned: true), """
            a formula the person pinned reads as an ordinary update in the inspector, so the \
            button beside the sentence would run a `brew upgrade` that answers "…is pinned"
            """)
        // And a package with no newer version says so rather than saying
        // nothing: the sentence is not drawn at all, and neither is the action.
        XCTAssertEqual(subject(outdated: [])?.updates, .upToDate)
    }

    /// **And on the page the action is in the sentence's own row.**
    ///
    /// Two controls in the inspector where there was one, the second of them
    /// level with the line that announces the update rather than in the title
    /// row above it. The counts are asserted on both sides — a page that drew no
    /// controls at all would pass "the second one is lower down" by default —
    /// and the pinned reading is drawn too, where the count must go back to one.
    func testThePageDrawsTheUpgradeBesideTheSentenceAndNotBesideTheName() async {
        func controls(outdated: [OutdatedPackage]) async -> [CGRect] {
            let transport = OnePackage(outdated: outdated)
            let mvm = ModuleViewModel(transport: transport)
            let hb = HomebrewViewModel.shared(vm: mvm)
            await hb.loadIfNeeded()
            await hb.refreshOutdated()
            hb.select(Self.caddy.id)
            // Light, named: this Mac switches appearance by the sun.
            let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                      width: 984, height: 700, appearance: .aqua)
            mount.settle(30)
            // Below the segment bar, which draws a focus ring of its own
            // wherever the pane is too narrow for the segments — the reason
            // `TheSplitThresholdFitsThePageItGatesTests` bands its own reading.
            let rings = mount.host.everyView(named: "_FocusRingView")
                .map { $0.convert($0.bounds, to: mount.host) }
                .filter { $0.minY >= 48 }
                .sorted { $0.minY < $1.minY }
            mount.drop()
            withExtendedLifetime(transport) {}
            return rings
        }

        let offered = await controls(outdated: [Self.newer])
        XCTAssertEqual(offered.count, 2, """
            the inspector drew \(offered.count) control(s) over a package with an update \
            waiting, where it has to draw the removal and the upgrade — the sentence still \
            announces something nothing on the screen can act on
            """)
        guard offered.count == 2 else { return }
        let removal = offered[0], upgrade = offered[1]
        XCTAssertGreaterThan(upgrade.minY, removal.maxY - 0.5, """
            the upgrade is drawn at y \(upgrade.minY)…\(upgrade.maxY) and the removal at \
            \(removal.minY)…\(removal.maxY) — the two are on one row, where a press meant for \
            the safe one can land on the one that cannot be taken back
            """)
        XCTAssertLessThan(upgrade.minY, removal.maxY + 40, """
            the upgrade is \(upgrade.minY - removal.maxY) pt below the removal — far enough to \
            be somewhere else on the page rather than beside the sentence that announces it
            """)

        let pinned = await controls(outdated: [Self.held])
        XCTAssertEqual(pinned.count, 1, """
            the inspector drew \(pinned.count) control(s) over a formula the person pinned, \
            where the upgrade would fail — only the removal belongs there
            """)
    }

    private final class OnePackage: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        private let outdated: [OutdatedPackage]
        init(outdated: [OutdatedPackage]) { self.outdated = outdated }
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode([TheUpdateIsOfferedWhereItIsSaidTests.caddy])
            case .outdated:
                return try JSONEncoder().encode(outdated)
            default:
                return Data("[]".utf8)
            }
        }
    }
}
