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
/// Per-app rule lists in Keep Awake (`KeepAwakeAppRules.swift`) and Layout
/// (`LayoutLists.swift`) draw this row. Drawn per module the rows drift: one
/// hides the icon from VoiceOver and another does not (hiding is right; the
/// name is beside it, so reading the icon aloud says the app's name twice), one
/// adds vertical padding and another does not, and the remove button's label
/// is written out at each site in the same shape and checked against none of
/// the others.
///
/// The controls stay the caller's business. What a rule *is* differs by module
/// — on/off, a condition, a VPN and a timing — and the row has no opinion
/// about that; what it owns is the geometry and the two accessibility
/// decisions that would otherwise be made once per list.
///
/// It lives here rather than in a module because `AppInfo` does: this file and
/// that one answer the same question, "what is this bundle id called and what
/// does it look like".
public struct HelmAppRuleRow<Controls: View, Note: View>: View {
    private let info: (name: String, icon: NSImage)
    private let controls: Controls
    private let note: Note
    private let remove: () -> Void

    /// `note` is a line under the row, empty unless the caller passes one;
    /// neither list passes one today. It is a slot rather than something the
    /// caller wraps around the row, because a row wrapped at each site is how
    /// per-module copies drift.
    public init(bundleID: String,
                @ViewBuilder controls: () -> Controls,
                @ViewBuilder note: () -> Note = { EmptyView() },
                remove: @escaping () -> Void) {
        self.info = AppInfo.resolve(bundleID)
        self.controls = controls()
        self.note = note()
        self.remove = remove
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: HelmAppRuleGeometry.iconGap) {
                Image(nsImage: info.icon)
                    .resizable().frame(width: HelmAppRuleGeometry.iconSide, height: HelmAppRuleGeometry.iconSide)
                    // The name is the next thing in the row, so reading the
                    // icon aloud says the application twice.
                    .accessibilityHidden(true)
                Text(info.name).lineLimit(1)
                Spacer(minLength: 12)
                controls
                Button(action: remove) {
                    // A cross, not a filled minus. The minus is the sign macOS
                    // puts under a list — the button that removes the *selected*
                    // row — and there is one of these per row, which is the
                    // other gesture entirely.
                    Image(systemName: "xmark").foregroundStyle(HelmText.faint)
                }
                .buttonStyle(.plain)
                // Which app this removes. A list of these offered VoiceOver
                // five identical buttons called "remove".
                .accessibilityLabel("\(HelmA11y.remove), \(info.name)")
            }
            note
        }
        // No extra vertical padding. Measured on a Form-based page, not
        // re-measured in a card: an app row came out 55 pt where every other
        // plain row was 35–37, so one card of five read as visibly looser than
        // its neighbours. Ten of those points were vertical padding on the row.
    }
}
