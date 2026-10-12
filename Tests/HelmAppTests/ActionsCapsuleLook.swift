import AppKit
@testable import HelmUI

/// **The look an actions item's hosted root carries**, for a row that has to know that the look it stored
/// reached the bar it reads.
///
/// `SettingsToolbar.actionsHost(_:for:)` writes the look into the capsule's environment, so it sits in the
/// stored root of the item's view; this walks the root's value types the way `ActionsCapsuleReading` does
/// (the walk stops at a reference type, whose fields are somebody's state and not a view's description) and
/// answers every `HelmBarAppearance` it meets, empty when the view stores no root.
extension ActionsCapsuleReading {

    static func looks(in host: NSView) -> [HelmBarAppearance] {
        func walk(_ value: Any, _ depth: Int) -> [HelmBarAppearance] {
            guard depth < 12 else { return [] }
            if let look = value as? HelmBarAppearance { return [look] }
            let mirror = Mirror(reflecting: value)
            guard mirror.displayStyle != .class else { return [] }
            return mirror.children.flatMap { walk($0.value, depth + 1) }
        }
        guard let root = Mirror(reflecting: host).children.first(where: { $0.label == "_rootView" })?.value else { return [] }
        return walk(root, 0)
    }
}
