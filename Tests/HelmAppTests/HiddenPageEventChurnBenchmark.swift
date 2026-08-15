import XCTest
import SwiftUI
import AppKit
import Darwin
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp
@testable import Module_VPN_Engine
import Module_VPN_UI

/// What one engine state event costs a page that is mounted but not on screen —
/// the state every Helm window is in for most of its life.
///
/// The panel's `NSHostingView` is built at the first toggle and never torn
/// down: `HelmPanel.hide()` is `orderOut(nil)` (PanelWindow.swift), and
/// `SettingsWindow` keeps its content behind `isReleasedWhenClosed = false`.
/// So every engine emission — and the owner's log shows VPN auto-connect
/// cycles emitting all night — reaches a live SwiftUI tree in a hidden
/// window, re-renders it, and pays whatever that render allocates.
///
/// Measured on the installed 0.10.0-dev.7 (pid 92600, 2026-08-15, `heap`):
/// 3 766 live `ObservationTracking` dictionaries, 63 462 `Set<AnyKeyPath>`,
/// 77 134 closure contexts at rest, growing by +70 trackings / +1 190 keypath
/// sets / +372 KB over seven minutes of idle — a ratchet nobody's phase names.
/// This file reproduces the per-event half in-process, against the allocator's
/// books (`size_in_use`), never `phys_footprint` — the house rule from
/// `HashCacheScaleBenchmark`.
///
/// `HELM_BENCH=1 swift test --filter HiddenPageEventChurnBenchmark`
@MainActor
final class HiddenPageEventChurnBenchmark: XCTestCase {

    /// Two payloads that genuinely differ, so every event is a real state
    /// change the page has to diff — an emission that changes nothing measures
    /// SwiftUI's short-circuit, not a render. Invented names, the
    /// `ModulePageFixtures` rule: nothing here may read this Mac's tunnels.
    private static func payload(_ up: Bool) -> VPNEngine.StatePayload {
        VPNEngine.StatePayload(
            connections: [
                VPNConnection(id: "bench-1", name: "Bench Amsterdam",
                              status: up ? .connected : .disconnected, kind: "IKEv2"),
                VPNConnection(id: "bench-2", name: "Bench Osaka",
                              status: up ? .disconnected : .connecting, kind: "L2TP"),
            ],
            autoConnected: up ? ["Bench Amsterdam"] : [],
            defaultName: "Bench Amsterdam",
            lastAutomation: nil,
            lastFailure: nil)
    }

