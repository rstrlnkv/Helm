import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Состояние waited without moving.**
///
/// `brew doctor` is the slowest query in the module, and `refresh` asks
/// `brew config` first on purpose so the Configuration heading is on screen
/// while the Checkup one is still saying what it is waiting for. That is exactly
/// the case `HealthScreen.of` turns into a *row*: a note under the Checkup
/// heading rather than the centred `HelmBusyState`. Measured 2026-09-16 at the
/// pane the app draws: «Проверка этого Mac…» was a plain 36 pt text row with
/// **no progress indicator anywhere on the page**, while every other wait in
/// this module and in the app spins — and the refusal row beside it was the same
/// grey row in the same place, differing only in its sentence.
///
/// So: the wait moves and the refusal does not, and the two are not one drawing.
@MainActor
final class TheHealthWaitMovesTests: XCTestCase {

    /// Answers `brew config` — which is what puts the note in a row rather than
    /// in the centre of the pane — and either hangs on `brew doctor` or refuses
    /// it.
    private final class Clinic: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        enum Doctor { case hanging, refusing }
        let doctor: Doctor
        init(doctor: Doctor) { self.doctor = doctor }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode([BrewPackage]())
            case .config:
                return try JSONEncoder().encode(
                    BrewConfig(lines: [ConfigLine(key: "HOMEBREW_VERSION", value: "7.0.1", section: .brew)],
                               text: "HOMEBREW_VERSION: 7.0.1"))
            case .doctor:
                if doctor == .hanging { try await Task.sleep(nanoseconds: 60_000_000_000) }
                throw CancellationError()
            default:
                return Data()
            }
        }
    }

    private struct Reading {
        let spinners: Int
        let picture: Data?
    }

    private func health(_ doctor: Clinic.Doctor) async -> Reading {
        let transport = Clinic(doctor: doctor)
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: 984, height: 520, appearance: .aqua)
        let loading = Task { @MainActor in await hb.loadIfNeeded() }
        hb.segment = .health
        let asking = Task { @MainActor in
            await hb.refreshConfig()
            await hb.refreshDoctor()
        }
        for _ in 0..<80 {
            mount.host.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
        let spinners = mount.host.everyView(ofType: NSProgressIndicator.self).count
        // The list's own band, not the page: the status line below it is not
        // part of this claim and differs for reasons of its own, which would
        // make two pages differ whatever the Checkup row said
        // (`RenderedInk.bytes`).
        let picture = mount.pixels(60...420)
        mount.drop()
        _ = loading
        _ = asking
        withExtendedLifetime(transport) {}
        return Reading(spinners: spinners, picture: picture)
    }

    func testTheCheckupWaitMovesAndItsRefusalDoesNot() async {
        let waiting = await health(.hanging)
        let refused = await health(.refusing)

        XCTAssertGreaterThan(waiting.spinners, 0, """
            Состояние is waiting on `brew doctor` and there is nothing moving on the page — the \
            slowest query in the module, spending a minute behind a still grey row
            """)
        XCTAssertEqual(refused.spinners, 0, """
            the refused Checkup is still drawing \(refused.spinners) progress indicator(s), and \
            nothing is on its way: `brew doctor` answered and the answer was a refusal
            """)
        XCTAssertNotNil(waiting.picture)
        XCTAssertNotEqual(waiting.picture, refused.picture, """
            waiting for `brew doctor` and being refused by it are drawn pixel for pixel the \
            same, which is the defect said in one sentence
            """)
    }
}
