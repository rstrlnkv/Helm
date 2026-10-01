import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **«Open Settings» is on the toast when the screen cannot be read, and only
/// then.** A button that cannot do what it says is worse than none: a full disk
/// is not fixed in the Privacy pane. Counted off the rendered tree, where a
/// control drawn by SwiftUI is a focus-ring view. Every refusal also carries the
/// close control (`TheRefusalToastCanBeSentAwayTests`), so the counts are the
/// button plus that one: 2 with the grant missing, 1 otherwise.
@MainActor
final class TheRefusalToastOffersSettingsOnlyForAMissingGrantTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private func buttons(for reason: CaptureRefusal, language: AppLanguage) -> Int {
        AppLanguage.override = language
        let model = ShotToastModel()
        model.content = ShotToast.refusalContent(reason)
        model.shown = true
        let mount = MountedRender(ShotToastView(model: model), width: ShotToast.width, height: 300, appearance: .aqua)
        mount.settle(20)
        return mount.host.everyView(named: "_FocusRingView").count
    }

    func testOnlyAMissingGrantOffersTheButton() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(buttons(for: .noPermission, language: language), 2, "\(language): no Open Settings (beside the close control) on a missing grant")
            for other in [CaptureRefusal.write(.diskFull), .captureFailed, .displayGone, .windowGone, .pasteboard, .encoding,
                          .write(.noPermission), .write(.noFolder)] {
                XCTAssertEqual(buttons(for: other, language: language), 1, "\(language): \(other) offered a Privacy button")
            }
        }
    }

    func testEveryRefusalHasASentenceOfItsOwn() {
        let all: [CaptureRefusal] = [.noPermission, .captureFailed, .displayGone, .windowGone, .pasteboard, .encoding,
                                     .write(.noFolder), .write(.notAFolder), .write(.noPermission), .write(.diskFull),
                                     .write(.namesExhausted), .write(.failed(5))]
        AppLanguage.each { language in
            let sentences = Set(all.map { ScStr.refusal($0) })
            // noFolder/notAFolder share a sentence and so do namesExhausted/failed: ten, not twelve.
            XCTAssertEqual(sentences.count, 10, "\(language): two different refusals read the same")
            XCTAssertFalse(sentences.contains(""), "\(language): a refusal has no words")
        }
    }
}
