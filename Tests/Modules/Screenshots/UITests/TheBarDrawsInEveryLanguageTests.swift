import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The bar is drawn in every language and both appearances, every control on
/// it has a name, and the countdown takes the Capture button's place.** Drawn
/// offscreen: the bar is never put on a screen here. The glass does not
/// composite in a render, so what is read is the structure — a size, the ink
/// and the accessibility tree — which is what a missing control or an unnamed
/// one changes.
@MainActor
final class TheBarDrawsInEveryLanguageTests: XCTestCase {

    private let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private func model(countdown: Int? = nil) -> CapturePanelModel {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let model = CapturePanelModel(store: store)
        // A countdown begins from a picked target, so the idle bar it is compared with is the one that offers Capture.
        model.hasTarget = true
        model.countdown = countdown
        return model
    }

    private func mount(_ model: CapturePanelModel, language: AppLanguage,
                       appearance: NSAppearance.Name = .aqua) -> MountedRender {
        AppLanguage.override = language
        let mount = MountedRender(CapturePanelView(model: model), width: 640, height: 120, appearance: appearance)
        mount.settle(20)
        return mount
    }

    /// The bar's own width, the way the real panel asks for it: a hosting view
    /// with nobody telling it how wide to be. (`MountedRender` pins a width, and
    /// a size read from it is the pin.)
    private func naturalSize(_ model: CapturePanelModel, language: AppLanguage) -> CGSize {
        AppLanguage.override = language
        let host = NSHostingView(rootView: CapturePanelView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        return host.fittingSize
    }

    func testTheBarHasSubstanceInEveryLanguageAndAppearance() {
        for language in AppLanguage.allCases {
            for appearance in appearances {
                let render = mount(model(), language: language, appearance: appearance)
                let size = naturalSize(model(), language: language)
                XCTAssertGreaterThan(size.width, 250, "\(language) \(appearance.rawValue): the bar came out \(size.width) pt wide")
                XCTAssertLessThan(size.width, 640, "\(language) \(appearance.rawValue): the bar needs \(size.width) pt, more than the 640 a small screen can spare")
                XCTAssertGreaterThan(size.height, 30, "\(language) \(appearance.rawValue): \(size.height) pt tall")
                XCTAssertGreaterThan(render.ink() ?? 0, 0, "\(language) \(appearance.rawValue): nothing was drawn")
            }
        }
    }

    /// The seconds left are drawn where the button was, and **the bar does not
    /// move at all**: counting and idle lay out to the same size in every
    /// language, so ✕ (the leading control) and both edges stay under the
    /// pointer. A countdown that grows or shrinks the bar by even a point moves
    /// the ✕ the person is about to press. (The ink of two mounts is not compared:
    /// it differs from one mount to the next with nothing changed.)
    func testTheCountdownTakesTheButtonsPlace() {
        AppLanguage.each { language in
            let idle = naturalSize(model(), language: language)
            for seconds in [10, 5, 1] {
                let counting = naturalSize(model(countdown: seconds), language: language)
                XCTAssertEqual(counting.width, idle.width, accuracy: 0.01,
                               "\(language): the bar moved under the pointer as it began to count down from \(seconds)")
                XCTAssertEqual(counting.height, idle.height, accuracy: 0.01, "\(language): \(seconds)")
            }
        }
    }

    /// **Every control on the bar has a name, read from the source.** A render
    /// offscreen publishes no accessibility tree (a walk from the hosting view
    /// finds a group and one text and nothing else), so the one place the defect
    /// can be seen is the declaration: a glyph-only `Button`, and the `Menu`,
    /// must each carry an `.accessibilityLabel`, and a button with a title of its
    /// own is named by it.
    func testEveryControlOnTheBarIsNamedWhereItIsDeclared() throws {
        // The close, mode, timer and gear controls are `GlassCell`, whose button sits in its own file and whose `name:` is
        // its tooltip and its accessibility label; the bar's content is in `CapturePanelView.swift`.
        let source = try ["CapturePanel.swift", "CapturePanelView.swift", "GlassCell.swift"].map {
            try RepoSource.text(of: "Sources/Modules/Screenshots/UI/\($0)")
        }.joined(separator: "\n")
        let lines = source.components(separatedBy: "\n")
        var seen = 0
        for (index, line) in lines.enumerated() {
            let body = line.trimmingCharacters(in: .whitespaces)
            guard body.hasPrefix("Button {") || body.hasPrefix("Button(") || body.hasPrefix("Menu {")
                    || body.hasPrefix("return Button {") || body.hasPrefix("GlassCell(")
                    || body.hasPrefix("return GlassCell(") else { continue }
            seen += 1
            // A button with a title of its own is named by it, and a cell by its `name:`.
            if body.hasPrefix("Button(ScStr.") { continue }
            if body.contains("GlassCell("), body.contains("name:") { continue }
            let indent = line.prefix { $0 == " " }.count
            var statement = line
            for next in lines.dropFirst(index + 1).prefix(60) {
                statement += "\n" + next
                let trimmed = next.trimmingCharacters(in: .whitespaces)
                let ends = !trimmed.isEmpty && next.prefix { $0 == " " }.count <= indent
                    && !trimmed.hasPrefix(".") && !trimmed.hasPrefix("}")
                if ends { break }
            }
            XCTAssertTrue(statement.contains(".accessibilityLabel("),
                          "the control declared at line \(index + 1) of the three files' joined source (CapturePanel, CapturePanelView, GlassCell) has no accessibility label:\n\(statement)")
        }
        XCTAssertGreaterThanOrEqual(seen, 4, "the scan found \(seen) controls — close, mode, Options, Capture are four at least")
    }

    /// Their names are macOS's own words, per language, and no two controls share one.
    func testTheNamesAreDistinctInEveryLanguage() {
        AppLanguage.each { language in
            let names = [ScStr.panelScreen, ScStr.panelWindow, ScStr.panelArea, ScStr.closePanel,
                         ScStr.options, ScStr.captureButton]
            XCTAssertEqual(Set(names).count, names.count, "\(language): two controls on the bar share a name: \(names)")
            XCTAssertFalse(names.contains(where: \.isEmpty), "\(language)")
        }
    }

    /// The bar's own words are the ones the page uses where they mean the same.
    func testTheBarsMenuHoldsEveryOptionTheBriefNames() {
        AppLanguage.each { language in
            let words = [ScStr.saveTo, ScStr.timer, ScStr.floatingThumbnail, ScStr.rememberSelection, ScStr.showCursor]
            XCTAssertEqual(Set(words).count, words.count, "\(language): two options share a name")
            for choice in CaptureTimer.allCases {
                XCTAssertFalse(ScStr.timer(choice).isEmpty)
            }
            XCTAssertEqual(Set(CaptureTimer.allCases.map(ScStr.timer)).count, CaptureTimer.allCases.count, "\(language)")
        }
    }
}
