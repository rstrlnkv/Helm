import SwiftUI
import AppKit
import HelmRuntime

/// The one way Helm says "this needs a permission you have not given".
///
/// It goes next to the control it is about, not only in the settings list: a
/// switch that macOS ignores looks exactly like a switch that works, and the
/// person flipping it is the one who needs to know.
public struct HelmPermissionNote: View {
    private let text: String
    private let openSettings: () -> Void

    public init(need: PermissionNeed, text: String) {
        self.init(text: text, openSettings: need.openSettings)
    }

    /// For a grant that is not a `PermissionNeed`: notifications are asked for
    /// through macOS's own API and answered by it, so there is nothing for
    /// `PermissionCheck` to probe — only a pane to send the person to.
    public init(text: String, openSettings: @escaping () -> Void) {
        self.text = text
        self.openSettings = openSettings
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(HelmSignal.warning)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                // Literal, not `.secondary`: these notes appear inside blocks
                // that animate in, and hierarchical styles re-resolve there.
                .foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(Self.grant) { openSettings() }
                .controlSize(.small)
        }
    }

    private static var grant: String {
        L("Grant…")
    }
}

public extension View {
    /// Runs when Helm comes back to the front — the moment to re-read anything
    /// the user may have changed in System Settings while away.
    func helmOnAppActive(_ action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in action() }
    }
}
