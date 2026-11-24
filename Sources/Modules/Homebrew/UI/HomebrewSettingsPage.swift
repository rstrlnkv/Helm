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
        // flag is the view's own (`shownConsole`; `HelmAccordion`), keyed on
        // `showsConsole` and not on the lines, so a line does not re-run the
        // page's layout. The band stands on still content (`helmPageStandsOnStillContent`).
        .helmPageStandsOnStillContent()
        .onChange(of: Self.showsConsole(hb)) { _, now in
            withAnimation(HelmMotion.disclosure) { shownConsole = now }
        }
        // The view model outlives this page, so a return visit shows what is
        // already loaded.
        .task { await hb.loadIfNeeded() }
        // And so the page says it has gone: an uninstall or fix ask still out
        // would otherwise open its dialog on the next visit, nobody having
        // asked. `.helmIdlesOffScreen()` in `SettingsWindow.swift` unmounts
        // this subtree when the window hides too, which dismisses a dialog left
        // standing rather than let it act on a stale reading.
        .onDisappear { hb.cancelUninstall(); hb.cancelFix() }
        // A fix asks first too; `FixAsk` decides which question.
        .confirmationDialog(hb.pendingFix.map { Self.fixQuestion($0) } ?? "",
                            isPresented: Binding(get: { hb.pendingFix != nil },
                                                 set: { if !$0 { hb.cancelFix() } }),
                            titleVisibility: .visible) {
            Button(HbStr.runTheFix, role: .destructive) { hb.confirmFix() }
            Button(HelmWord.cancel, role: .cancel) { hb.cancelFix() }
        } message: {
            if let note = hb.pendingFix.flatMap({ Self.fixQuestionNote($0, dependents: hb.dependentsOfPending) }) { Text(note) }
        }
        // Removing a cask removes an application, so it asks first.
        .confirmationDialog(hb.pendingUninstall.map { HbStr.confirmUninstall($0.name) } ?? "",
                            isPresented: Binding(get: { hb.pendingUninstall != nil },
                                                 set: { if !$0 { hb.cancelUninstall() } }),
                            titleVisibility: .visible) {
            Button(HbStr.uninstall, role: .destructive) { hb.confirmUninstall() }
            Button(HelmWord.cancel, role: .cancel) { hb.cancelUninstall() }
        } message: {
            Text(Self.uninstallNote(dependents: hb.dependentsOfPending))
        }
    }

    /// Whether the console and the hairline over it are on the page at all.
    ///
    /// `.failed` as well: a refusal before launch writes no console line, and
    /// its note needs a console to be drawn in.
    private static func showsConsole(_ hb: HomebrewViewModel) -> Bool {
        !hb.consoleLines.isEmpty || hb.running || hb.op.phase == .failed
    }

    // MARK: - Not installed

    /// `HelmEmptyState`, the drawing the same pane shows with the module off.
    /// **The tint is the module's** (`HomebrewDescriptor.tint`), as in the page
    /// header.
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
