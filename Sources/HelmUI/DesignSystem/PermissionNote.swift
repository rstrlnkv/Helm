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
/// It is a `HelmBanner`, a mark, a note and a button in one field, so the two
/// shapes cannot drift.
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
        // one notice that macOS itself draws, and the panel's permissions widget
        // uses this glyph for it.
        HelmBanner(text, symbol: "exclamationmark.circle.fill") {
            Button(Self.grantLabel) { openSettings() }
                .controlSize(.small)
        }
    }

    /// The verb, where an empty state can read it too: a page whose whole
    /// content is «this needs a permission» draws the same word on a prominent
    /// button rather than inventing a second one for the same act.
    public static var grantLabel: String { L(.grant) }
}

extension View {
    /// Runs when Helm comes back to the front — the moment to re-read anything
    /// the user may have changed in System Settings while away.
    public func helmOnAppActive(_ action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in action() }
    }

    /// Keeps `state` on whether Accessibility has been granted: once as the page
    /// appears, and again every time Helm comes back to the front, which is how
    /// it hears about a grant made in System Settings.
    ///
    /// Synchronous, unlike the disk probe: `AXIsProcessTrusted()` is one
    /// non-blocking call, so the answer is there on the first frame.
    public func helmTracksAccessibility(_ state: Binding<PermissionState>,
                                 alsoOn extra: Notification.Name? = nil) -> some View {
        modifier(HelmAccessibilityTracker(state: state, extra: extra))
    }

    /// Keeps `state` on whether Full Disk Access has been granted: once as the
    /// page appears, and again every time Helm comes back to the front, which is
    /// how it hears about a grant made in System Settings.
    ///
    /// The note itself stays at the call site: each module says what the
    /// missing grant costs there. The probe is `PermissionCheck.fullDiskAccess()`,
    /// four blocking file reads, which says at its declaration why it runs off
    /// the cooperative pool.
    public func helmTracksFullDiskAccess(_ state: Binding<PermissionState>,
                                  alsoOn extra: Notification.Name? = nil) -> some View {
        modifier(HelmFullDiskTracker(state: state, extra: extra))
    }

    /// Keeps `state` on whether Screen Recording has been granted: once as the
    /// page appears, and again every time Helm comes back to the front.
    ///
    /// Synchronous like Accessibility's, for the same reason: the probe is
    /// `CGPreflightScreenCaptureAccess`, one non-blocking call that answers from
    /// the process's own grant and raises no dialog.
    public func helmTracksScreenRecording(_ state: Binding<PermissionState>,
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

/// The same three lines for Full Disk Access, asynchronous because the probe is
/// four blocking file reads.
private struct HelmFullDiskTracker: ViewModifier {
    let state: Binding<PermissionState>
    let extra: Notification.Name?

    func body(content: Content) -> some View {
        content
            .task { state.wrappedValue = await answer() }
            // A `Task`: the answer lands a hop later, and only the first frame
            // differs.
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
/// «Helm came back to the front» is when a settings page hears about a grant
/// given in System Settings, but not the panel: `PanelWindow` takes key focus
/// without activating the app, so it never sees `didBecomeActive`. Without a
/// moment of its own the panel would draw the launch-time answer for the life
/// of the process, a reading older than the act (ARCHITECTURE.md § The gates).
///
/// A publisher rather than an `if` around `onReceive`: a `ViewModifier` that
/// branched on its body's shape would change the view's identity.
private enum HelmGrantRefresh {
    static func publisher(_ name: Notification.Name?) -> AnyPublisher<Notification, Never> {
        guard let name else { return Empty().eraseToAnyPublisher() }
        return NotificationCenter.default.publisher(for: name).eraseToAnyPublisher()
    }
}
