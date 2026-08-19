// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI
import Module_VPN_Engine

/// **What the hero draws, as one value.**
///
/// Separate from the view because every rule worth guarding here is a rule
/// about *content* — which tiles exist, what each says, which sentence the
/// verdict is — and none of it can be read back off a rendering: an
/// `NSHostingView`'s accessibility tree is empty outside a real client, and
/// SwiftUI draws its own type rather than through `NSTextField`. A view whose
/// content is a value is a view whose content has a test
/// (`TheStripDrawsOnlyWhatIsKnownTests`); a view that decides in its `body` has
/// prose instead.
struct VPNTunnelStrip {

    /// What the headline wears beside its sentence. Three, not a boolean:
    /// a check that could not be made must never be dressed as the bad answer
    /// (`VPNExitVerdict`).
    ///
    /// The glyph and the colour hang off the case rather than off two switches
    /// in the view, so a fourth answer is one place to fill in and a build
    /// error until it is.
    enum Mark: Equatable {
        case success, warning, neutral

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .neutral: "questionmark.circle"
            }
        }

        var tint: Color {
            switch self {
            case .success: HelmSignal.success
            case .warning: HelmSignal.warning
            // Quiet, never `danger`: a probe that failed is not bad news.
            case .neutral: HelmText.quiet
            }
        }
    }

    /// What stands under the readings — the offer, the run that is already
    /// going, or the sentence that stands where neither belongs.
    ///
    /// One value, because the three are exclusive and a set of optionals can be
    /// several at once or none: a button drawn beside its own spinner is a
    /// second fifteen seconds of somebody's traffic one press away, and a button
    /// drawn beside the sentence explaining why there is no button is worse.
    enum Action: Equatable {
        case offer(String)
        case running(String)
        /// A tunnel that is not carrying the default route. The sentence, not a
        /// disabled button: nothing about *this* card can enable it, and a
        /// control that never becomes pressable is a control that has to be
        /// explained anyway.
        case notOffered(String)
    }

    /// Which reading a tile holds — the identity `ForEach` needs, and what a
    /// test asks about instead of matching a translated label.
    enum Reading: String { case uptime, down, up, speed }

    struct Tile: Identifiable {
        var id: Reading { kind }
        let kind: Reading
        let label: String
        let value: String
        /// The line under the figure. **Not optional, and that is the row's
        /// shape.** Three of the four columns had none, so the figures sat over
        /// nothing while the fourth carried a line — which was invisible while
        /// each column had a well behind it and is the whole structure now that
        /// they do not. A column with nothing to say under its figure is a
        /// column that has not been designed.
        let note: String
    }

    /// **The one dash in the strip, and it is the exception that proves the
    /// rule.** An absent reading is an absent tile everywhere else, because a
    /// dash there is a measurement of nothing; the speed tile stands empty
    /// because its emptiness is actionable — there is no passive way to read a
    /// link's throughput, and the button under it is the whole point.
    static let noReading = "—"

    /// **The hero's second line, as one value of three cases.**
    ///
    /// Not an optional string: «no country» is two different states and they
    /// must not be drawn the same. The traffic is in the tunnel and nobody has
    /// been told where it comes out — that is worth a sentence — against the
    /// traffic not being in the tunnel at all, where there is no exit country
    /// to be about and a line saying one is unknown would be answering a
    /// question nobody asked.
    enum Place: Equatable {
        /// The country, already named in Helm's own language.
        case named(String)
        /// In the tunnel; the exit has not answered.
        case unknown
        /// Nothing to say — the traffic is beside the tunnel, or the routing
        /// reading itself failed.
        case none
    }

    let tiles: [Tile]
    /// **The verdict alone, with no place in it.** It carried the country as
    /// its own tail until the strip became the page's hero; `place` is that
    /// half now, on a line of its own, and the switcher's accessibility value
    /// reads this one — which is why it has to stay a sentence that is true
    /// without the country rather than one with a dangling dash.
    let verdict: String
    let place: Place
    let mark: Mark
    let action: Action

    /// **`measuring` defaults to the state's own answer, not to false.**
    ///
    /// The state already carries whether a run is in flight — it is the engine's
    /// fact, on the wire for exactly that reason — and the parameter is the page
    /// putting the press in front of it during the moment the command is
    /// crossing the queue (`VPNViewModel.measuring`). Defaulted to `false` the
    /// two disagreed by construction: `VPNTunnelStrip(state)` drew the button
    /// over a running measurement, which is why every test here had to pass
    /// `measuring:` by hand to see the state the state was already in.
    init(_ state: VPNTunnelState, now: Date = Date(), measuring: Bool? = nil) {
        let measuring = measuring ?? state.measuring
        let facts = VPNTunnelFacts(since: state.since, bytesIn: state.bytesIn,
                                   bytesOut: state.bytesOut, speed: state.speed, now: now)
        var tiles: [Tile] = []
        // Each of the three is drawn only if it was actually read. Nil here is
        // never zero: nobody saw the tunnel come up, or the kernel had no
        // counters for its interface.
        if let uptime = facts.uptime {
            tiles.append(Tile(kind: .uptime, label: VPNStr.tileUptime,
                              value: HelmDates.span(uptime),
                              note: VPNStr.tunnelAndInterface(state.name, state.interface)))
        }
        if let bytesIn = facts.bytesIn {
            tiles.append(Tile(kind: .down, label: VPNStr.tileDown,
                              value: Bytes(Int(clamping: bytesIn)), note: VPNStr.bytesSince))
        }
        if let bytesOut = facts.bytesOut {
            tiles.append(Tile(kind: .up, label: VPNStr.tileUp,
                              value: Bytes(Int(clamping: bytesOut)), note: VPNStr.bytesSince))
        }
        tiles.append(Self.speedTile(facts, now: now))
        self.tiles = tiles

        switch state.exit {
        case .throughTunnel(let countryCode):
            verdict = VPNStr.trafficThroughTunnel
            // The place is named out of `Locale` in Helm's own language — never
            // the exit service's own spelling of it — and a code that is not a
            // region, or none at all, is `unknown` rather than a line that
            // trails off.
            place = countryCode.flatMap(VPNStr.country).map(Place.named) ?? .unknown
            mark = .success
        case .besideTunnel:
            verdict = VPNStr.trafficBesideTunnel
            place = .none
            mark = .warning
        case .unknown:
            verdict = VPNStr.trafficUnknown
            place = .none
            mark = .neutral
        }

        // **The offer belongs to the tunnel holding the default route, and to
        // no other.** One predicate, read here and by the engine that refuses
        // the same command (`VPNExitVerdict.carriesTheDefaultRoute`) — the view
        // is not the only thing that can send one, and a rule spelled twice is
        // a rule two targets can disagree about.
        if measuring {
            action = .running(VPNStr.measuring)
        } else if state.exit.carriesTheDefaultRoute {
            // «Measure again» rather than «Measure speed» once a figure sits in
            // the tile: the press replaces a stale number, it does not produce
            // the first one.
            action = .offer(facts.speed == nil ? VPNStr.measureSpeed : VPNStr.measureAgain)
        } else {
            action = .notOffered(VPNStr.speedIsTheRoutedTunnels)
        }
    }

    /// The fourth column: a figure once one has been asked for, and before that
    /// the offer with its price on it.
    ///
    /// The note always opens with the unit, because this column's value is two
    /// numbers and cannot carry one the way a byte figure does — and what
    /// follows the unit is the one thing worth qualifying it with. The age is
    /// there exactly when `VPNTunnelFacts.speedIsStale` says the figure can no
    /// longer stand as the link's speed now, which is that property's own doc
    /// comment and this is its only reader; a fresh reading keeps the unit
    /// alone. Written the other way round (an age under every reading) the
    /// property would be a promise with nothing keeping it.
    private static func speedTile(_ facts: VPNTunnelFacts, now: Date) -> Tile {
        guard let speed = facts.speed else {
            // **The unit alone, because the price is beside the button now.**
            // `speedNotYet` — fifteen seconds and some traffic — used to be
            // quoted here, on the reasoning that the column should say what the
            // button under it costs. The hero draws that button with its price
            // next to it, so quoting it here as well put the same clause on the
            // screen twice, 40 pt apart, and wrapped this column to two lines
            // while its three neighbours took one. A price belongs beside the
            // thing it is paid for.
            return Tile(kind: .speed, label: VPNStr.tileSpeed, value: noReading,
                        note: VPNStr.speedNote(nil))
        }
        return Tile(kind: .speed, label: VPNStr.tileSpeed,
                    // `Count`, not `Decimal`: the figure is a whole number of
                    // megabits and wants the language's digit grouping. Written
                    // `Decimal(speed.down)` it did not even reach `HelmUI` —
                    // that member takes a `Double` and `down` is an `Int`, so the
                    // call bound to `Foundation.Decimal.init(_: Int)` and drew its
                    // locale-independent description: «10000» for a 10 Gbit link.
                    value: "\(Count(speed.down)) ↓  \(Count(speed.up)) ↑",
                    note: VPNStr.speedNote(facts.speedIsStale
                        ? HelmDates.relative(speed.at, to: now) : nil))
    }
}

