import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// The page, mounted, and where its controls came out — shared by every check in
/// this target that measures a drawing rather than a value.
///
/// The mount was written out in three files before this existed, and the reader
/// under it in two more (`ARemovalReportDoesNotEatTheListTests` walks for the
/// list's own scroll view, VPN's page walks for focus rings): the same argument as
/// `LeftoversWire` one file over. A control drawn by SwiftUI on macOS is a
/// `_FocusRingView` in the rendered tree — the checkbox, the buttons, the segmented
/// filter — and its frame is the only honest answer to «how wide was that button
/// actually drawn», which is a question no layout API answers: they all report what
/// the row *asked for*.
@MainActor
enum LeftoversPageRender {

    /// A mounted page in one language, at one width, in a named appearance.
    ///
    /// The caller owns `AppLanguage.override`'s restoration: a render is only in
    /// the language that was set while it was laid out, so the override has to
    /// outlive this call and every `settle` the caller makes.
    static func page(_ items: [StaleItem], language: AppLanguage, width: CGFloat,
                     height: CGFloat = 540, appearance: NSAppearance.Name,
                     scanned: Bool = true,
                     grants: HelmGrants = HelmGrants(accessibility: .granted, fullDisk: .granted)) async -> (MountedRender, LeftoversViewModel) {
        await page(on: LeftoversWire(items: items), language: language, width: width,
                   height: height, appearance: appearance, scanned: scanned, grants: grants)
    }

    /// The same page over a wire the caller built: one that holds a removal reply,
    /// or one that does not answer until it is told to. Hand-rolled in two files
    /// before it took a transport, which is the same argument as the mount itself.
    /// - Parameter grants: named, never inherited — without the disk grant the
    ///   page draws a permission note and every measurement below moves 61 pt. It
    ///   is an argument rather than a constant because the denied state is a
    ///   branch of this page: the note, and the Grant button the report used to
    ///   key to this probe instead of to the refusal under it.
    static func page(on transport: EngineTransport, language: AppLanguage, width: CGFloat,
                     height: CGFloat = 540, appearance: NSAppearance.Name,
                     scanned: Bool = true,
                     grants: HelmGrants = HelmGrants(accessibility: .granted, fullDisk: .granted)) async -> (MountedRender, LeftoversViewModel) {
        AppLanguage.override = language
        let vm = ModuleViewModel(transport: transport)
        let mount = MountedRender(LeftoversSettingsPage(vm: vm)
            .environment(\.helmGrants, grants),
                                  width: width, height: height, appearance: appearance)
        let model = LeftoversViewModel.shared(vm: vm)
        if scanned { await model.scan() }
        mount.settle(30)
        return (mount, model)
    }

    /// Every control's frame in the page's own coordinates, left to right.
    static func controls(in mount: MountedRender) -> [CGRect] {
        var found: [CGRect] = []
        func walk(_ view: NSView) {
            if "\(type(of: view))" == "_FocusRingView" {
                found.append(view.convert(view.bounds, to: mount.host))
            }
            view.subviews.forEach(walk)
        }
        walk(mount.host)
        return found.sorted { $0.minX < $1.minX }
    }

    /// What one button asks for when nothing is squeezing it: the same control,
    /// alone, in a mount far wider than any translation of it.
    ///
    /// - Parameter controlSize: the page draws two sizes and this measured one.
    ///   Every language came out ~19 pt «squeezed» against a regular control when
    ///   the row's button is `.small` — a difference in the *baseline*, which
    ///   would have read as a truncation on all eight and hidden a real one.
    static func naturalWidth(of title: String, prominent: Bool,
                             appearance: NSAppearance.Name,
                             controlSize: ControlSize = .regular) -> CGFloat {
        let button = Button(title) {}
        let mount = MountedRender(Group {
            if prominent { button.buttonStyle(.borderedProminent) } else { button }
        }.controlSize(controlSize), width: 900, height: 60, appearance: appearance)
        defer { mount.drop() }
        mount.settle(6)
        return controls(in: mount).first?.width ?? 0
    }
}
