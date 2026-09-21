import AppKit
import HelmTestSupport

/// **The instrument `TheSystemsScrollEdgeEffectAttachesTests` reads a window's
/// title bar with**, kept apart from the measurements that use it.
///
/// It is here and not in `Tests/Support` because exactly one file asks these
/// questions, and it is out of that file because it is not one of its answers:
/// the file argues that the band under this window's toolbar has to be Helm's
/// own — the system's scroll edge effect is withheld by
/// `titlebarAppearsTransparent`, the knob that would turn a per-page toolbar
/// background on is inert, and there is no per-section surface up there for
/// either of them to light. Two of those three are read off this census, and a
/// reader following that argument should not have to walk 190 lines of layer
/// walking to get from one to the next. The same separation
/// `Tests/Support/RenderedInk.swift` makes for a pixel reading, at the scale
/// one target needs it.
///
/// Every reading is a pure function of a window and nothing here holds state,
/// which is why it is an enum and why the move cost the measurements nothing.
@MainActor
enum TitlebarCensus {

    /// One window's title bar, kept as the parts a reader has to tell apart.
    ///
    /// The three ways this reading can be worthless — no window built, no
    /// window frame around the content, no title bar in it — are three cases
    /// rather than an empty census, because a census that is empty for those
    /// reasons prints exactly what a title bar with nothing in it prints.
    struct Reading: Equatable {
        let reach: Reach
        /// Views under the title bar container, so «found nothing» and «could
        /// not reach the tree» read differently.
        let viewsWalked: Int
        /// Layers under it, which is where a title bar's background actually
        /// is: on macOS 26 the whole bar is one `NSTitlebarView` whose first
        /// sublayer is a `CABackdropLayer` with no view of its own.
        let layersWalked: Int
        let containerFrame: NSRect?
        let titlebarViewFrame: NSRect?
        /// One line per layer, deep — the thing two arms are compared on.
        let census: [String]
        /// Views under the bar as wide as the sidebar: a «sidebar section», if
        /// AppKit made one.
        let sidebarWideViews: [String]
        /// `NSTitlebarContainerBlockingView`, which is the only view under the
        /// bar whose position comes from the split's divider.
        let blockingFrames: [NSRect]

        var readable: Bool { reach == .read }

        var sentence: String {
            switch reach {
            case .noContentView:
                return "the window has no content view: nothing was built to read"
            case .noWindowFrame:
                return "the content view has no superview: the window frame was never made"
            case .noTitlebarContainer:
                return "walked \(viewsWalked) views under the window frame and found no "
                    + "NSTitlebarContainerView: this window has no title bar to read"
            case .read:
                return "title bar \(containerFrame.map { "\($0)" } ?? "nil") over "
                    + "\(viewsWalked) views and \(layersWalked) layers, "
                    + "\(sidebarWideViews.count) of them as wide as the sidebar"
            }
        }
    }

    /// Every layer under `layer`, one line each, with everything a background
    /// would have to change to be drawn: its class, where it is, whether it is
    /// on, what it fills with, whether it carries content or a filter.
    static func lines(_ layer: CALayer, depth: Int) -> [String] {
        let fill = layer.backgroundColor.map { "\($0.components ?? [])" } ?? "none"
        let line = String(repeating: "  ", count: depth)
            + "\(layer.name ?? "-") <\(type(of: layer))> \(layer.frame)"
            + " opacity=\(layer.opacity) hidden=\(layer.isHidden) fill=\(fill)"
            + " contents=\(layer.contents != nil)"
            + " filters=\((layer.filters as? [Any])?.count ?? 0)"
            + " backgroundFilters=\((layer.backgroundFilters as? [Any])?.count ?? 0)"
            + " compositing=\(layer.compositingFilter != nil) mask=\(layer.mask != nil)"
        guard depth < 8 else { return [line + " [not descended]"] }
        return [line] + (layer.sublayers ?? []).flatMap { lines($0, depth: depth + 1) }
    }

