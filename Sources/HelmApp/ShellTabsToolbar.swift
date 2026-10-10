import AppKit
import HelmRuntime

/// **The owner of an `NSToolbar` that holds one thing, AppKit's own segmented control, and of the one
/// assignment of that toolbar to a window.** It names no page, no layout and no look: whoever holds it
/// says whether the window wears the toolbar (`wear(_:)`) and where, in window coordinates, the control's
/// left edge goes (`place(minX:)`). Nothing in the app constructs it; the window still has no toolbar.
/// It is the only file under `Sources` that names a type of AppKit's toolbar family and the only one that
/// writes a window's `toolbar`, in one line that `attach(to:)` and `wear(_:)` both reach.
///
/// **Two items, and nothing else.** `lead` holds an empty view whose width is a constraint this object
/// writes; `tabs` holds the control. The lead exists because AppKit lays a toolbar's items out from its
/// own left edge and offers no way to say "start here": the control stands at the lead's width plus the
/// distance AppKit puts between the two. There is no flexible space on purpose. Every item sits in a
/// viewer view of AppKit's that is as high as the strip and as wide as the item, and answers the hit
/// test; a flexible space's viewer would cover everything from the control's right edge to the window's,
/// where the content's own controls stand. The lead's viewer would cover everything from the buttons to
/// the control, so `releaseLead()` hides it, by `isHidden` on the superview of the empty view: a public
/// property of a view AppKit owns, found by reading `superview` and `subviews`, with no private selector
/// and no key by name. It hides a view only when that view holds the empty view alone and is neither
/// the window's content view nor its frame view; when AppKit's hierarchy has another shape it hides
/// nothing, writes one line to the log, and the hit test then answers AppKit's viewer left of the
/// control. It runs when AppKit puts the empty view in a window, at every `place(minX:)` and after every
/// assignment that puts the toolbar on.
///
/// **Where the control stands.** Its left edge is the empty view's left edge in the window, `leadEdge`,
/// plus the constant, plus the distance between the empty view's right edge and the control's, `gap`. Both
/// are read back from the last layout, when the empty view stands flush with its viewer's left edge, and
/// are 92 and 4 until then. The constant is `minX` rounded down, less the two, brought into
/// `1...widest`: zero lays nothing out, so 1 is the least; not-a-number reads 1, and an infinity goes to
/// the bound on its side. The toolbar snaps its items to whole points while the asked x may carry
/// fractions, hence the rounding down, and the left edge `controlFrameInWindow` shows can differ from the
/// asked x by under a point. A viewer is wider than a narrow empty view: with the constant at 1 the
/// control stood at 132.5 in a 1000 pt window never shown, one reading that no row holds, so that is
/// about as far left as it goes, and an x left of it is not reached. `place(minX: nil)` hides the control's item and keeps the strip.
///
/// **Assigned only when asked.** One `NSToolbar` lives as long as this object and goes on the window
/// by `wear(true)` and off it by `wear(false)`; a call that changes nothing assigns nothing, and
/// `assignments` counts the rest. The style is `.unified` and the display mode `.iconOnly`. A `wear(_:)`
/// asked before there is a window is remembered and applied by `attach(to:)`.
///
/// **Measured in a window never ordered and never key** (by the rows of
/// `TheTabsToolbarStandsItsControlWhereItIsToldTests`): the assignments against a key-value observer of
/// `window.toolbar`, the constant never below 1, the control's left edge against the asked x, the control
/// leaving the window with its item hidden, the lead hidden after a place, a resize and off then on, and
/// the frame view's hit test left and right of the control and on it. **Not seen by anyone:** a real
/// press, a drag, a double click or the context menu delivered where the hit test answers; anything
/// drawn, so that the control wears AppKit's rendition and no band appears under the strip; the control
/// in a key or an inactive window; full screen; a right-to-left layout, where the lead may stand on the right, a guess no row holds;
/// whether the lead's 92 changes with the window's buttons hidden.
@MainActor
final class ShellTabsToolbar: NSObject, NSToolbarDelegate {

    /// The control, AppKit's own: no cell, no size and no colour is written to it here.
    let control = NSSegmentedControl()

    /// Called with the index of the segment a person pressed; never for a change made from code.
    var onPick: ((Int) -> Void)?

    /// How many times a window's `toolbar` was assigned by this object, equal values excluded.
    private(set) var assignments = 0

    private static let leadID = NSToolbarItem.Identifier("lead")
    private static let tabsID = NSToolbarItem.Identifier("tabs")

    /// The ceiling of the lead's constant. A window is far narrower.
    private static let widest: CGFloat = 1_000_000

    /// What the lead edge and the gap read until a layout has put the items in a window.
    private static let firstLeadEdge: CGFloat = 92
    private static let firstGap: CGFloat = 4

    private let toolbar = NSToolbar(identifier: "HelmTabsToolbar")
    private let spacer = Lead()
    private let leadWidth: NSLayoutConstraint
    private let leadItem = NSToolbarItem(itemIdentifier: ShellTabsToolbar.leadID)
    private let tabsItem = NSToolbarItem(itemIdentifier: ShellTabsToolbar.tabsID)