    private static func json<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    /// The VPN settings page on a transport this file holds the emitting end
    /// of, in a window that is never ordered in — the hidden panel's shape.
    /// The engine is deliberately never built: `activate()` reaches scutil,
    /// and a measurement has no business shelling out (`ModulePageRender`'s
    /// own rule).
    private func mountedPage() -> (LocalTransport, NSHostingView<AnyView>, NSWindow, ModuleViewModel) {
        let transport = LocalTransport()
        transport.setHandler { _ in Data() }
        transport.emit(EngineEvent(name: VPNEvent.state.rawValue,
                                   payload: Self.json(Self.payload(true))))
        let vm = ModuleViewModel(transport: transport)
        let view = NSHostingView(rootView: AnyView(
            VPNDescriptor().settingsPage(vm)
                .frame(width: HelmLayout.settingsColumn)
                .environment(\.helmGrants, HelmGrants(accessibility: .granted,
                                                      fullDisk: .granted))))
        view.frame = NSRect(x: 0, y: 0, width: HelmLayout.settingsColumn, height: 3000)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        view.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        // Settle: pump until the subscription is live and the first payload has
        // drawn. The page holds connections only after the replayed event lands.
        for _ in 0..<100 {
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return (transport, view, window, vm)
    }

    /// One lap: `count` real state changes, each pumped so SwiftUI acts on it,
    /// each inside a pool so what remains is what was *kept*, not what waits
    /// for a drain (the house `autoreleasepool` rule, applied to the loop).
    private func lap(_ transport: LocalTransport, view: NSView, count: Int, from: Int) {
        for i in 0..<count {
            autoreleasepool {
                transport.emit(EngineEvent(name: VPNEvent.state.rawValue,
                                           payload: Self.json(Self.payload((from + i) % 2 == 0))))
                view.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
            }
        }
    }

    /// Three laps of the same number of events: a leak tracks lap count,
    /// steady-state churn settles. The same protocol as
    /// `HeroTickCostBenchmark.testNoGrowthAcrossSimulatedHoursOfTicking`, with
    /// an event where that file has a tick.
    func testStateEventsAgainstAHiddenPage() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let (transport, view, window, vm) = mountedPage()
        defer { window.contentView = nil; _ = vm }

        let perLap = 300
        // Two warm-up laps: the first fills CoreText/glyph caches, the second
        // proves they settled (HeroTickCostBenchmark's reasoning, kept).
        lap(transport, view: view, count: perLap, from: 0)
        lap(transport, view: view, count: perLap, from: perLap)
        // Six measured laps, because two cannot tell a leak from a cache still
        // filling: a cache's per-lap growth decays to zero, a per-event keep
        // does not.
        var deltas: [Int] = []
        var before = AllocatorBooks.allocatedBytes()
        let warm = before
        for n in 0..<6 {
            lap(transport, view: view, count: perLap, from: perLap * (2 + n))
            let after = AllocatorBooks.allocatedBytes()
            deltas.append(after - before)
            before = after
        }
        print("hidden VPN page, \(perLap) state events per lap: size_in_use "
              + "\(warm / 1024) KB after warm-up; laps "
              + deltas.map { String(format: "+%d KB (%.0f B/event)",
                                    $0 / 1024, Double($0) / Double(perLap)) }
                .joined(separator: ", "))

        // The bound sits in the gap between the two measured sides, the house
        // rule for choosing one. The healthy side is `testFloorWithoutEvents`:
        // the same page, the same pumps, no events — 0 B per lap, three runs.
        // The defective side is this test as first run, 2026-08-15: the last
        // three laps held +2846, +2815 and +2847 B/event (and never less than
        // +2517 across six), so the keep does not decay — it is not a cache.
        // 1000 B/event fails the code as it stands and passes a page that
        // stops keeping its events; when the fix lands, re-measure and record
        // the healthy reading here.
        let lastThree = deltas.suffix(3).reduce(0, +)
        let perEvent = Double(lastThree) / Double(perLap * 3)
        XCTAssertLessThan(perEvent, 1000, String(format:
            "a hidden page kept %.0f bytes per engine state event, sustained across "
            + "laps 4–6 — a night of VPN auto-connect polling (26 emissions per failed "
            + "connect, VPNEngine.pollUntilSettled) reaches every mounted tree at this "
            + "price, and the panel's tree is mounted from first open to quit "
            + "(HelmPanel.hide is orderOut)", perEvent))
    }

    /// The same page, the same laps, no events at all — the harness's own
    /// floor. Whatever the pump and the pools cost regardless of the wire must
    /// not be read as the price of an event.
    func testFloorWithoutEvents() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let (_, view, window, vm) = mountedPage()
        defer { window.contentView = nil; _ = vm }

        func pump(_ count: Int) {
            for _ in 0..<count {
                autoreleasepool {
                    view.layoutSubtreeIfNeeded()
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.002))
                }
            }
        }
        let perLap = 300
        pump(perLap); pump(perLap)
        let afterWarmup = AllocatorBooks.allocatedBytes()
        pump(perLap)
        let afterSecond = AllocatorBooks.allocatedBytes()
        pump(perLap)
        let afterThird = AllocatorBooks.allocatedBytes()
        print(String(format: "hidden VPN page, no events: size_in_use %d KB after warm-up; "
                     + "+%d KB second lap; +%d KB third lap",
                     afterWarmup / 1024, (afterSecond - afterWarmup) / 1024,
                     (afterThird - afterSecond) / 1024))
    }
}
