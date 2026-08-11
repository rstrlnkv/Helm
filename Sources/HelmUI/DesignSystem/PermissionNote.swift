import SwiftUI
import AppKit
import HelmRuntime

/// The one way Helm says "this needs a permission you have not given".
///
/// It goes next to the control it is about, not only in the settings list: a
/// switch that macOS ignores looks exactly like a switch that works, and the
/// person flipping it is the one who needs to know.
///
/// **It is a `HelmBanner`, not a shape of its own.** This was the last pre-v3
/// row left on a settings page: a bare `HStack` of a mark, `.caption` text —
/// 10 pt, where every other note on the same page is 11 — and a button, with no
/// field to say the three were one thing. Which is the description of
/// `HelmBanner` word for word, so the fix was to draw one rather than to restate
/// its numbers here: nine call sites in eight modules became v3 in one edit, and
/// the two shapes cannot drift, because there is one.
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
        // The circle, not the banner's default triangle: a withheld grant is the
        // one notice in the app that macOS itself draws, and the panel's own
        // permissions widget has always used this glyph for it.
        HelmBanner(text, symbol: "exclamationmark.circle.fill") {
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
