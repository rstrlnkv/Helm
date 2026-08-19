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
    /// **What the tunnel carries around itself, or nil when it carries
    /// nothing.**
    ///
    /// The verdict says the traffic goes through the tunnel and the page's own
    /// footer says «all of this Mac's traffic», and on the machine this was
    /// written against both are false: `17.0.0.0/8` — Apple's whole network — is
    /// declared outside the tunnel, so iCloud, the App Store and iMessage leave
    /// with the real address under a green tick. Helm had been reading those
    /// lines and discarding them (`VPNExcludedRoutes`).
    let exclusions: String?
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
        exclusions = VPNStr.excluded(state.excluded)

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

    /// Natural height of whatever the block is showing, so it can ramp between
    /// two of them instead of snapping.
    ///
    /// **This block copied `KeepAwakeHero`'s placement and none of its motion**,
    /// and the whole page paid for it: measured off the render, the section
    /// title under the hero sat at five different heights across five ordinary
    /// states of one Mac, and two of those transitions happen with nobody
    /// touching anything. The exit country arriving moved the page 16 pt; Helm
    /// first learning the tunnel's uptime moved it 8; pressing a segment moved
    /// it 46 in one frame. `KeepAwakeHero`'s own comment is about exactly this —
    /// «a fade that snaps the page by 20 pt underneath somebody's eyes is the
    /// fade being blamed for a jump it did not cause».
    @State private var bodyHeight: CGFloat?
    /// What is **drawn**, as against what has arrived. Seeded from the incoming
    /// value rather than from a constant: a page opened on a live tunnel must
    /// show it, not play the empty state swapping into it (`KeepAwakeHero` says
    /// why an optional falling back to the property is a check that cannot
    /// fail).
    @State private var shown: [VPNTunnelState]

    init(_ tunnels: [VPNTunnelState], selected: Binding<String?>, now: Date = Date(),
         measuring: String? = nil, measure: @escaping (String) -> Void) {
        self.tunnels = tunnels
        _selected = selected
        self.now = now
        self.measuring = measuring
        self.measure = measure
        _shown = State(initialValue: tunnels)
    }

    var body: some View {
        // Resolved here rather than in `init`, because the choice depends on a
        // binding: the page holds the selection and the engine rewrites the
        // list under it, and a value computed once at construction would be the
        // answer to a question asked before either could move.
        let switcher = VPNTunnelSwitcher(shown, selected: selected)
        return Group {
            if let chosen = switcher.chosen {
                live(switcher, chosen).transition(.opacity)
            } else {
                empty.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The measurement alone, and **not** `helmAccordion`: this block has no
        // open state and never collapses. What it needs is to be the size of
        // whatever it is showing, so the cross-fade has an animating frame for
        // its clip to be taken from.
        .helmMeasuredHeight($bodyHeight)
        .frame(height: bodyHeight, alignment: .top)
        .clipped()
        // Where the value **lands**, not where it was set: the engine publishes
        // these and a transaction is the only thing that makes them move
        // (ARCHITECTURE.md § Motion). `.animation(_:value:)` on the outside was
        // measured doing nothing for the same shape one module over.
        .onChange(of: tunnels) { _, arrived in
            withAnimation(HelmMotion.disclosure) { shown = arrived }
        }
    }

    // MARK: - With a tunnel up

    /// **The shape `KeepAwakeHero` draws, measured off it rather than
    /// remembered.**
    ///
    /// Rendered and looked at before this was written, because the shape is not
    /// what its name suggests: the figure there is a *sentence* at 40 pt light,
    /// centred, in `HelmText.quiet` — «Mac засыпает как обычно» — with a 13 pt
    /// caption under it and a centred row of capsule verbs under that. No
    /// glyph: the state is carried by words.
    ///
    /// So the verdict takes the 40 pt slot, the country and the exclusions
    /// become the caption, and the segments and the measure button become the
    /// capsule row. The one departure is the mark, which stays — `KeepAwakeHero`
    /// can do without one because none of its states is alarming, and this
    /// block's whole reason for existing is the state that is.
    private func live(_ switcher: VPNTunnelSwitcher,
                      _ chosen: VPNTunnelState) -> some View {
        let strip = VPNTunnelStrip(chosen, now: now, measuring: measuring == chosen.name)
        return VStack(spacing: HelmSpace.s6) {
            // **The words are inset like a heading; the surface is not.**
            //
            // The whole block sits in the cards' own column
            // (`VPNSettingsPage.heroAndTitle` backs it out of the header inset),
            // and these two go back in by the same amount, because a heading
            // belongs level with what the rows below *say* —
            // `HelmLayout.groupedHeaderOutset` carries both halves of that
            // ruling. Written the other way round, as a negative padding on the
            // readings alone, it drew nothing at all: `.clipped()` sits at this
            // view's root for the cross-fade, and a clip takes back whatever a
            // negative padding inside it gives.
            headline(strip)
                .padding(.horizontal, HelmLayout.groupedHeaderOutset)
            verbs(switcher, strip, chosen)
                .padding(.horizontal, HelmLayout.groupedHeaderOutset)
            readings(strip)
        }
        .frame(maxWidth: .infinity)
    }

    /// The verdict at the size a page's own state is set in, and one caption
    /// under it.
    ///
    /// **The country and the exclusions are one line, not two.** They were a
    /// 16 pt line and an 11 pt line under a 22 pt heading — three type sizes for
    /// one thought, and two of the page's five measured heights. Joined by the
    /// dot this module already punctuates with (`VPNStr.note`), they are one
    /// caption in the slot `KeepAwakeHero` puts «Ни одно правило не включено» in.
    private func headline(_ strip: VPNTunnelStrip) -> some View {
        VStack(spacing: HelmSpace.s4) {
            HStack(alignment: .top, spacing: HelmSpace.s4) {
                Image(systemName: strip.mark.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(strip.mark.tint)
                    // Optically centred on the first line of a 40 pt sentence
                    // rather than hung from its top: the cap band of 40 pt SF
                    // is about 29 pt and the mark is 22, so half the difference
                    // is what puts the two centres together. `s3` is the step
                    // that lands there; there is no half-step on the ladder and
                    // this does not need one.
                    .padding(.top, HelmSpace.s3)
                    // Decoration: the sentence beside it says the same thing,
                    // and a screen reader that read both would say it twice.
                    .accessibilityHidden(true)
                Text(strip.verdict)
                    .font(.system(size: 40, weight: .light))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let caption = caption(strip) {
                Text(caption)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.faint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// «Финляндия · кроме локальной сети и серверов Apple», or whichever half
    /// of it there is — and nil when there is neither, so the slot is absent
    /// rather than empty.
    private func caption(_ strip: VPNTunnelStrip) -> String? {
        let place: String? = switch strip.place {
        case .named(let country): country
        case .unknown: VPNStr.exitCountryUnknown
        case .none: nil
        }
        let parts = [place, strip.exclusions].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// **The verbs, as capsules in a centred row** — the shape
    /// `KeepAwakeHero` gives its presets.
    ///
    /// The segments and the measure button share the row because they are the
    /// same kind of thing here: the only two things this block can be told to
    /// do. A tunnel that is not carrying the traffic has no button to offer,
    /// and its sentence goes under the row rather than into it — a paragraph
    /// among capsules is not a capsule.
    @ViewBuilder
    private func verbs(_ switcher: VPNTunnelSwitcher, _ strip: VPNTunnelStrip,
                       _ chosen: VPNTunnelState) -> some View {
        VStack(spacing: HelmSpace.s4) {
            HelmWrappingRow(spacing: HelmSpace.s4, lineSpacing: HelmSpace.s3,
                            alignment: .center) {
                VPNTunnelSwitcherRow(switcher, selected: $selected)
                switch strip.action {
                case .offer(let word):
                    Button(word) { measure(chosen.name) }
                        .controlSize(.large)
                        .buttonStyle(.bordered)
                case .running(let word):
                    HStack(spacing: HelmSpace.s3) {
                        ProgressView().controlSize(.small)
                        Text(word)
                            .font(HelmText.rowDetail)
                            .foregroundStyle(HelmText.quiet)
                    }
                    .frame(height: 30)
                case .notOffered:
                    EmptyView()
                }
            }
            if case .notOffered(let sentence) = strip.action {
                Text(sentence)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// **The readings as four cards**, on the surface the connection cards use.
    ///
    /// They were one well with full-height hairlines between them, which said
    /// «four readings of one tunnel» — and that is the truer sentence, since it
    /// is one `utunN`, one moment it came up, and one `ifdata` read. Four cards
    /// say «four independent things». The owner chose the cards after seeing
    /// both drawn, so what this comment records is the trade rather than an
    /// argument: the page gains one card system from top to bottom, and loses
    /// the mark that told its hero from its list.
    ///
    /// `HelmSurface.wellFill` and `HelmRadius.card` because those are what a
    /// connection card is made of — two card systems on one page is the defect
    /// this house has already paid for twice, and a *third* fill here would be
    /// exactly that.
    private func readings(_ strip: VPNTunnelStrip) -> some View {
        // The gap the connections grid uses between its own cards, so the two
        // rows are one rhythm rather than two.
        HStack(alignment: .top, spacing: HelmSpace.s5) {
            ForEach(strip.tiles) { column(_: $0) }
        }
        // The row takes the height of its tallest card and no more. Without it a
        // container taller than the row stretches it: the wells an earlier
        // edition drew were photographed at 190 pt with 100 pt of empty fill
        // under the figures.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// One reading, as its own card.
    ///
    /// `maxWidth: .infinity` on each is what makes the four equal, and
    /// `HelmSpace.s5` is a card's own inner padding — the same number a
    /// connection card pays, because this is the same surface.
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
                // at length in System Settings is an ordinary Mac.
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HelmSpace.s5)
        .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
            .fill(HelmSurface.wellFill))
    }

    // MARK: - With nothing up

    /// **The state `KeepAwakeHero` is drawn around**, and the best argument for
    /// taking its shape whole: «Mac засыпает как обычно» is that page's idle,
    /// set in the same 40 pt as its countdown. «Ни один туннель не поднят» is
    /// this one's, and it now sits in the same slot at the same size.
    ///
    /// No mark, and that is the one place this block does follow the model:
    /// nothing is wrong with a Mac that has no tunnel up, and a glyph beside
    /// that sentence would be answering a question nobody asked.
    private var empty: some View {
        VStack(spacing: HelmSpace.s4) {
            Text(VPNStr.noTunnelUp)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(HelmText.quiet)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(VPNStr.noTunnelUpNote)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.faint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        // The same inset the live state's words take, for the same reason: the
        // block is in the cards' column and its text is not.
        .padding(.horizontal, HelmLayout.groupedHeaderOutset)
    }
}
