import AppKit
import HelmRuntime
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A click on the bar acts on the first press even when the bar is not key.**
/// The bar is a non-activating panel over another app's window; a content view
/// that refuses first mouse spends the first click on becoming key, which on ✕
/// would leave a countdown running after a press. Only the override is provable
/// without a screen — the click itself was not exercised.
@MainActor
final class TheBarActsOnTheFirstClickTests: XCTestCase {
    func testTheBarsContentAcceptsTheFirstMouse() throws {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let panel = CapturePanel(store: store).makePanel()
        let host = try XCTUnwrap(panel.contentView, "the bar has no content")
        XCTAssertTrue(host.acceptsFirstMouse(for: nil), "the first click on the bar is spent on making it key")
    }
}
