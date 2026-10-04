import AppKit
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **What the two red order tests cannot reach.** `TheShareHandsOffFirstAndOpensAtTheShotTests.testTheMenusShareItemIsLastEnabledKeylessAndSendsTheShareExit`
/// and `TheMenuChecksTheToolInUseTests.testThePinIsInTheMenuOnlyWhileOfferedAndAfterSave` stand red over where the tail of the
/// ⋯ menu ends (an open choice between two tracks), and each returns at its first failure, so what they say of the items
/// themselves goes unasked: Share… is enabled for every tool, carries no key, sends the share exit through the NSMenu and is
/// titled in every language; the Pin is a plain enabled item sending the pin exit, straight after Save. Asked here **by title, not by
/// position in the tail**, so the order the owner picks changes none of it, and while the two stay red these still guard the items.
///
/// Synchronous: nothing awaits.
@MainActor
final class TheShareAndPinItemsOfTheMenuWhateverTheOrderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppLanguage.override = .en
    }

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private func model(tool: AnnotationTool?) -> EditorBarModel {
        let model = EditorBarModel()
        model.show(tool: tool, style: AnnotationStyle(), canUndo: false, canRedo: false)
        return model
    }

    private func actions(_ items: [EditorMenuItem], titled title: String) -> [(action: EditorAction, enabled: Bool, on: Bool)] {
        items.compactMap {
            if case .action(let t, let action, let enabled, let on) = $0, t == title { (action, enabled, on) } else { nil }
        }
    }

    func testShareIsThereOnceEnabledAndSendsTheShareExitForEveryToolAndEveryPinState() {
        var seen = 0
        for pinOffered in [false, true] {
            for tool in [nil] + AnnotationTool.allCases.map({ Optional($0) }) {
                let found = actions(EditorMenu.items(for: model(tool: tool), pinOffered: pinOffered), titled: ScStr.share)
                XCTAssertEqual(found.count, 1, "Share… is not in the menu once for tool \(String(describing: tool)), pin \(pinOffered)")
                XCTAssertEqual(found.first?.action, .exit(.share))
                XCTAssertEqual(found.first?.enabled, true, "Share… is off for tool \(String(describing: tool))")
                XCTAssertEqual(found.first?.on, false)
                seen += 1
            }
        }
        XCTAssertEqual(seen, 2 * (AnnotationTool.allCases.count + 1), "the control: every case was asked")
    }

    func testShareInTheRealMenuCarriesNoKeyAndSendsTheShareExit() throws {
        var sent: [EditorAction] = []
        let m = model(tool: .arrow)
        m.perform = { sent.append($0) }
        let menu = EditorMenu.make(for: m)
        menu.delegate?.menuNeedsUpdate?(menu)
        let items = menu.items.filter { $0.title == ScStr.share }
        XCTAssertEqual(items.count, 1, "the control: one Share… in the NSMenu")
        let item = try XCTUnwrap(items.first)
        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(item.keyEquivalent, "", "Share… has a key")
        menu.performActionForItem(at: menu.index(of: item))
        XCTAssertEqual(sent, [.exit(.share)])
        AppLanguage.each { language in
            XCTAssertFalse(ScStr.share.isEmpty, "\(language)")
            XCTAssertNotEqual(ScStr.share, ScStr.save, "\(language)")
        }
    }

    func testThePinIsAPlainEnabledItemThatSendsThePinExitAndStandsStraightAfterSave() throws {
        for tool in [nil] + AnnotationTool.allCases.map({ Optional($0) }) {
            let items = EditorMenu.items(for: model(tool: tool), pinOffered: true)
            let pins = actions(items, titled: ScStr.pin)
            XCTAssertEqual(pins.count, 1, "the control: one Pin for tool \(String(describing: tool))")
            XCTAssertEqual(pins.first?.action, .exit(.pin))
            XCTAssertEqual(pins.first?.enabled, true)
            XCTAssertEqual(pins.first?.on, false)
            let at = try XCTUnwrap(items.firstIndex { if case .action(let t, _, _, _) = $0 { t == ScStr.pin } else { false } })
            guard at > 0, case .action(let before, _, _, _) = items[at - 1] else { return XCTFail("nothing before the Pin is an action") }
            XCTAssertEqual(before, ScStr.save, "the Pin does not stand straight after Save for tool \(String(describing: tool))")
            XCTAssertFalse(actions(EditorMenu.items(for: model(tool: tool), pinOffered: false), titled: ScStr.pin).isEmpty == false, "the Pin is offered when it is not")
        }
    }
}