    /// The title bar of `window`, read through the window frame — the bar is
    /// the content view's *sibling*, so a walk that starts at the content view
    /// never reaches it.
    static func read(in window: NSWindow) -> Reading {
        func empty(_ reach: Reach, views: Int) -> Reading {
            Reading(reach: reach, viewsWalked: views, layersWalked: 0,
                            containerFrame: nil, titlebarViewFrame: nil, census: [],
                            sidebarWideViews: [], blockingFrames: [])
        }
        guard let content = window.contentView else { return empty(.noContentView, views: 0) }
        guard let windowFrame = content.superview else { return empty(.noWindowFrame, views: 0) }
        let siblings = windowFrame.everyView.filter { view in
            view !== content && !(view.isDescendant(of: content))
        }
        guard let container = siblings.first(where: {
            $0.appKitClassName == "NSTitlebarContainerView"
        }) else {
            return empty(.noTitlebarContainer, views: siblings.count)
        }

        let under = container.everyView
        let sidebarWidth = (window.contentViewController as? NSSplitViewController)?
            .splitViewItems.first?.viewController.view.frame.width ?? 0
        let census = container.layer.map { lines($0, depth: 0) } ?? []
        return Reading(
            reach: .read,
            viewsWalked: under.count,
            layersWalked: census.count,
            containerFrame: container.frame,
            titlebarViewFrame: under.first { $0.appKitClassName == "NSTitlebarView" }?.frame,
            census: census,
            sidebarWideViews: under
                .filter { sidebarWidth > 0 && abs($0.frame.width - sidebarWidth) < 1 }
                .map { "\($0.appKitClassName) \($0.frame)" },
            blockingFrames: under
                .filter { $0.appKitClassName == "NSTitlebarContainerBlockingView" }
                .map(\.frame))
    }

    /// Every arm's census, read in one pass, until three passes running agree.
    ///
    /// **A title bar's layers arrive late and out of order.** A layer's
    /// `contents` appears when it first rasterizes and the decoration layer is
    /// built lazily, so two windows read at two moments differ by the time
    /// between the readings — measured: the same pair read one after the other
    /// was 22 layers against 26, and the extra four were the decoration
    /// layer's, which had simply not been made yet when the first was read.
    /// Reading every arm in one pass and waiting for the passes to repeat is
    /// what makes a difference between arms a difference about the arms.
    ///
    /// «Never settled» comes back as its own answer rather than as the last
    /// pass, because a comparison over a tree still being built is the kind of
    /// green that means nothing.
    struct Settled {
        let censuses: [String: [String]]
        /// Passes taken, so «settled at once» and «settled after a second of
        /// run loop» are not the same sentence in a failure message.
        let passes: Int
        let settled: Bool
    }

    static func settled(_ arms: [(name: String, window: NSWindow)],
                        forAtMost seconds: TimeInterval) -> Settled {
        let deadline = Date().addingTimeInterval(seconds)
        var previous: [String: [String]] = [:]
        var agreements = 0
        var passes = 0
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            let now = Dictionary(uniqueKeysWithValues:
                arms.map { ($0.name, read(in: $0.window).census) })
            passes += 1
            agreements = now == previous ? agreements + 1 : 0
            previous = now
            if agreements >= 2 { return Settled(censuses: now, passes: passes, settled: true) }
        }
        return Settled(censuses: previous, passes: passes, settled: false)
    }

    /// What one census has that the other has not, both ways round, as a
    /// multiset — an inserted layer shifts every line after it, so a
    /// line-by-line comparison of two trees that differ by one layer reports
    /// the whole tail as different and names the wrong layer.
    static func difference(_ left: [String], _ right: [String]) -> [String] {
        var remaining = right
        var out: [String] = []
        for line in left {
            if let hit = remaining.firstIndex(of: line) { remaining.remove(at: hit) } else {
                out.append("only without the change: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        return out + remaining.map {
            "only with the change: \($0.trimmingCharacters(in: .whitespaces))"
        }
    }

    /// The census, proved able to see a background arriving in the title bar.
    ///
    /// Plants a layer of its own under `NSTitlebarView`, reads, and takes it
    /// away again. Without this, «the two arms read alike» is indistinguishable
    /// from «this reader cannot see the thing the arms differ in», which is the
    /// shape of every check that cannot fail.
    static func seesAPlantedLayer(in window: NSWindow) -> String? {
        let before = read(in: window)
        guard let bar = window.contentView?.superview?.everyView
            .first(where: { $0.appKitClassName == "NSTitlebarView" }),
            let host = bar.layer else { return "there is no NSTitlebarView to plant a layer under" }
        let planted = CALayer()
        planted.name = "PlantedTitlebarBackground"
        planted.frame = bar.bounds
        planted.backgroundColor = NSColor.systemPink.cgColor
        host.addSublayer(planted)
        let during = read(in: window)
        planted.removeFromSuperlayer()
        let after = read(in: window)

        guard during.census.contains(where: { $0.contains("PlantedTitlebarBackground") }) else {
            return "a layer planted under the title bar does not appear in the census"
        }
        guard during.census.count == before.census.count + 1 else {
            return "planting one layer moved the census by "
                + "\(during.census.count - before.census.count) lines"
        }
        guard after.census == before.census else {
            return "the census did not come back to what it was once the planted layer was gone"
        }
        return nil
    }

    /// The three ways a title-bar reading can be worthless, kept apart from a
    /// reading that found nothing — a census that is empty because no window was
    /// built prints what a title bar with nothing in it prints.
    enum Reach: String {
        case noContentView, noWindowFrame, noTitlebarContainer, read
    }
}
