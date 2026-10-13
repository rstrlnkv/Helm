import AppKit
import SwiftUI
import XCTest
@testable import HelmUI

/// **The `HelmToolbarActionsCapsule` that a `helm.actions` item's view hosts, read back from the view.**
///
/// `SettingsToolbar.actionsHost(_:for:)` hosts the capsule under two environment writes (the look and the
/// switcher's cell), so the item's view is an `NSHostingView` of a `ModifiedContent` and not of the capsule's
/// own type: `item.view as? NSHostingView<HelmToolbarActionsCapsule>` answers nil whatever the bar holds, and a
/// reader that folds that nil into "the button is not shown" reads a bar with no capsule as a bar with a
/// hidden button. This reader walks the root's value types (structs, optionals, enums, tuples; the walk stops
/// at a reference type, whose fields are somebody's state and not a view's description) and answers the
/// capsule value it meets first, with its `model` and `reserveWidth(_:)` as the page declared them.
///
/// **Each way of not finding it fails with a sentence that says which**: no item, no view, a view with no
/// stored root, a root with no capsule in it. The sentence is recorded as a failure at the caller's line
/// before the error is thrown: on the `async throws` rows that read through this reader, a log that held a
/// thrown error of this kind held, in its place and across four lines, `caught error: "InvalidTransition {`,
/// `phase: idle`, `targetPhase: failed(deinit)`, `}"` at `<unknown>:0`, and nothing of the sentence the error
/// carried. Only the recorded failure names the sentence and the caller's line.
@MainActor
enum ActionsCapsuleReading {

    struct Unread: Error {
        let description: String
    }

    struct Read {
        let host: NSView
        let capsule: HelmToolbarActionsCapsule
    }

    /// The view of `toolbar`'s `helm.actions` item and the capsule in it. `context` leads each sentence.
    static func read(_ toolbar: NSToolbar, context: String,
                     file: StaticString = #filePath, line: UInt = #line) throws -> Read {
        guard let item = SettingsWindowRig.item("helm.actions", in: toolbar) else {
            throw unread("\(context): the toolbar has no helm.actions item: its items are "
                         + "\(toolbar.items.map(\.itemIdentifier.rawValue))", file, line)
        }
        guard let host = item.view else {
            throw unread("\(context): the helm.actions item has no view", file, line)
        }
        return Read(host: host, capsule: try capsule(inHost: host, context: context, file: file, line: line))
    }

    /// The capsule in an item's view. Fails when the view stores no root or when the root holds no capsule.
    static func capsule(inHost host: NSView, context: String,
                        file: StaticString = #filePath, line: UInt = #line) throws -> HelmToolbarActionsCapsule {
        guard let root = Mirror(reflecting: host).children.first(where: { $0.label == "_rootView" })?.value else {
            throw unread("\(context): no readable root: the actions item's view is a "
                         + "\(type(of: host)) with no stored root", file, line)
        }
        guard let capsule = firstCapsule(in: root, depth: 0) else {
            throw unread("\(context): no capsule: the walk of the root, a \(type(of: root)), "
                         + "met no HelmToolbarActionsCapsule", file, line)
        }
        return capsule
    }

    private static func unread(_ sentence: String, _ file: StaticString, _ line: UInt) -> Unread {
        XCTFail(sentence, file: file, line: line)
        return Unread(description: sentence)
    }

    private static func firstCapsule(in value: Any, depth: Int) -> HelmToolbarActionsCapsule? {
        guard depth < 12 else { return nil }
        if let capsule = value as? HelmToolbarActionsCapsule { return capsule }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle != .class else { return nil }
        for child in mirror.children {
            if let found = firstCapsule(in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }
}