/// **The top of the VPN page: what the tunnel carrying your traffic is doing.**
///
/// The one thing this page can say that a card cannot. A card knows its own
/// configuration is connected; only the page knows which tunnel the traffic is
/// actually leaving through, how long it has been that way, and what it has
/// carried — so this reads one tunnel rather than being drawn four times over.
///
/// **It was the last block on the page and is the first.** As a `Form` section
/// under the grid of connections it sat below the fold on any Mac with more
/// than a few configurations, and the two things a person opens this page to
/// find out — is my traffic really in the tunnel, and where does it come out —
/// were a 13 pt line at the bottom of it. The shape is `KeepAwakeHero`'s, which
/// solved the same problem one module over: what is happening, in the type size
/// of a headline, above the settings rather than after them.
///
/// **No card of its own.** It rides on the first section's header with
/// `.helmSettingsColumn()`, the way `KeepAwakeSettingsPage.sessionHero` does —
/// a hero inside a card would be a card above the cards.
///
/// **And no wells.** The four columns were recessed fills
/// (`HelmSurface.wellFill`), which drew four boxes where the page wanted one
/// row of four readings — a card of cards. They are separated by whitespace
/// now, and what makes them read as one row is that every column has the same
/// three lines. Hairline rules between them were drawn and rejected by
/// looking: at 40 pt they begin at the label and end inside the note, so they
/// read as fragments rather than as structure.
struct VPNTunnelHero: View {
    private let tunnels: [VPNTunnelState]
    @Binding private var selected: String?
    private let now: Date
    /// The name of the tunnel a run is in flight for, or nil. A name rather
    /// than a flag, so a spinner turns over the tunnel being measured and not
    /// over whichever one the switcher happens to be showing.
    private let measuring: String?
    private let measure: (String) -> Void

