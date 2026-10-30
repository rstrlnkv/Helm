import SwiftUI
import HelmUI

struct HomebrewSettingsPage: View {
    @ObservedObject var hb: HomebrewViewModel

    var body: some View {
        VStack(spacing: 0) {
            if hb.status.installed {
                HomebrewManager(hb: hb)
            } else {
                installScreen
            }
            if showsConsole {
                Divider()
                HomebrewConsole(hb: hb)
            }
        }
        // **The console arrives by taking its height off everything above it**, and it used
        // to do that in one frame: the first install of the session put a
        // divider and the well under the page, and the list, the status bar and
        // whatever row the eye was on jumped up together. One token, on
        // the fact that decides it — the same one the other list screens use
        // (`UninstallerSettingsPage`).
        //
        // `showsConsole` and not `hb.consoleLines.count`: the lines arriving
        // scroll, which `HomebrewConsole` does by a jump, and re-running the page's
        // layout per line of `brew` output is a different thing entirely.
        // The band stands on the manager's own bands or on the install screen,
        // never on a scroll view, so it is lit from the first frame
        // (`helmPageStandsOnStillContent`).
        .helmPageStandsOnStillContent()
        .animation(HelmMotion.interface, value: showsConsole)
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
        // visit to Homebrew opens a confirmation for the app's only
        // irreversible deletion that nobody asked for. `LatestRequest` retires
        // work on a later press and on a cancel; leaving is neither, and this
        // is the one place that knows it happened. The modifier is not on
        // this page and this comment used to say it was: `.helmIdlesOffScreen()`
        // is on the detail hosting controller in `SettingsWindow.swift`, which
        // holds whichever module page is open — so hiding the app or occluding
        // the Settings window unmounts this subtree and fires this too, which is
        // the behaviour, reached from one level up. Dismissing a
        // confirmation dialog the person had left standing on screen rather
        // than leaving it to act later on a reading taken before the
        // interruption, which is the right call for the app's only
        // irreversible deletion.
        // And the other question this page can have standing: a `brew doctor`
        // fix that removes a package waits on a dialog too, and it is asked of
        // the same view model, which outlives this subtree.
        .onDisappear { hb.cancelUninstall(); hb.cancelFix() }
        // The second irreversible deletion this page can reach, and it used to
        // go on a single click six points from Copy. The question names the
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
        // Removing a cask removes an application. Every other destructive
        // action in Helm asks first; this one used to go on a single click.
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
    private var showsConsole: Bool {
        !hb.consoleLines.isEmpty || hb.running || hb.op.phase == .failed
    }

    // MARK: - Not installed

    /// The same pane draws `HelmEmptyState` with the module switched off; this
    /// used to replace it in place with a hand-rolled second one — 16 pt stack
    /// spacing against 14, a 20 pt title against 17, a 12 pt body against 13,
    /// and a button pinned to 260 pt. One flick of the switch showed both.
    ///
    /// **The tint is the module's, not the category's.** This comment used to
    /// say the colour was «read off the descriptor rather than written as
    /// `.pink`» — and it was reading the category's colour, which is `.pink` reached
    /// the long way round and shared with two other modules. The plate in the
    /// page header above it was already green.
    private var installScreen: some View {
        HelmEmptyState(symbol: "shippingbox",
                       tint: HomebrewDescriptor.tint.colour,
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
