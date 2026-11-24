import HelmContract
import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

@MainActor public final class AutopilotDescriptor: ModuleDescriptor {
    public typealias Model = AutopilotViewModel

    public static let id = ModuleID(AutopilotEngine.moduleID)
    /// **The one module that has something to hand over on a first launch.** It
    /// does nothing until somebody writes a rule, so the tour offers the way to
    /// the page that shows the five rules they can have without writing one.
    /// Worded as going there (`tourOffer`), not as showing the rules: the page
    /// has them only while there is no rule at all, and the tour cannot know.
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: ApStr.moduleName, summary: ApStr.summary,
        sfSymbol: symbol, permissions: [.fullDisk],
        welcomeOffer: ApStr.tourOffer) }
    static let symbol = "location.north.circle"
    public static let category: ModuleCategory = .files
    public static let tint = ModuleTint(
        ordinary: (light: (0.000, 0.533, 1.000), dark: (0.000, 0.569, 1.000)),
        increasedContrast: (light: (0.000, 0.464, 0.870), dark: (0.000, 0.472, 0.830)))
    public static let glyph = ShellGlyph(
        body: ShellGlyph.rounded([ShellGlyph.pt(4.5, 5), ShellGlyph.pt(20.5, 12), ShellGlyph.pt(4.5, 19), ShellGlyph.pt(8, 12)], 1.5),
        detail: ShellGlyph.lines([[ShellGlyph.pt(8, 12), ShellGlyph.pt(13.5, 12)]]))

    public init() {}

    /// The one place the production engine is built; `makeModule` needs it as
    /// the concrete type the model calls.
    private func productionEngine(store: NamespacedStore,
                                  historyChanged: @escaping @Sendable () -> Void) -> AutopilotEngine {
        // The sweep runs hourly with nobody at the desk and it trashes files,
        // so a person is owed a notice. The sentence comes from here because
        // `L()` is `HelmUI`'s and the engine cannot see it.
        AutopilotEngine(store: store,
                        sweepNotice: SweepNotifier(
                            port: SystemAutomationNotice(area: AutopilotEngine.moduleID),
                            words: { ApStr.sweepNotice($0) }),
                        historyChanged: historyChanged)
    }

    /// The channel the engine's "a pass went into the history" travels on,
    /// newest one kept: the signal means "look again" and carries nothing, so
    /// the model's loop takes one ping, the slot holds one more, and the rest
    /// are dropped — three in a row are at most two reads, never three. A
    /// function of its own so a test reads the same buffering `makeModule` uses
    /// (`AnAnnouncedPassReachesTheModelWithNoPageTests.testThreePingsBeforeAnyoneLooksAreAtMostTwoReads`).
    static func historyChannel() -> (AsyncStream<Void>, AsyncStream<Void>.Continuation) {
        AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// The engine and the model that calls it, built once at launch; the model
    /// reads nothing until a page opens it.
    public func makeModule(store: NamespacedStore) -> ModuleParts<AutopilotViewModel> {
        let (changes, changed) = Self.historyChannel()
        let engine = productionEngine(store: store, historyChanged: { changed.yield() })
        return ModuleParts(engine: engine, model: AutopilotViewModel(work: engine, historyChanges: changes))
    }

    /// Closes the model; the host calls it before the engine's `deactivate()`,
    /// on the person's switch and on quit.
    public func stop(_ model: AutopilotViewModel) { model.stop() }

    /// A row in the utilities list, not a tile: what a tile could show, the
    /// folders watched or the files put right today, answers no question anyone
    /// opens a menu bar to ask.
    public func menuBar(_ model: AutopilotViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ model: AutopilotViewModel) -> AnyView {
        AnyView(AutopilotSettingsPage(rvm: model))
    }
}
