import SwiftUI
import HelmUI

struct HomebrewSettingsPage: View {
    @ObservedObject var hb: HomebrewViewModel
    /// What is drawn of `showsConsole`: a value the engine publishes is not a press (`HelmAccordion`).
    @State private var shownConsole: Bool
    @State private var consoleBlock: CGFloat?
    @Environment(\.helmTraits) private var traits

    init(hb: HomebrewViewModel) {
        _hb = ObservedObject(wrappedValue: hb)
        _shownConsole = State(initialValue: Self.showsConsole(hb))
    }

    var body: some View {
        VStack(spacing: 0) {
            if hb.status.installed {
                HomebrewManager(hb: hb)
            } else {
                installScreen
            }
            VStack(spacing: 0) {
                Divider()
                HomebrewConsole(hb: hb, open: shownConsole)
            }
            .helmAccordion(open: shownConsole, height: $consoleBlock)
        }
        // **The console arrives by taking its height off everything above it.** Its
        // flag is the view's own (`shownConsole`): the operation's state is a value the
        // engine publishes, not a press, and `HelmAccordion` says what that needs.
        // `showsConsole` and not the lines: a line arriving scrolls by a jump in
        // `HomebrewConsole`, and re-running the page's layout per line is another thing.
        // The band stands on the manager's own bands or on the install screen, never on
        // a scroll view, so it is lit from the first frame (`helmPageStandsOnStillContent`).
        .helmPageStandsOnStillContent()
        .onChange(of: Self.showsConsole(hb)) { _, now in
            withAnimation(HelmMotion.disclosure) { shownConsole = now }
        }
        // The view model outlives this page, so a return visit shows what is
        // already loaded instead of paying for `brew list` and a `brew desc`
        // batch again.
        .task { await hb.loadIfNeeded() }
        // The other side of that: the view model outliving the page is exactly
        // why the page has to say it has gone. An uninstall ask is asked of
        // the engine and can be out for the whole query deadline, and the
        // `Task` the press launches is not tied to this subtree — so switching
        // modules or closing Settings leaves a query whose answer would set
        // `pendingUninstall` on a view model with nothing mounted, and the next
        // visit to Homebrew opens a confirmation for an
        // irreversible deletion that nobody asked for. `LatestRequest` retires
        // work on a later press and on a cancel; leaving is neither, and this
        // is the one place that knows it happened. The modifier is not on
        // this page: `.helmIdlesOffScreen()`
        // is on the detail hosting controller in `SettingsWindow.swift`, which
        // holds whichever module page is open — so hiding the app or occluding
        // the Settings window unmounts this subtree and fires this too, which is
        // the behaviour, reached from one level up. Dismissing a
        // confirmation dialog the person had left standing on screen rather
        // than leaving it to act later on a reading taken before the
        // interruption, which is the right call for an
        // irreversible deletion.
        // And the other question this page can have standing: a `brew doctor`
        // fix that removes a package waits on a dialog too, and it is asked of
        // the same view model, which outlives this subtree.
        .onDisappear { hb.cancelUninstall(); hb.cancelFix() }
        // The second irreversible deletion this page can reach; it asks first. The question names the
        // package with the words the Uninstall dialog uses — `FixAsk` decides
        // which of the two questions is asked, and whether one is asked at all.
        .confirmationDialog(hb.pendingFix.flatMap { Self.fixQuestion($0) } ?? "",
                            isPresented: Binding(get: { hb.pendingFix != nil },
                                                 set: { if !$0 { hb.cancelFix() } }),
                            titleVisibility: .visible) {
            Button(HbStr.runTheFix, role: .destructive) { hb.confirmFix() }
            Button(HbStr.cancel, role: .cancel) { hb.cancelFix() }
        } message: {
            if let note = hb.pendingFix.flatMap({ Self.fixQuestionNote($0) }) { Text(note) }
        }
        // Removing a cask removes an application, so it asks first.
        .confirmationDialog(hb.pendingUninstall.map { HbStr.confirmUninstall($0.name) } ?? "",
                            isPresented: Binding(get: { hb.pendingUninstall != nil },
                                                 set: { if !$0 { hb.cancelUninstall() } }),
                            titleVisibility: .visible) {
            Button(HbStr.uninstall, role: .destructive) { hb.confirmUninstall() }
            Button(HbStr.cancel, role: .cancel) { hb.cancelUninstall() }
        } message: {
            // Two sentences, and the second only when there is something to say:
            // a heading over an empty list reads as a reassurance that nothing
            // depends on this, which a refused query has not earned.
            if hb.dependentsOfPending.isEmpty {
                Text(HbStr.uninstallIsPermanent)
            } else {
                Text(HbStr.uninstallIsPermanent + "\n\n"
                     + HbStr.stillNeededBy + "\n"
                     + hb.dependentsOfPending.joined(separator: ", "))
            }
        }
    }

    /// Whether the console and the hairline over it are on the page at all.
    ///
    /// `.failed` as well, and that is not cosmetic: an operation the engine
    /// refused before it launched anything writes no console line, so a refusal
    /// with an empty console had no console to be drawn in and reached the page
    /// as nothing at all.
    private static func showsConsole(_ hb: HomebrewViewModel) -> Bool {
        !hb.consoleLines.isEmpty || hb.running || hb.op.phase == .failed
    }

    // MARK: - Not installed

    /// The same pane draws `HelmEmptyState` with the module switched off, so this is
    /// the same drawing and not a second, hand-rolled one: one flick of the switch
    /// would show both.
    ///
    /// **The tint is the module's** (`HomebrewDescriptor.tint`): this plate and the
    /// one in the page header above it are one green.
    private var installScreen: some View {
        HelmEmptyState(symbol: "shippingbox",
                       tint: HomebrewDescriptor.tint.colour(increased: traits.increasedContrast),
                       title: HbStr.notInstalledTitle,
                       message: HbStr.notInstalledBody()) {
            Button {
                hb.installBrew()
            } label: {
                Label(HbStr.installBrew, systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(hb.running)
        }
    }
}
