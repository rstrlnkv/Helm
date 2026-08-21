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

    /// What stands under the readings — the offer, the run that is already
    /// going, or the sentence that stands where neither belongs.
    ///
    /// One value, because the three are exclusive and a set of optionals can be
    /// several at once or none: a button drawn beside its own spinner is a
    /// second twenty seconds of somebody's traffic one press away, and a button
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
    let action: Action
    /// **How long the arc under a running measurement is drawn against.**
    ///
    /// This link's own last run, and a measured fallback before there is one. It
    /// was a constant in the view — 22 s, taken on one Mac on one link on one
    /// afternoon, under a comment saying it should not be a constant at all. The
    /// port times its own run now and the reading carries the length
    /// (`VPNSpeedReading.took`), so from the second measurement onwards the arc
    /// is a fact about the link in front of the reader;
    /// `NetworkQualitySpeed.typicalRun` is what stands before that, and it is
    /// the same figure with its measurement written at it.
    ///
    /// Here rather than in the view for the reason this whole type exists: a
    /// number the page draws is content, and content that lives in a `body` has
    /// prose instead of a test.
    ///
    /// Still a **length**, never a stage — the engine knows only whether a run
    /// is in flight (`VPNEngine.measuringSpeed` is a name or nothing) — so the
    /// arc goes on claiming the clock rather than the work.
    let expectedWait: TimeInterval

    /// **Whether a run is in flight for the tunnel this strip is about.**
    ///
    /// Read off `action` rather than stored beside it, so the two cannot
    /// disagree: `.running` *is* the state, and a second field meaning the same
    /// thing is a field somebody has to remember to set. The speed card wears
    /// the measuring slot while this is true (`helmMeasuringSlot`) — the figure
    /// already there drops a rank rather than disappearing, because it is still
    /// the only reading the person has.
    var isMeasuring: Bool {
        if case .running = action { true } else { false }
    }

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
        expectedWait = facts.speed?.took ?? NetworkQualitySpeed.typicalRun
        exclusions = VPNStr.excluded(state.excluded)

        switch state.exit {
        case .throughTunnel(let countryCode):
            verdict = VPNStr.trafficThroughTunnel
            // The place is named out of `Locale` in Helm's own language — never
            // the exit service's own spelling of it — and a code that is not a
            // region, or none at all, is `unknown` rather than a line that
            // trails off.
            place = countryCode.flatMap(VPNStr.country).map(Place.named) ?? .unknown
        case .besideTunnel:
            verdict = VPNStr.trafficBesideTunnel
            place = .none
        case .unknown:
            verdict = VPNStr.trafficUnknown
            place = .none
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
    /// there exactly when `VPNTunnelFacts.speedShowsItsAge` says there is one
    /// to draw; a fresh reading keeps the unit alone. Written the other way
    /// round (an age under every reading) the property would be a promise with
    /// nothing keeping it.
    ///
    /// **`speedShowsItsAge`, not `speedIsStale`, and the two came apart here.**
    /// This line read the staleness — «may the figure stand as live» — as «show
    /// the age», so a reading stamped ahead of this page's clock, which is
    /// stale for that very reason, drew «Мбит/с · через 5 мин.»: a time still
    /// to come under a figure taken in the past
    /// (`AnAgeIsNeverAheadOfTheClockTests`).
    private static func speedTile(_ facts: VPNTunnelFacts, now: Date) -> Tile {
        guard let speed = facts.speed else {
            // **The unit alone.** A price tag — «about 15 s, spends traffic» —
            // used to be quoted here, on the reasoning that the column should
            // say what the button under it costs, and it wrapped this column to
            // two lines while its three neighbours took one. It moved beside the
            // button, then off the screen entirely when the button stopped
            // quoting it, and `VPNStr.speedNotYet` went with it: the figure in
            // it had never been measured and was five seconds short of the
            // truth (`NetworkQualitySpeed.typicalRun`), in eight languages.
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
                    //
                    // **Each arrow sits against its own digits, and there is one
                    // space between the pair.** It was `1176 ↓  298 ↑` — a space
                    // before each arrow and two between the readings — which
                    // measured 101.0 pt for a four-digit reading against the
                    // 88.9 this draws. That is the whole difference between the
                    // figure standing at 16 pt and `helmMetricFigure` shrinking
                    // it at the narrowest pane the window allows. An arrow is
                    // the unit of the number beside it, not a word of its own.
                    value: "\(Count(speed.down))↓ \(Count(speed.up))↑",
                    // `.short`, and **never `.abbreviated`** however well its
                    // name suits a 116 pt column: that style prints «-1 мин» in
                    // Russian and «-1 min» in French — a signed delta rather
                    // than an age, under a figure that is already two signed
                    // readings. `HelmDates.AgeStyle` has two cases so the third
                    // cannot be asked for here.
                    note: VPNStr.speedNote(facts.speedShowsItsAge
                        ? HelmDates.age(speed.at, to: now, style: .short) : nil))
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
    /// **When this page saw a run begin, or nil because it did not.**
    ///
    /// The engine says *whether* a measurement is in flight and nothing else —
    /// no stage, no fraction, no byte count (`VPNEngine.measuringSpeed` is a
    /// name or nothing). So the only fact anybody has about how far along a run
    /// is, is the clock, and the only page entitled to read that clock is one
    /// that watched the run start. Seeded `nil` rather than `Date()`, which is
    /// the same law the `shown` property above obeys from the other end: a page
    /// opened *into* a run never saw it begin, and a stamp taken at `init` would
    /// be a twenty-second-old run drawn as a fresh one. `HelmExpectedWait`
    /// answers `nil` with the indeterminate spinner this page has always drawn.
    @State private var measureStarted: Date?

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
        // **The stamp is taken where the run begins, and only there.** Not in
        // `init` — that is every rebuild the engine causes, and it causes dozens
        // behind one connect, so the clock would restart under a wait already
        // running. Not inside `measure`'s closure either: a press is not a
        // start, the engine refuses a tunnel that is not carrying the default
        // route, and `VPNViewModel.measuring` puts the press in front of the
        // engine's answer for as long as the command is crossing the queue.
        // Nil → a name is the one transition that is a run beginning; a name →
        // nil is it ending, and the stamp goes with it so the next page opened
        // into a run inherits nothing.
        //
        // No `withAnimation` around it, and that is not an oversight: what this
        // value changes is *which* indicator draws, and the handover between
        // them is a cut on purpose — the two say different things and a
        // cross-fade between them would be the app hedging.
        .onChange(of: measuring) { was, running in
            measureStarted = running == nil ? nil : (was == nil ? Date() : measureStarted)
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
    /// capsule row. **And there is no departure left**: this block kept a mark
    /// beside its sentence on the reasoning that Keep Awake can do without one
    /// because none of its states is alarming. The reasoning survives the
    /// glyph's removal — the alarming state is still the reason this block
    /// exists — but the glyph was carrying colour and nothing else, and the
    /// note on `headline` has what it cost to draw it.
    private func live(_ switcher: VPNTunnelSwitcher,
                      _ chosen: VPNTunnelState) -> some View {
        let strip = VPNTunnelStrip(chosen, now: now, measuring: measuring == chosen.name)
        return VStack(spacing: HelmSpace.s6) {
            // **The figure block is `KeepAwakeHero`'s, spacing and all.** That
            // page draws its verdict, its caption and its row of verbs in one
            // `VStack(spacing: s4)` with `s6` on top of the row, and this one
            // drew the three as siblings at `s6` — 18 pt from caption to verbs
            // against Keep Awake's 26, photographed at 29.5 and 39.0 from the
            // caption's cap. Two heroes that are the same shape on purpose must
            // not be two rhythms.
            VStack(spacing: HelmSpace.s4) {
                headline(strip)
                verbs(switcher, strip, chosen)
                    .padding(.top, HelmSpace.s6)
            }
            // **The words are inset like a heading; the surface is not.**
            //
            // The whole block sits in the cards' own column
            // (`VPNSettingsPage.heroAndTitle` backs it out of the header inset),
            // and the words go back in by the same amount, because a heading
            // belongs level with what the rows below *say* —
            // `HelmLayout.groupedHeaderOutset` carries both halves of that
            // ruling. Written the other way round, as a negative padding on the
            // readings alone, it drew nothing at all: `.clipped()` sits at this
            // view's root for the cross-fade, and a clip takes back whatever a
            // negative padding inside it gives.
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
    ///
    /// **And the verdict wore a glyph, which it no longer does.** A tick or a
    /// warning triangle beside the sentence, `accessibilityHidden` because the
    /// sentence already said it — so it was carrying colour and nothing else,
    /// and it was carrying it badly: photographed, the mark's own ink sat
    /// 5.75 pt above the cap band it claimed to be optically centred on, and
    /// standing inside the centred row it pushed the sentence 16.25 pt to the
    /// right of the caption underneath it. Both were arithmetic against a line
    /// box rather than against the drawing. `KeepAwakeHero` carries its verdict
    /// in words alone at the same rank, and now so does this — which is what
    /// `TheStripDrawsOnlyWhatIsKnownTests` § 5 already called the rule.
    @ViewBuilder
    private func headline(_ strip: VPNTunnelStrip) -> some View {
        Text(strip.verdict)
            .font(HelmText.heroFont)
            .helmHeroSentence()
        if let caption = caption(strip) {
            Text(caption)
                .font(HelmText.rowTitle)
                .foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
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
                VPNTunnelSwitcherRow(switcher.drawn(beside: strip.action),
                                     selected: $selected)
                switch strip.action {
                case .offer(let word):
                    Button(word) { measure(chosen.name) }
                        .controlSize(.large)
                        .buttonStyle(.bordered)
                        // **30, which is what the segments and the spinner
                        // beside it are.** A `.large` bordered button measures
                        // 28, and on a Mac with one tunnel it is now the only
                        // thing on the row — so the block stood 2 pt shorter
                        // there and dropped back the moment a second tunnel came
                        // up. `helmMeasuredHeight` would ramp that rather than
                        // snap it, which is a 0.30 s move of the whole page for
                        // a difference nobody asked for.
                        .frame(height: 30)
                case .running(let word):
                    HStack(spacing: HelmSpace.s3) {
                        // **The one thing on this page that says how far in the
                        // wait is** — and it says it about the wait, not about
                        // the measurement, because the measurement reports
                        // nothing until it is over. Same slot and same 16 pt as
                        // the spinner it replaces, so the row it stands in does
                        // not move; when the clock runs out it *becomes* that
                        // spinner again rather than filling up and sitting
                        // there. `HelmExpectedWait` carries the argument.
                        HelmExpectedWait(started: measureStarted,
                                         expected: strip.expectedWait)
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
            // **Only the speed card, and only while its own run is going.** The
            // slot is the one place on this page that says a newer figure is on
            // its way; drawn on all four it would be saying it about three
            // readings nobody asked for. `false` is inert — full ink, no border,
            // a paused schedule (`HelmMeasuringSlot`).
            ForEach(strip.tiles) { tile in
                column(tile).helmMeasuringSlot(strip.isMeasuring && tile.kind == .speed)
            }
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
    /// `maxWidth: .infinity` on each is what makes the four equal in width, and
    /// `HelmSpace.s5` is a card's own inner padding — the same number a
    /// connection card pays, because this is the same surface.
    ///
    /// **`maxHeight: .infinity` is what makes them equal in height, and the row
    /// went without it.** The row's own comment claimed «every column has the
    /// same three lines», which was true while every note was one line and is
    /// not a rule anything held: measured on the page at the narrowest pane it
    /// allows, the four stood at 76 / 94 / 94 / 81, and a configuration named at
    /// length in System Settings breaks the family at every pane. Under the
    /// row's `.fixedSize(vertical:)` the `HStack` still takes the height of its
    /// tallest card and no more — this only spends that height on the other
    /// three — and `alignment: .top` on the row keeps every word where it was.
    /// `TheReadingsAreOneRowTests` reads it off the drawing, because a SwiftUI
    /// idiom is not a contract and no value carries the answer.
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
        // «Скорость, 343, incy · utun8» as one VoiceOver stop, the way
        // `HelmMetricStrip` reads its two. Left apart, the four cards are twelve
        // stops and three of them say the figure before the word naming it.
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    /// No mark, which used to be the one place this block followed the model
    /// and is now both of them: nothing is wrong with a Mac that has no tunnel
    /// up, and a glyph beside that sentence would be answering a question
    /// nobody asked.
    private var empty: some View {
        VStack(spacing: HelmSpace.s4) {
            Text(VPNStr.noTunnelUp)
                .font(HelmText.heroFont)
                .foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
            Text(VPNStr.noTunnelUpNote)
                .font(HelmText.rowTitle)
                .foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
        }
        .frame(maxWidth: .infinity)
        // The same inset the live state's words take, for the same reason: the
        // block is in the cards' column and its text is not.
        .padding(.horizontal, HelmLayout.groupedHeaderOutset)
    }
}
