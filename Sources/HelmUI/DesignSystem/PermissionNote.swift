import SwiftUI
import AppKit
import Combine
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
            Button(Self.grantLabel) { openSettings() }
                .controlSize(.small)
        }
    }

    /// The verb, where an empty state can read it too: a page whose whole
    /// content is «this needs a permission» draws the same word on a prominent
    /// button rather than inventing a second one for the same act.
    public static var grantLabel: String {
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

    /// Keeps `state` on whether Accessibility has been granted: once as the page
    /// appears, and again every time Helm comes back to the front, which is how
    /// it hears about a grant made in System Settings.
    ///
    /// The twin of `helmTracksFullDiskAccess`, and it existed as three hand-held
    /// lines in the two modules that need this grant — the `@State`, the `.task`
    /// and the `.helmOnAppActive` — with nothing to keep the two copies agreeing
    /// about which of the three they had.
    ///
    /// Synchronous, unlike the disk probe: `AXIsProcessTrusted()` is one
    /// non-blocking call and needs no hop, so the answer is there on the first
    /// frame rather than one later.
    func helmTracksAccessibility(_ state: Binding<PermissionState>,
                                 alsoOn extra: Notification.Name? = nil) -> some View {
        modifier(HelmAccessibilityTracker(state: state, extra: extra))
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
    func helmTracksFullDiskAccess(_ state: Binding<PermissionState>,
                                  alsoOn extra: Notification.Name? = nil) -> some View {
        modifier(HelmFullDiskTracker(state: state, extra: extra))
    }

    /// Keeps `state` on whether Screen Recording has been granted: once as the
    /// page appears, and again every time Helm comes back to the front — which is
    /// how it hears about a grant made in System Settings, where the person
    /// went to make it.
    ///
    /// Synchronous like Accessibility's, for the same reason: the probe is
    /// `CGPreflightScreenCaptureAccess`, one non-blocking call that answers from
    /// the process's own grant and raises no dialog.
    func helmTracksScreenRecording(_ state: Binding<PermissionState>,
                                   alsoOn extra: Notification.Name? = nil) -> some View {
        modifier(HelmScreenRecordingTracker(state: state, extra: extra))
    }
}

/// The `.task` and the «Helm came back to the front» re-read, in one place.
private struct HelmAccessibilityTracker: ViewModifier {
    let state: Binding<PermissionState>
    let extra: Notification.Name?

    func body(content: Content) -> some View {
        content
            .task { state.wrappedValue = answer }
            .helmOnAppActive { state.wrappedValue = answer }
            .onReceive(HelmGrantRefresh.publisher(extra)) { _ in state.wrappedValue = answer }
    }

    private var answer: PermissionState {
        PermissionCheck.currentAccessibility()
    }
}

private struct HelmScreenRecordingTracker: ViewModifier {
    let state: Binding<PermissionState>
    let extra: Notification.Name?

    func body(content: Content) -> some View {
        content
            .task { state.wrappedValue = answer }
            .helmOnAppActive { state.wrappedValue = answer }
            .onReceive(HelmGrantRefresh.publisher(extra)) { _ in state.wrappedValue = answer }
    }

    private var answer: PermissionState {
        PermissionCheck.currentScreenRecording()
    }
}

/// The same three lines for the other grant.
///
/// The probe stays asynchronous, unlike Accessibility's: four blocking file reads
/// belong off the cooperative pool.
private struct HelmFullDiskTracker: ViewModifier {
    let state: Binding<PermissionState>
    let extra: Notification.Name?

    func body(content: Content) -> some View {
        content
            .task { state.wrappedValue = await answer() }
            // A `Task` rather than the synchronous read this replaced: the answer
            // lands a hop later than it used to, and the note with it. Measured
            // offscreen against the old wiring — the page settles at the same
            // height, and only the first frame differs.
            .helmOnAppActive {
                Task { @MainActor in state.wrappedValue = await answer() }
            }
            .onReceive(HelmGrantRefresh.publisher(extra)) { _ in
                Task { @MainActor in state.wrappedValue = await answer() }
            }
    }

    private func answer() async -> PermissionState {
        await PermissionCheck.fullDiskAccess()
    }
}

/// The extra moment a caller can add to the two the trackers already keep.
///
/// «Helm came back to the front» is the moment a settings page hears about a
/// grant given in System Settings, and it is not the panel's: `PanelWindow`
/// takes key focus without activating the app on purpose, so a panel opened
/// from the menu-bar icon never sees `didBecomeActive`. Without a moment of its
/// own the panel would read the grants once, at launch, and go on drawing that
/// answer for the life of the process — which is the reading older than the act
/// CLAUDE.md names, in the surface most exposed to it.
///
/// A publisher rather than an `if` around `onReceive`: a `ViewModifier` cannot
/// branch on the shape of its body without changing the view's identity, and a
/// tracker that rebuilt its subtree when a caller passed nil would be a worse
/// bug than the one it fixes.
private enum HelmGrantRefresh {
    static func publisher(_ name: Notification.Name?) -> AnyPublisher<Notification, Never> {
        guard let name else { return Empty().eraseToAnyPublisher() }
        return NotificationCenter.default.publisher(for: name).eraseToAnyPublisher()
    }
}
