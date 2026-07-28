import SwiftUI

/// One application in a list of per-app rules: its icon, its name, whatever
/// controls the module needs, and a way to take it off the list.
///
/// Three modules keep such a list — Keep Awake, VPN and Keyboard — and each
/// drew this row for itself. They had already drifted in three places: only
/// Keyboard hid the icon from VoiceOver (which is right; the name is beside
/// it, so reading the icon aloud says the app's name twice), only VPN added
/// vertical padding, and the remove button's label was written out at each
/// site in the same shape but never checked against the others.
///
/// The controls stay the caller's business. What a rule *is* differs by module
/// — on/off, a condition, a VPN and a timing — and the row has no opinion
/// about that; what it owns is the geometry and the two accessibility
/// decisions that were being made three times.
///
/// It lives here rather than in a module because `AppInfo` does: this file and
/// that one answer the same question, "what is this bundle id called and what
/// does it look like".
public struct HelmAppRuleRow<Controls: View, Note: View>: View {
    private let info: (name: String, icon: NSImage)
    private let controls: Controls
    private let note: Note
    private let remove: () -> Void

    /// `note` is a line under the row — VPN puts a warning there when the rule
    /// points at a connection that no longer exists. It is a separate slot
    /// rather than something the caller wraps around the row, because the
    /// wrapping is what made VPN's copy diverge.
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
            HStack(spacing: 10) {
                Image(nsImage: info.icon)
                    .resizable().frame(width: 22, height: 22)
                    // The name is the next thing in the row, so reading the
                    // icon aloud says the application twice.
                    .accessibilityHidden(true)
                Text(info.name).lineLimit(1)
                Spacer(minLength: 12)
                controls
                Button(action: remove) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(HelmText.quiet)
                }
                .buttonStyle(.plain)
                // Which app this removes. A list of these offered VoiceOver
                // five identical buttons called "remove".
                .accessibilityLabel("\(HelmA11y.remove), \(info.name)")
            }
            note
        }
        .padding(.vertical, 5)
    }
}