    private weak var window: NSWindow?
    private var wanted = false
    private var leadEdge = ShellTabsToolbar.firstLeadEdge
    private var gap = ShellTabsToolbar.firstGap
    private var loggedTheLead = false

    /// The empty view of the `lead` item; it tells its owner when AppKit has put it in a window.
    private final class Lead: NSView {
        var arrived: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { arrived?() }
        }
    }

    override init() {
        spacer.translatesAutoresizingMaskIntoConstraints = false
        leadWidth = spacer.widthAnchor.constraint(equalToConstant: 1)
        leadWidth.isActive = true
        spacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
        super.init()
        spacer.arrived = { [weak self] in self?.releaseLead() }
        leadItem.view = spacer
        leadItem.isBordered = false
        leadItem.style = .plain
        control.trackingMode = .selectOne
        control.target = self
        control.action = #selector(picked(_:))
        tabsItem.view = control
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
    }

    // MARK: - the window

    /// Names the window the toolbar goes on, and puts it there when `wear(true)` was asked before. A
    /// different window than the one before takes the toolbar off the one before.
    func attach(to window: NSWindow?) {
        if let old = self.window, old !== window, old.toolbar === toolbar { assign(nil, to: old) }
        self.window = window
        apply()
    }

    /// Puts the toolbar on the window (`true`) or takes it off (`false`). Nothing when the window already
    /// stands so; remembered when there is no window yet.
    func wear(_ on: Bool) {
        wanted = on
        apply()
    }

    private func apply() {
        guard let window else { return }
        let target = wanted ? toolbar : nil
        guard window.toolbar !== target else { return }
        assign(target, to: window)
        if wanted { releaseLead() }
    }

    /// The one line that writes a window's `toolbar`.
    private func assign(_ target: NSToolbar?, to window: NSWindow) {
        window.toolbar = target
        if target != nil { window.toolbarStyle = .unified }
        assignments += 1
    }

    // MARK: - where the control stands

    /// The control's width when it is worn and in the window; 0 otherwise. A free twin of the control does
    /// not give it: read in a window never shown, the control fits narrower in the toolbar than a free twin
    /// with the same labels, a reading no row holds.
    var fittingWidth: CGFloat {
        guard window?.toolbar === toolbar, control.window != nil else { return 0 }
        return control.fittingSize.width
    }

    /// Stands the control's left edge at `minX` in the window's coordinates, rounded down; nil hides the
    /// control's item and keeps the strip.
    func place(minX: CGFloat?) {
        readBack()
        if let minX {
            // Not-a-number reads the least, 1; an infinity the bound on its side.
            let constant = (minX.rounded(.down) - leadEdge - gap)
                .clamped(to: 1...Self.widest, whenNotANumber: 1)
            tabsItem.isHidden = false
            set(constant)
        } else {
            tabsItem.isHidden = true
            set(1)
        }
        releaseLead()
    }

    private func set(_ constant: CGFloat) {
        if leadWidth.constant != constant { leadWidth.constant = constant }
    }

    /// The lead edge and the gap as the last layout left them, when both views are in the window and the
    /// empty view stands at the left edge of its viewer. A viewer is at least as wide as AppKit makes every
    /// item, so a narrow empty view is centred in it, and the distances read then belong to the viewer's
    /// padding and not to the lead.
    private func readBack() {
        guard spacer.window != nil, control.window != nil, let viewer = spacer.superview else { return }
        let lead = spacer.convert(spacer.bounds, to: nil)
        let tabs = control.convert(control.bounds, to: nil)
        let measuredGap = tabs.minX - lead.maxX
        let flush = lead.minX - viewer.convert(viewer.bounds, to: nil).minX
        guard lead.minX.isFinite, measuredGap.isFinite, measuredGap >= 0, abs(flush) < 1 else { return }
        leadEdge = lead.minX
        gap = measuredGap
    }

    // MARK: - the lead

    /// Hides the viewer AppKit puts around the empty view, so that it answers no hit. Only a view that
    /// holds the empty view alone is hidden; any other shape is left and logged once.
    private func releaseLead() {
        guard let viewer = spacer.superview, let window = spacer.window else { return }
        guard viewer.subviews == [spacer], viewer !== window.contentView,
              viewer !== window.contentView?.superview else {
            if !loggedTheLead {
                loggedTheLead = true
                HelmLog.shared.warn("shell", "the tabs toolbar's lead has an unexpected container; left as it is")
            }
            return
        }
        if !viewer.isHidden { viewer.isHidden = true }
    }

    // MARK: - readings

    /// The width constraint of the lead as it stands.
    var leadConstant: CGFloat { leadWidth.constant }

    /// The control's frame in the window; `.null` when it is in none (not worn, or its item hidden).
    var controlFrameInWindow: CGRect {
        control.window == nil ? .null : control.convert(control.bounds, to: nil)
    }

    /// Whether the lead's viewer is in a window and hidden; false while nothing is worn.
    var leadIsReleased: Bool {
        spacer.window != nil && spacer.superview?.isHidden == true
    }

    // MARK: - the control's action

    @objc private func picked(_ sender: NSSegmentedControl) {
        onPick?(sender.selectedSegment)
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.leadID, Self.tabsID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.leadID, Self.tabsID]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.leadID: return leadItem
        case Self.tabsID: return tabsItem
        default: return nil
        }
    }
}
