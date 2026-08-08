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

    /// Keeps `state` on whether Full Disk Access has been granted: once as the
    /// page appears, and again every time Helm comes back to the front, which is
    /// how it hears about a grant made in System Settings.
    ///
    /// Five settings pages carried the same `@State`, the same
    /// `.helmOnAppActive` and the same line inside their own `.task`. The note
    /// itself stays at the call site — each module says what the missing grant
    /// costs *there*, and those sentences are the part that differs.
    ///
    /// The probe is `PermissionCheck.fullDiskAccess()`, which is four blocking
    /// file reads and says at its own declaration why it does them off the
    /// cooperative pool.
    func helmTracksFullDiskAccess(_ state: Binding<PermissionState>) -> some View {
        task { state.wrappedValue = await PermissionCheck.fullDiskAccess() }
            // A `Task` rather than the synchronous read this replaced: the
            // answer lands a hop later than it used to, and the note with it.
            // Measured offscreen against the old wiring — the page settles at
            // the same height, and only the first frame differs.
            .helmOnAppActive {
                Task { @MainActor in state.wrappedValue = await PermissionCheck.fullDiskAccess() }
            }
    }
}
