import AppKit
import ObjectiveC
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A window of a `swift test` process made key the way the capsule family makes one, and the two-control bar
/// content the families that need a key bar declare.** No window of this process is shown or key, and a stock
/// `NSSegmentedControl` draws its selection grey until its window is key. `install(in:)` replaces the getters
/// of `isKeyWindow` and `isMainWindow` so that they answer for a registered window and with AppKit's own answer
/// for every other; `setKey(_:_:)` records the answer, runs AppKit's private `acquireMainAppearance` /
/// `acquireKeyAppearance` (or `resignKeyAppearance` / `resignMainAppearance`) on the window, and posts the
/// notifications its observers wait for. The getters are put back by the test's teardown.
///
/// **Whether the seam works is not decided here.** `TheBarDrawsNoAccentInAKeyWindowTests`'
/// `testTheKeySeamMakesAStockControlDrawTheAccent` photographs a bare stock control not key and then key; red
/// there, every row that calls `setKey` proves nothing. `TheCapsuleDrawsWhatAppKitsPlatterDrawsTests` and
/// `ADisabledActionDimsAsAppKitsOwnButtonTests` keep their own copies of this seam.
@MainActor
enum AKeyWindowTheWindowServerDoesNotGive {

    nonisolated(unsafe) private static var answers: [ObjectIdentifier: Bool] = [:]

    /// Swizzles the two getters for the length of `test`; call it before the first `setKey` of a test. A second
    /// call in the same test is harmless while no window is still key: it empties the answers table, and the
    /// teardowns put the getters back in reverse order.
    static func install(in test: XCTestCase) throws {
        answers = [:]
        for selector in [#selector(getter: NSWindow.isKeyWindow), #selector(getter: NSWindow.isMainWindow)] {
            let method = try XCTUnwrap(class_getInstanceMethod(NSWindow.self, selector),
                                       "NSWindow has no \(selector) to answer for")
            let original = method_getImplementation(method)
            typealias Getter = @convention(c) (NSWindow, Selector) -> Bool
            let call = unsafeBitCast(original, to: Getter.self)
            let answering: @convention(block) (NSWindow) -> Bool = { window in
                AKeyWindowTheWindowServerDoesNotGive.answers[ObjectIdentifier(window)] ?? call(window, selector)
            }
            method_setImplementation(method, imp_implementationWithBlock(answering))
            test.addTeardownBlock { method_setImplementation(method, original) }
        }
        test.addTeardownBlock { AKeyWindowTheWindowServerDoesNotGive.answers = [:] }
    }

    /// One key change on `window`: the flag, AppKit's own appearance calls, the notifications. Becoming
    /// key runs main before key, resigning runs key before main.
    static func setKey(_ on: Bool, _ window: NSWindow, file: StaticString = #filePath, line: UInt = #line) {
        answers[ObjectIdentifier(window)] = on
        XCTAssertEqual(window.isKeyWindow, on, "the window server stand-in does not answer isKeyWindow",
                       file: file, line: line)
        XCTAssertEqual(window.isMainWindow, on, "the window server stand-in does not answer isMainWindow",
                       file: file, line: line)
        let names = on ? ["acquireMainAppearance", "acquireKeyAppearance"]
                       : ["resignKeyAppearance", "resignMainAppearance"]
        for name in names {
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(type(of: window), selector) else {
                XCTFail("NSWindow no longer answers \(name): the stand-in for the window server is gone",
                        file: file, line: line)
                return
            }
            typealias Call = @convention(c) (AnyObject, Selector) -> Void
            unsafeBitCast(method_getImplementation(method), to: Call.self)(window, selector)
        }
        let posted = on ? [NSWindow.didBecomeMainNotification, NSWindow.didBecomeKeyNotification]
                        : [NSWindow.didResignKeyNotification, NSWindow.didResignMainNotification]
        for name in posted { NotificationCenter.default.post(name: name, object: window) }
    }

    /// Two centre tabs with a glyph each.
    static func tabs() -> [HelmToolbarTab] {
        [HelmToolbarTab(id: "first", title: "Alpha", symbol: "circle"),
         HelmToolbarTab(id: "second", title: "Beta", symbol: "square")]
    }

    /// One segmented action, the view-mode switcher of two glyphs, the first selected.
    static func viewMode() -> HelmToolbarAction {
        HelmToolbarAction(id: "viewMode", title: "View", options: [
            HelmToolbarTab(id: "first", title: "First", symbol: "minus"),
            HelmToolbarTab(id: "second", title: "Second", symbol: "ellipsis"),
        ], selection: .constant("first"))
    }
}
