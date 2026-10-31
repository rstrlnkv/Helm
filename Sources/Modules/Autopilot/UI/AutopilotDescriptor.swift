import HelmContract
import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

@MainActor public final class AutopilotDescriptor: ModuleDescriptor {
    public typealias Model = AutopilotViewModel

    public static let id = ModuleID(AutopilotEngine.moduleID)
    /// **The one module that has something to hand over on a first launch.**
    /// Every other one either works the moment it is switched on or waits for a
    /// gesture; this one does nothing at all until somebody writes a rule, and a
    /// tour that left them at «Autopilot: folders that keep themselves in order»
    /// has described a feature and delivered none of it. The offer is the way to
    /// the page that shows the five rules they can have without writing one —
    /// worded as going there (`tourOffer`) and not as showing the rules, because
    /// the tour cannot know whether the page still has them to show: it does
    /// only while there is no rule at all.
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: ApStr.moduleName, summary: ApStr.summary,
        sfSymbol: "location.north.circle", permissions: [.fullDisk],
        welcomeOffer: ApStr.tourOffer) }
    public static let category: ModuleCategory = .files
    public static let tint = ModuleTint(
        ordinary: (light: (0.000, 0.533, 1.000), dark: (0.000, 0.569, 1.000)),
        increasedContrast: (light: (0.000, 0.464, 0.870), dark: (0.000, 0.472, 0.830)))
    public static let glyph = ShellGlyph(
        body: ShellGlyph.rounded([ShellGlyph.pt(4.5, 5), ShellGlyph.pt(20.5, 12), ShellGlyph.pt(4.5, 19), ShellGlyph.pt(8, 12)], 1.5),
        detail: ShellGlyph.lines([[ShellGlyph.pt(8, 12), ShellGlyph.pt(13.5, 12)]]))
    /// Folders and their rules span the pane; the header must not centre itself
    /// on the 744 pt form column.
    public var pageBleeds: Bool { true }

    public init() {}

    /// The one place the production engine is built; `makeModule` needs it as
    /// the concrete type the model calls.
    private func productionEngine(store: NamespacedStore,
                                  historyChanged: @escaping @Sendable () -> Void) -> AutopilotEngine {
        // The sweep runs hourly with nobody at the desk and it trashes files,
        // which makes it the one thing this module does that a person is owed
        // out loud. The sentence comes from here, because `L()` is `HelmUI`'s
        // and the engine cannot see it — the shape Keep Awake's battery veto
        // already has.
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

    /// Not a utility any more: how many folders it watches and what it did
    /// today are figures worth a glance, which is the whole test for whether a
    /// module belongs in the panel rather than behind a disclosure in it.
    /// A row in the utilities list, not a tile.
    ///
    /// It had a widget for a while — the count of watched folders, the words
    /// put right today — and both are numbers without a question behind them:
    /// nobody opens a menu bar to find out how many folders are watched. A tile
    /// has to earn its 90 pt, and this one was earning it by existing.
    public func menuBar(_ model: AutopilotViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ model: AutopilotViewModel) -> AnyView {
        AnyView(AutopilotSettingsPage(rvm: model))
    }
}
