import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import HelmUI
import Observation
import SwiftUI
import XCTest
import Module_Homebrew_Engine
@testable import Module_Homebrew_UI
@testable import HelmApp

/// **The three places a tab switch can pick up a curve that
/// `EveryTabSwitchIsACutTests` does not look at.** The owner's rule is the one
/// that file holds — «вкладки везде переключаются резко», 2026-09-30.
///
/// - **The writer.** The shared guard writes the page's `selectedTab` binding
///   itself. A person's press reaches that binding through `SettingsToolbar`'s
///   own binding and `HelmToolbarSwitcher`'s coordinator, and a
///   `withAnimation` anywhere on that path animates every page at once while
///   the guard stays green. Here the press is the control's own action, sent
///   to the real toolbar, and what is read is the transaction the page's
///   update arrived in.
/// - **What the switch asked for.** The shared guard parks the wire for the
///   length of its photograph, so the answer a shown tab asks its engine for
///   lands after it; here that landing is photographed too.
/// - **Homebrew wide with a selection on both sides**, in both appearances and
///   both directions, which the page's own case takes one way and in light only.
@MainActor
final class ATabSwitchIsACutEndToEndTests: XCTestCase {

    private static let width: CGFloat = 984
    private static let height: CGFloat = 700

    private static func pump(_ view: NSView?, turns: Int) {
        for _ in 0..<turns {
            view?.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: - The writer

    @Observable
    final class TabBox {
        var tab = "a"
    }

    /// Reads the transaction every change of `box.tab` arrives in.
    private struct Probe: View {
        let box: TabBox
        let heard: (Bool) -> Void
        var body: some View {
            Text(box.tab)
                .transaction(value: box.tab) { transaction in heard(transaction.animation != nil) }
        }
    }

    /// **A press on a segment of the real toolbar changes the page in a
    /// transaction with no animation.** The control is found in the window's
    /// `NSToolbar`, its selection moved and its own action sent — the call a
    /// click ends in — so every layer between the press and the page's binding
    /// is the shipping one.
    func testAPressOnTheToolbarReachesThePageWithoutACurve() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window

        let box = TabBox()
        var heard: [Bool] = []
        let host = NSHostingView(rootView: Probe(box: box) { heard.append($0) }.helmMeasuringBench())
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 40)
        let probeWindow = NSWindow(contentRect: host.frame, styleMask: [.titled],
                                   backing: .buffered, defer: false)
        probeWindow.contentView = host
        Self.pump(host, turns: 5)

        // **The instrument first**: a write inside `withAnimation` is heard as
        // animated, and a plain one as not. Without this, a probe that never
        // hears an animation passes every mutant.
        withAnimation(HelmMotion.interface) { box.tab = "c" }
        Self.pump(host, turns: 5)
        XCTAssertEqual(heard.last, true, "the probe did not hear a write inside withAnimation as animated (\(heard))")
        box.tab = "a"
        Self.pump(host, turns: 5)
        XCTAssertEqual(heard.last, false, "the probe heard a plain write as animated (\(heard))")
        heard = []

        let binding = Binding(get: { box.tab }, set: { box.tab = $0 })
        let content = HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "a", title: "A", symbol: "circle"),
                   HelmToolbarTab(id: "b", title: "B", symbol: "square")],
            selectedTab: binding, actions: [], search: nil)
        model.selection = .module("test.cut")
        channel.declare(content, token: "test.cut", generation: channel.nextGeneration())
        window.layoutIfNeeded()
        Self.pump(window.contentView, turns: 5)

        let bar = try XCTUnwrap(window.toolbar)
        let tabsItem = try XCTUnwrap(bar.items.first { $0.itemIdentifier.rawValue == "helm.tabs" })
        let control = try XCTUnwrap(tabsItem.view?.everyView(ofType: NSSegmentedControl.self).first,
                                    "no NSSegmentedControl under the tabs item")
        XCTAssertEqual(control.segmentCount, 2, "the switcher is folded, so a press opens a menu instead")

        for (index, id) in [(1, "b"), (0, "a"), (1, "b")] {
            control.selectedSegment = index
            XCTAssertTrue(control.sendAction(control.action, to: control.target),
                          "the control's own action went nowhere")
            Self.pump(host, turns: 5)
            // The subject before the absence: the press reached the page.
            XCTAssertEqual(box.tab, id, "the press on segment \(index) did not reach the page's binding")
        }
        print("[transactions] toolbar press → page: \(heard)")
        XCTAssertEqual(heard.count, 3, "the page heard \(heard.count) changes for three presses")
        XCTAssertFalse(heard.contains(true), """
            a press on the toolbar's switcher reached the page inside an animated transaction \
            (\(heard)) — every page's tab switch rides that curve whatever the page itself says
            """)
        _ = toolbar
    }

    // MARK: - What the switch asked for

    /// **The answer a shown tab asks for lands without a curve.** Every module
    /// page with tabs, every switch: the wire is parked for the switch (as the
    /// shared guard does), the page settles, then the wire is let go and what
    /// arrives is photographed and judged by the same bound, counted from the
    /// first frame the answer changed. An arrival that changes nothing is not
    /// judged; at least one must change the drawing, or this case photographed
    /// no arrival at all. With `ModulePageFixtures`' wire only Homebrew's
    /// answers change the drawing — every `[frames]` line says which did.
    func testWhatASwitchAskedForArrivesWithoutACurve() throws {
        var arrivals = 0
        var pages: Set<String> = []
        for descriptor in ModuleRegistry.all {
            let id = type(of: descriptor).id.rawValue
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let channel = HelmWindowToolbarChannel()
                let page = ModulePageRender.page(for: descriptor, in: appearance, width: Self.width,
                                                 declaringTo: channel)
                page.host.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
                Self.pump(page.host, turns: 40)
                defer { page.host.window?.contentView = nil }
                guard let content = channel.content(for: id), content.tabs.count > 1,
                      let tabs = content.selectedTab else { continue }
                pages.insert(id)
                let screen = RenderedInk.label(of: appearance)
                let start = tabs.wrappedValue
                for target in content.tabs.map(\.id).filter({ $0 != start }) + [start] {
                    page.transport.hold()
                    tabs.wrappedValue = target
                    Self.pump(page.host, turns: 40)
                    let before = try XCTUnwrap(RenderedInk.bytes(page.host))
                    let began = Date()
                    page.transport.release()
                    let shots = try FrameRecorder.photograph(page.host, since: began)
                    let label = "\(screen), \(id) arrival after → \(target)"
                    FrameRecorder.write(shots, of: page.host,
                                        named: "arrival-\(id)-\(target)-\(appearance.rawValue)")
                    guard let settled = shots.last?.pixels, settled != before else {
                        print("[frames] \(label): nothing arrived that changed the drawing")
                        continue
                    }
                    arrivals += 1
                    // **Timed from the first frame the answer reached, not from
                    // the release.** Letting the wire go resumes a parked call,
                    // which hops through a task and the view model before
                    // anything draws, so the turns before the first changed
                    // frame are the answer still travelling. What must not
                    // follow that frame is a curve: after one grace turn, every
                    // frame is the settled one.
                    let reached = try XCTUnwrap(shots.firstIndex { $0.pixels != before })
                    let account = shots.enumerated().filter { $0.element.pixels != settled }
                        .map { "#\($0.offset)@\(Int($0.element.at * 1000))ms" }
                    print("[frames] \(label): reached at #\(reached), \(account.count)/\(shots.count) unsettled \(account)")
                    let moving = shots.dropFirst(reached + FrameRecorder.grace).filter { $0.pixels != settled }
                    XCTAssertEqual(moving.count, 0, """
                        \(label): \(moving.count) frames after the answer reached the page (#\(reached)) \
                        and one grace turn were not the settled drawing, the last at \
                        \(Int((moving.last?.at ?? 0) * 1000)) ms — what the tab asked for arrived on a curve
                        """)
                }
            }
        }
        XCTAssertFalse(pages.isEmpty, "no module page declared tabs")
        XCTAssertGreaterThan(arrivals, 0, """
            no switch on \(pages.sorted()) asked for anything that changed the drawing when it \
            arrived, so this case photographed nothing
            """)
    }

    // MARK: - Homebrew wide, a selection on both sides

    func testHomebrewWideSegmentsWithASelectionOnBothSidesCut() throws {
        let stale = OutdatedPackage(name: "fixture-formula", installed: "1.2.3",
                                    latest: "1.3.0", isCask: false, pinned: false)
        let wiring: ModulePageRender.Wiring = { id in
            var wire = ModulePageRender.answering(id)
            if id == HomebrewDescriptor.id.rawValue {
                wire.answers(HomebrewCommand.outdated, with: [stale])
            }
            return wire
        }
        let descriptor = try XCTUnwrap(ModuleRegistry.all.first { $0.idRaw == HomebrewDescriptor.id.rawValue })
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let channel = HelmWindowToolbarChannel()
            let page = ModulePageRender.page(for: descriptor, in: appearance, width: Self.width,
                                             wiredBy: wiring, declaringTo: channel)
            page.host.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
            Self.pump(page.host, turns: 40)
            defer { page.host.window?.contentView = nil }
            let screen = RenderedInk.label(of: appearance)
            let hb = HomebrewViewModel.shared(vm: page.viewModel)
            let tabs = try XCTUnwrap(channel.content(for: HomebrewDescriptor.id.rawValue)?.selectedTab)
            // Each segment once, and a selection in the two that list packages.
            for segment in ["updates", "health", "installed"] {
                tabs.wrappedValue = segment
                Self.pump(page.host, turns: 40)
            }
            hb.select(try XCTUnwrap(hb.installed.first?.id, "no installed package to select"))
            Self.pump(page.host, turns: 40)
            tabs.wrappedValue = "updates"
            Self.pump(page.host, turns: 40)
            hb.select(try XCTUnwrap(hb.outdated.first?.id, "no outdated package to select"))
            Self.pump(page.host, turns: 40)
            XCTAssertNotNil(hb.selected, "\(screen): precondition: nothing selected on Updates")

            for (step, target) in ["installed", "updates", "health", "installed", "health", "updates"].enumerated() {
                let before = try XCTUnwrap(RenderedInk.bytes(page.host))
                page.transport.hold()
                let began = Date()
                tabs.wrappedValue = target
                let shots = try FrameRecorder.photograph(page.host, since: began)
                FrameRecorder.write(shots, of: page.host, named: "brew-wide-sel-\(step)-\(target)-\(appearance.rawValue)")
                try FrameRecorder.judge(shots, before: before,
                                        "\(screen), homebrew wide (selected both sides) → \(target)")
                page.transport.release()
                Self.pump(page.host, turns: 40)
                if target != "health" {
                    XCTAssertNotNil(hb.selected, "\(screen): the selection on \(target) was lost")
                }
            }
        }
    }
}