    init(_ tunnels: [VPNTunnelState], selected: Binding<String?>, now: Date = Date(),
         measuring: String? = nil, measure: @escaping (String) -> Void) {
        self.tunnels = tunnels
        _selected = selected
        self.now = now
        self.measuring = measuring
        self.measure = measure
    }

    var body: some View {
        // Resolved here rather than in `init`, because the choice depends on a
        // binding: the page holds the selection and the engine rewrites the
        // list under it, and a value computed once at construction would be the
        // answer to a question asked before either could move.
        let switcher = VPNTunnelSwitcher(tunnels, selected: selected)
        return Group {
            if let chosen = switcher.chosen {
                live(switcher, chosen)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - With a tunnel up

    private func live(_ switcher: VPNTunnelSwitcher,
                      _ chosen: VPNTunnelState) -> some View {
        let strip = VPNTunnelStrip(chosen, now: now, measuring: measuring == chosen.name)
        return VStack(alignment: .leading, spacing: HelmSpace.s6) {
            headline(strip)
            // Under the headline and above the figures: the segments say which
            // tunnel every reading below is about, so they read as that row's
            // own heading rather than as a control belonging to the page.
            VPNTunnelSwitcherRow(switcher, selected: $selected)
            HStack(alignment: .top, spacing: HelmSpace.s4) {
                ForEach(strip.tiles) { column(_: $0) }
            }
            // The row takes the height of its tallest column and no more.
            // Without it a container taller than the strip stretches it: the
            // wells this replaced were photographed at 190 pt with 100 pt of
            // empty fill under the figures.
            .fixedSize(horizontal: false, vertical: true)
            action(strip, chosen)
        }
    }

    /// **The verdict, in the size a headline is set in.**
    ///
    /// Two lines rather than one sentence: the verdict answers «is my traffic
    /// in the tunnel» and the place answers «where does it come out», and the
    /// second used to be the tail of the first — the fact a person opens this
    /// page for, at the end of a sentence, in a caption. The place is quieter
    /// than the verdict because it qualifies it; it is the same size because it
    /// is the same headline.
    private func headline(_ strip: VPNTunnelStrip) -> some View {
        HStack(alignment: .top, spacing: HelmSpace.s5) {
            Image(systemName: strip.mark.symbol)
                .font(.system(size: 22))
                .foregroundStyle(strip.mark.tint)
                // Decoration: the sentence beside it says the same thing, and a
                // screen reader that read both would say it twice.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HelmSpace.s3) {
                // **22, the scale's step above body — not a number chosen by
                // eye.** It was 26, which is on no step of 10·11·13·16·22·40 and
                // `TypeScaleRatchetTests` counts every size that is not: the
                // ladder is only ever shortened, so a headline that wants its
                // own size has to argue for one rather than type it.
                Text(strip.verdict)
                    .font(.system(size: 22))
                    .fixedSize(horizontal: false, vertical: true)
                place(strip.place)
            }
        }
    }

    /// The second line, or nothing at all — `VPNTunnelStrip.Place` carries why
    /// «no country» is two states rather than one empty string.
    @ViewBuilder
    private func place(_ place: VPNTunnelStrip.Place) -> some View {
        switch place {
        case .named(let country):
            Text(country)
                .font(.system(size: 22))
                .foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
        case .unknown:
            // Body scale, not the headline's: it is a statement about the
            // check rather than an answer, and setting it at 26 pt would give
            // «not known» the weight of a country's name.
            Text(VPNStr.exitCountryUnknown)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.faint)
                .fixedSize(horizontal: false, vertical: true)
        case .none:
            EmptyView()
        }
    }

    /// One reading: what it is, the figure, and the line that qualifies it.
    ///
    /// `maxWidth: .infinity` on each is what makes the four equal, and the only
    /// thing that does now that there is no fill to see the edges of.
    private func column(_ tile: VPNTunnelStrip.Tile) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            Text(tile.label)
                // 10, the scale's bottom step: a caption over a figure.
                .font(.system(size: 10))
                .foregroundStyle(HelmText.quiet)
                .lineLimit(1)
            Text(tile.value)
                .helmMetricFigure()
            Text(tile.note)
                .font(.system(size: 10))
                .foregroundStyle(HelmText.faint)
                // Wrapping rather than truncating: a note that loses its tail
                // loses the interface out of «incy · utun8», and a tunnel named
                // at length in System Settings is an ordinary Mac. The columns
                // are top-aligned, so a second line lengthens one column
                // without moving a figure beside it.
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The offer, the run that is already going, or the sentence that stands
    /// where neither belongs — `VPNTunnelStrip.Action` carries why the three
    /// are one value rather than three optionals.
    @ViewBuilder
    private func action(_ strip: VPNTunnelStrip, _ chosen: VPNTunnelState) -> some View {
        switch strip.action {
        case .offer(let word):
            HStack(spacing: HelmSpace.s4) {
                Button(word) { measure(chosen.name) }
                // The price of the press, beside the press rather than under a
                // figure that does not exist yet.
                Text(VPNStr.speedNotYet)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .running(let word):
            HStack(spacing: HelmSpace.s3) {
                ProgressView().controlSize(.small)
                Text(word)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
            }
        case .notOffered(let sentence):
            Text(sentence)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - With nothing up

    /// **The slot answers even with nothing to be about.**
    ///
    /// The section used to be absent altogether, which is right for a block
    /// three quarters of the way down a page and wrong for the first one on it:
    /// a slot that disappears takes the page's shape with it. Quiet rather than
    /// marked — nothing is wrong with a Mac that has no tunnel up, so there is
    /// no glyph and no colour, only the sentence and what to do about it.
    private var empty: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            Text(VPNStr.noTunnelUp)
                .font(.system(size: 22))
                .foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
            Text(VPNStr.noTunnelUpNote)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
