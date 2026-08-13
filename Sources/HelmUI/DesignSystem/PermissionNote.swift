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
    ///
    /// **A page that draws a different screen per grant needs a reading that can
    /// name the grant.** `helmGrants` is that, and it is nil everywhere in the
    /// app: the probe is asked, as it always was. Keyboard replaced its banner
    /// with an empty state, so the *content* of its page — not a 45 pt notice on
    /// it — now depends on whether the process running the measurement holds
    /// Accessibility, and every ratchet built on the offscreen render became a
    /// fact about somebody's terminal. This is the same discipline
    /// `ModulePageRender` applies to the appearance: a reading says which screen
    /// it is of, rather than inheriting whatever this Mac happens to be.
    func helmTracksAccessibility(_ state: Binding<PermissionState>) -> some View {
        modifier(HelmAccessibilityTracker(state: state))
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
    ///
    /// `helmGrants` comes in front of that probe, for the reason
    /// `helmTracksAccessibility` states: five pages draw a 61 pt banner off this
    /// answer, so without a reading a measurement of any of them is a fact about
    /// the grants of whichever process drew it.
    func helmTracksFullDiskAccess(_ state: Binding<PermissionState>) -> some View {
        modifier(HelmFullDiskTracker(state: state))
    }
}

/// What a reading of a page says about the grants it was taken under, or nil for
/// «ask the machine», which is every path in the running app.
///
/// A `PermissionState` per grant rather than one flag: a page can depend on more
/// than one, and «tell me about Accessibility» must not silently answer for Full
/// Disk Access as well.
public struct HelmGrants: Sendable, Equatable {
    public var accessibility: PermissionState?
    public var fullDisk: PermissionState?

    public init(accessibility: PermissionState? = nil, fullDisk: PermissionState? = nil) {
        self.accessibility = accessibility
        self.fullDisk = fullDisk
    }
}

public extension EnvironmentValues {
    /// Set by a measurement, never by the app. It changes what a view *draws*
    /// about a grant and nothing about what the app is allowed to do — the
    /// engines ask macOS for themselves, and a refusal comes from macOS.
    @Entry var helmGrants = HelmGrants()
}

/// The `.task` and the «Helm came back to the front» re-read, in one place, with
/// the override in front of the probe.
///
/// A `ViewModifier` rather than the two modifiers inline: the override lives in
/// the environment, and a `View` extension function cannot read it.
private struct HelmAccessibilityTracker: ViewModifier {
    @Environment(\.helmGrants) private var grants
    let state: Binding<PermissionState>

    func body(content: Content) -> some View {
        content
            .task { state.wrappedValue = answer }
            .helmOnAppActive { state.wrappedValue = answer }
    }

    private var answer: PermissionState {
        grants.accessibility ?? PermissionCheck.currentAccessibility()
    }
}

/// The same three lines for the other grant, and a `ViewModifier` for the same
/// reason: the reading lives in the environment, and a `View` extension function
/// cannot read it — which is why this grant stayed machine weather for as long as
/// it did while its twin had already been named.
///
/// The probe stays asynchronous, unlike Accessibility's: four blocking file reads
/// belong off the cooperative pool, and a reading skips them altogether.
private struct HelmFullDiskTracker: ViewModifier {
    @Environment(\.helmGrants) private var grants
    let state: Binding<PermissionState>

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
    }

    /// Not `grants.fullDisk ?? await …`: Swift refuses an `await` on the right of
    /// `??`, since the autoclosure it builds is synchronous. Written out, the
    /// reading also short-circuits the four file reads rather than racing them.
    private func answer() async -> PermissionState {
        if let named = grants.fullDisk { return named }
        return await PermissionCheck.fullDiskAccess()
    }
}
