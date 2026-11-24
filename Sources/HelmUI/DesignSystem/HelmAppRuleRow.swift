import SwiftUI

/// The icon's side and the gap after it. Apart from the row because a generic
/// type cannot hold a stored constant; a row that sits in the same list (an
/// «Add app…» row) takes the numbers from here, so the two agree.
public enum HelmAppRuleGeometry {
    public static let iconSide: CGFloat = 22
    public static let iconGap = HelmSpace.s5
}

/// One application in a list of per-app rules: its icon, its name, whatever
/// controls the module needs, and a way to take it off the list.
///
/// One row for every per-app rule list, so the geometry and the two
/// accessibility decisions are made once: the icon hidden from VoiceOver, the
/// name beside it already saying it, and the remove button named for its app.
/// The controls stay the caller's: what a rule *is* differs by module. It lives
/// beside `AppInfo`, which answers the same question about a bundle id.
public struct HelmAppRuleRow<Controls: View>: View {
    private let info: (name: String, icon: NSImage)
    private let controls: Controls
    private let remove: () -> Void

    public init(bundleID: String,
                @ViewBuilder controls: () -> Controls,
                remove: @escaping () -> Void) {
        self.info = AppInfo.resolve(bundleID)
        self.controls = controls()
        self.remove = remove
    }

    public var body: some View {
        HStack(spacing: HelmAppRuleGeometry.iconGap) {
            Image(nsImage: info.icon)
                .resizable().frame(width: HelmAppRuleGeometry.iconSide, height: HelmAppRuleGeometry.iconSide)
                // The name is the next thing in the row, so reading the
                // icon aloud says the application twice.
                .accessibilityHidden(true)
            Text(info.name).lineLimit(1)
            Spacer(minLength: 12)
            controls
            // Which app this removes, or a list of these offers VoiceOver
            // identical buttons called "remove".
            HelmRemoveButton(label: "\(HelmA11y.remove), \(info.name)", action: remove)
        }
            // No extra vertical padding: it made an app row far taller than the
            // plain rows beside it.
    }
}

/// The button that takes one row off a list: a faint cross, not a filled minus. The minus is the sign macOS puts
/// under a list — the button that removes the *selected* row — and there is one of these per row, which is the other
/// gesture entirely. `label` is what VoiceOver reads, as given.
public struct HelmRemoveButton: View {
    public let label: String
    let target: CGFloat?
    let action: () -> Void
    /// `target` is the side of a square hit area round the cross, for a page whose pointer has to hit a glyph a few
    /// points wide; without it the button is the glyph.
    public init(label: String, target: CGFloat? = nil, action: @escaping () -> Void) {
        self.label = label
        self.target = target
        self.action = action
    }
    public var body: some View {
        Button(action: action) {
            if let target {
                Image(systemName: "xmark").foregroundStyle(HelmText.faint)
                    .frame(minWidth: target, minHeight: target)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: "xmark").foregroundStyle(HelmText.faint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
