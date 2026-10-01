// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmRuntime
import HelmUI

/// The log, while it is being written — one card per launch of the app.
///
/// Not a diagnostics dashboard: it invents no figure and computes nothing it
/// cannot say how. It shows the lines the app already writes — the same `write`,
/// the same format, the same truth — so that watching Helm misbehave does not
/// mean leaving it, finding `~/Library/Logs/Helm` and reading what already
/// happened.
///
/// **Folded, never edited.** A launch is a card (`LogSessions`), the burst of
/// lines a launch writes while it switches its modules on is one fold, and a line
/// written again and again in a row is one row with a count. Every one of those
/// is drawn from the lines in the order they arrived, none is dropped, and
/// «Copy log» hands back the lines expanded, in the file's own format
/// (`LogPresentation.lines`). What the page decides is what to show first; what
/// it says is what the file holds.
///
/// Shown on every build, because this is also where the log is switched on. It
/// used to be dev-only, and the switch lived in Settings under "Diagnostics" —
/// two places for one subject, and the one a person is told to press when they
/// report a problem was not the one named after it.
///
/// **The controls are the window's, not the page's.** Level, module, search,
/// Follow, Copy and the rest live in the window's toolbar like every other
/// page's (`toolbarContent`); the page is the cards and a footer. The permanent
/// band that held the writing switch is gone — the switch is one line in the
/// «More actions» menu, which is as often as anyone needs it.
struct LogView: View {
    /// Set by the settings window, where the page's header lives in the
    /// window's toolbar instead of in this stack.
    @Environment(\.helmPageBar) private var pageBar

    /// Where the lines come from, and whether there is a log on disk behind them.
    ///
    /// The app passes the log; the defaults are what every caller uses. They are
    /// parameters because a measurement of this page otherwise reads whatever
    /// this Mac happens to have logged — the row's own geometry was unmeasurable
    /// for exactly that reason, and the filter row's overflow in Russian was
    /// found on a page with no lines in it because that was the only page a
    /// harness could draw.
    var source: () -> [LogEntry] = { HelmLog.shared.recentEntries() }
    var storedLog: () -> Bool = { HelmLog.anyFileExists() }

    /// Polled rather than subscribed. A log has no interesting event to observe
    /// — it has a tail — and one timer that exists while the page is on screen
    /// is cheaper to reason about than a stream that has to be finished.
    @State private var entries: [LogEntry] = []
    /// A file can appear and go without this process doing it — a rollover, a
    /// person emptying the folder — so it is re-read on the same tick the lines
    /// are, never remembered from the first read.
    @State private var hasStoredLog = false
    @State private var minimumLevel: LogLevel = .info
    @State private var chosen: Set<String> = []
    @State private var query = ""
    @State private var following = true
    /// Where the reader is, by the line (`LogReaderPlace`).
    @State private var place = LogReaderPlace()
    /// The launches whose start-up fold is open, by the id of their first line.
    @State private var openStartups: Set<LogEntry.ID> = []
    @State private var tick: RepeatingTick?
    @State private var loggingOn = LogPolicy.isEnabled(
        version: AppBuild.shortVersion ?? "0",
        override: AppSettings.loggingOverride)

    /// Read once per body: the split, the filters and the folds are one pass
    /// over at most a thousand lines, and every part of the page below — the
    /// cards, the toolbar's Copy, the footer, the Follow key — must see the
    /// same one.
    private var presented: LogPresentation {
        LogPresentation.build(entries, minimumLevel: minimumLevel, categories: chosen, query: query)
    }

    var body: some View {
        let page = presented
        VStack(spacing: 0) {
            // **A band, not a scroll edge — and `HelmPageHeader` directly is
            // how a page says so.** The other pages hand their content to
            // `helmPageHeader`, which lays the strip over a scroll view and
            // gives it the material and the rule. This page is a scroll view
            // and a footer stacked, and the scroll view is several levels
            // inside the stack the band is applied to, so nothing ever
            // scrolls *under* the band. A material over content that never
            // passes behind it would blur nothing, and the rule would be a
            // hairline between a header and a card — the line measured away
            // in `ThePageHeaderCarriesNoRuleTests`, back under a new name. The
            // 52 pt strip is the same either way; only the edge is not.
            //
            // `bleeds: true` like every other full-width page: without it the
            // header caps at `HelmLayout.settingsColumn` and centres, which put
            // its icon at x = 53 against the rows' x = 21 on this pane.
            //
            // In the settings window the header is in the window's toolbar
            // (`PageBarStyle`), and this row is not drawn at all.
            if pageBar == nil {
                HelmPageHeader(symbol: "text.alignleft", tint: .gray,
                               title: AppStr.logPane,
                               bleeds: true, standsOnStillContent: true)
            }
            lines(page)
            Divider()
            footer(page)
        }
        // **The same fact as `standsOnStillContent:` above, for the other
        // placement of the same band.** This page reports `false` for the
        // scroll and always will — not because it has no scroll view, which it
        // does, in `lines`, but because `helmPageBar` is applied here, to the
        // outer `VStack(spacing: 0)`, with that scroll view several levels
        // inside it. The five pages that rely on the scroll trigger hand their
        // own `Form` straight to `helmPageHeader` instead, where the closure
        // fires. So before this the band was structurally incapable of
        // lighting: nothing above it against the `Divider()`s below. The header
        // in the row takes the fact as an argument because it is right here;
        // the header in the window's toolbar is drawn by `helmToolbarBackdrop`
        // a window away, and a preference is how it hears.
        .helmPageStandsOnStillContent()
        .helmPageBar(title: AppStr.logPane)
        // The token is the page's own key, the one `SettingsToolbar.pageKey`
        // answers for `.log`. Declared unconditionally: the toolbar swaps a
        // whole bar when the *shape* of what a page declares changes, and this
        // page's shape never does.
        .helmWindowToolbar(toolbarContent(page), token: "log")
        .onAppear {
            refresh()
            // One second: the log is read, not animated, and a person watching
            // it is reading the line that just arrived rather than counting
            // frames.
            let made = RepeatingTick(interval: 1) { refresh() }
            tick = made
            made.set(active: true)
        }
        .onDisappear {
            tick?.set(active: false)
            tick = nil
        }
    }

    // MARK: - The window's toolbar

    /// The three tabs and the level each one means. One declaration, so the
    /// toolbar's segments and the filter they set cannot disagree.
    private static let levelTabs: [(id: String, level: LogLevel)] = [
        ("all", .info), ("warn", .warn), ("error", .error),
    ]

    /// **What the page asks of the window's toolbar**, in one place: the level
    /// as the centred tabs, then the capsule — module filter, Follow, Copy and
    /// the «More actions» menu — and the search.
    ///
    /// Follow is a toggle with a face: its state is its glyph (an open eye when
    /// following, a slashed one when not) and never a tint. The old glyph button
    /// lit up in the accent colour when it was on; this one does not, because a
    /// state carried by colour alone is not read by everyone. Its word is in the
    /// tooltip and the accessibility label, as it always was, and what it is
    /// doing is the accessibility value.
    private func toolbarContent(_ page: LogPresentation) -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "all", title: AppStr.logLevelAll, symbol: "list.bullet"),
                   HelmToolbarTab(id: "warn", title: AppStr.logLevelWarnings,
                                  symbol: "exclamationmark.triangle"),
                   HelmToolbarTab(id: "error", title: AppStr.logLevelErrors,
                                  symbol: "xmark.octagon")],
            selectedTab: Binding(
                get: { Self.levelTabs.first { $0.level == minimumLevel }?.id ?? "all" },
                set: { id in minimumLevel = Self.levelTabs.first { $0.id == id }?.level ?? .info }),
            actions: [
                // Built from what has arrived, so it names the modules that
                // spoke rather than the nine that exist. A line with no module
                // (an unreadable one) has no entry of its own here: it is not
                // something to filter *to*.
                HelmToolbarAction(id: "modules",
                                  title: chosen.isEmpty ? AppStr.logAllModules
                                                        : AppStr.logSomeModules(chosen.count),
                                  symbol: "line.3.horizontal.decrease",
                                  menu: [HelmToolbarMenuItem(id: "all", title: AppStr.logAllModules,
                                                             isOn: chosen.isEmpty) { chosen = [] }]
                                    + LogFilter.categories(in: entries).filter { !$0.isEmpty }.map { category in
                                        HelmToolbarMenuItem(id: category, title: category,
                                                            isOn: chosen.contains(category)) {
                                            if chosen.contains(category) { chosen.remove(category) }
                                            else { chosen.insert(category) }
                                        }
                                    }),
                HelmToolbarAction(id: "follow", title: AppStr.logFollow,
                                  symbol: "eye", isOn: following,
                                  face: HelmToolbarToggleFace(offSymbol: "eye.slash",
                                                              onValue: AppStr.logFollowing,
                                                              offValue: AppStr.logNotFollowing)) {
                    following.toggle()
                },
                HelmToolbarAction(id: "copy", title: AppStr.copyLog, symbol: "doc.on.doc",
                                  isEnabled: !page.lines.isEmpty) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.pasteboardText(page.lines), forType: .string)
                },
                // Whether anything is written to the file at all, and what ends
                // up in it. Dev builds always log — the file is the evidence a
                // build is triaged on — so the switch is theirs to read, not to
                // change.
                HelmToolbarAction(id: "more", title: HelmA11y.moreActions, symbol: "ellipsis", menu: [
                    HelmToolbarMenuItem(id: "write", title: AppStr.writeLog, isOn: loggingOn,
                                        isEnabled: !AppBuild.isDev) {
                        let on = !loggingOn
                        loggingOn = on
                        AppSettings.loggingOverride = on
                        HelmLog.shared.setEnabled(on)
                    },
                    HelmToolbarMenuItem(id: "reveal", title: AppStr.revealLog, isOn: false) {
                        HelmReveal.inFinder(HelmLog.fileURL.path)
                    },
                    HelmToolbarMenuItem(id: "clear", title: AppStr.clearLog, isOn: false,
                                        isEnabled: Self.canClear(entries: entries,
                                                                 storedLog: hasStoredLog)) {
                        // Both, because there is one Clear now and a person
                        // pressing it means the log, not the window onto it.
                        HelmLog.shared.clear()
                        HelmLog.shared.clearTail()
                        entries = []
                        hasStoredLog = false
                    },
                ]),
            ],
            search: HelmToolbarSearch(prompt: AppStr.logSearch, text: $query))
    }

    // MARK: - The cards

    /// The zero-height end of the list, what Follow scrolls to. Below the last
    /// card and above the page's own bottom padding, so «at the end» is the
    /// padding's height and no more (see `cardView` for what that was measured
    /// to hold for).
    private static let endMarker = "helm.log.end"

    /// What the person chose to see; a change of it is a different page, and the
    /// reader's line is not held across it (`LogReaderPlace.forget`).
    private struct FilterKey: Equatable {
        let level: LogLevel
        let chosen: Set<String>
        let query: String
    }

    /// What the follow rule watches; see the handler in `lines`.
    private struct FollowKey: Equatable {
        let following: Bool
        let first: LogEntry.ID?
        let last: LogEntry.ID?
        let count: Int
    }

    @ViewBuilder private func lines(_ page: LogPresentation) -> some View {
        if page.isEmpty {
            // No symbol: the header already draws this exact mark 610 pt above,
            // and `HelmEmptyState`'s own rule is that a statement is a sentence
            // and nothing else.
            HelmEmptyState(message: entries.isEmpty ? AppStr.logEmpty : AppStr.logNothingMatches,
                           note: entries.isEmpty && !loggingOn && !AppBuild.isDev
                               ? AppStr.logNoteStable : nil) {
                if !entries.isEmpty {
                    Button(AppStr.logAllModules) {
                        chosen = []
                        minimumLevel = .info
                        query = ""
                    }
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: HelmSpace.s5) {
                        ForEach(page.cards) { card in
                            cardView(card)
                        }
                        Color.clear.frame(height: 0).id(Self.endMarker)
                    }
                    .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .coordinateSpace(.named(Self.contentSpace))
                }
                .onScrollGeometryChange(for: LogReaderPlace.Metrics.self) { geometry in
                    LogReaderPlace.Metrics(top: geometry.visibleRect.minY,
                                           visibleHeight: geometry.visibleRect.height,
                                           contentHeight: geometry.contentSize.height)
                } action: { _, now in
                    place.scrolled(now)
                }
                // **The end is held by the scroll view, not scrolled to once.** A
                // lazy card's rows make the page's height an estimate until
                // they have been drawn, and a `scrollTo` lands where the
                // estimate put the end — then the rows are measured, the page
                // changes height under a view that stays where it was, and the
                // newest line is somewhere below. Measured on a real tail in a
                // window on screen: the page opened at y = 7 677 of 15 901 pt
                // (`TheLogOpensOnItsNewestLineInARealWindowTests`), and with
                // the bottom anchor for the first offset alone it opened
                // 1 227 pt short at 760 pt wide and 1 262 pt short at 848 and
                // 1 000. Anchoring the bottom for size changes too keeps the
                // end under a view that was at it. It is set only while Follow
                // is lit, and it holds nothing for a view that was *not* at the
                // end: a reader scrolled up, with Follow on or off, is held by
                // the line they read (`LogReaderPlace`). `.alignment` is left
                // alone, so a short log still sits at the top of its pane.
                .defaultScrollAnchor(following ? .bottom : nil, for: .initialOffset)
                .defaultScrollAnchor(following ? .bottom : nil, for: .sizeChanges)
                // One rule for every road: while Follow is lit and what is
                // shown changes — a filter, a new line — or Follow turns on,
                // the view goes to the end of the newest card. Keyed on the
                // newest line's identity, never the count alone: `LogTail` caps
                // at 1000, so once full the count is constant and a
                // count-keyed handler stops firing while the control still says
                // Follow. The oldest identity and the count are in the key
                // because a filter can change what is shown and leave the
                // newest line the same one, and Follow turning on changes none
                // of them.
                .onChange(of: FilterKey(level: minimumLevel, chosen: chosen, query: query)) { _, _ in
                    place.forget()
                }
                .onChange(of: FollowKey(following: following, first: page.cards.first?.id,
                                        last: page.newestID, count: page.lines.count)) { _, _ in
                    guard following, !page.isEmpty else { return }
                    place.seekTheEnd()
                    proxy.scrollTo(Self.endMarker, anchor: .bottom)
                    // A second time on the next turn, and `place` asks for the end
                    // again after each quiet period until the view is at it (or
                    // gives up after `LogReaderPlace.attempts`): the anchor above
                    // holds the end for a view that was at it, and a view that was
                    // not — a person had scrolled up, then pressed Follow or
                    // widened a filter — is brought to it here, on an estimate
                    // where rows are lazy. The hop carries nothing but a
                    // constant; whether Follow is still lit is read inside it,
                    // because a person may have turned it off in between.
                    DispatchQueue.main.async {
                        guard following else { return }
                        proxy.scrollTo(Self.endMarker, anchor: .bottom)
                    }
                }
                // The other half: this reader is mounted by the first read
                // that brings a line, so the lines were already here when it
                // appeared and `onChange` has nothing to report for them. The
                // anchor above is what makes the open exact; this is the first
                // landing, which the anchor then corrects as rows are measured.
                .onAppear {
                    place.following = { following }
                    place.scrollToLine = { proxy.scrollTo($0, anchor: UnitPoint(x: 0, y: $1)) }
                    place.scrollToEnd = { proxy.scrollTo(Self.endMarker, anchor: .bottom) }
                    guard following, !page.isEmpty else { return }
                    place.seekTheEnd()
                    proxy.scrollTo(Self.endMarker, anchor: .bottom)
                }
            }
        }
    }

    /// One launch: what it was and how it went, then its lines.
    ///
    /// The card is the house's card (`helmCard`) with no padding of its own and
    /// clipped to its corners, so a row's wash reaches the card's edge instead
    /// of a rounded corner's.
    ///
    /// **The rows are lazy above `lazyAbove` of them** — a card's rows are the
    /// part that grows to a thousand, and what plain and lazy each cost is
    /// measured at that constant.
    ///
    /// **Follow's landing is held by the scroll view** — see the anchor in
    /// `lines`. Lazy rows are what make the page's height an estimate until they
    /// are drawn, and an estimate is what a one-off `scrollTo` lands on; the
    /// arrangement here (the end mark after the last card, the rows of a large
    /// card lazy) is measured to end at the page's own bottom padding with the
    /// anchor in place, on a real tail in a window on screen
    /// (`TheLogOpensOnItsNewestLineInARealWindowTests`).
    private func cardView(_ card: LogPresentation.Card) -> some View {
        let burstLines = card.startup.reduce(0) { $0 + $1.repeats }
        let open = Self.startupIsOpen(card.id, opened: openStartups, query: query)
        return VStack(alignment: .leading, spacing: 0) {
            cardHeader(card)
            if burstLines > 0 { startupFold(card, lines: burstLines, open: open) }
            if !card.rows.isEmpty || (open && burstLines > 0) { Divider() }
            if open && burstLines > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(card.startup) { tracked($0, LogRowView(row: $0).equatable()) }
                }
                .padding(.vertical, HelmSpace.s3)
                if !card.rows.isEmpty { Divider() }
            }
            if !card.rows.isEmpty {
                let rows = ForEach(card.rows) { row in
                    if let heading = row.heading { dayHeader(heading) }
                    tracked(row, LogRowView(row: row).equatable())
                }
                Group {
                    if card.rows.count > Self.lazyAbove {
                        LazyVStack(alignment: .leading, spacing: 0) { rows }
                    } else {
                        VStack(alignment: .leading, spacing: 0) { rows }
                    }
                }
                .padding(.vertical, HelmSpace.s3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmCard(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous))
    }

    /// **How many rows a card draws plainly before it draws them lazily.**
    /// A plain stack's heights are all measured, so the place of a line is a
    /// reading and `LogReaderPlace` can hold the reader to it; a lazy stack
    /// estimates the height of everything the view has scrolled past, and the
    /// estimate is re-made on every arrival and fold. Lazy is what makes a
    /// thousand rows cheap, so it stays for the card too large to draw whole. The
    /// figure is a ceiling chosen, not measured here: what mounting that many plain
    /// rows costs is what `testTheMainThreadCostOfOneArrivingLineOnScreen`
    /// (`HELM_BENCH=1`, in `TheLogHoldsAReaderThroughWhatNobodyTriedTests`) reads.
    static let lazyAbove = 400

    /// The content's own coordinates, which the rows report their place in.
    private static let contentSpace = "helm.log.content"

    /// A row that tells `place` where it is in the content whenever that
    /// changes, and when it is no longer drawn. A row's place moves only when the
    /// layout does — a scroll does not move it — so this is not a per-frame cost.
    private func tracked(_ row: LogPresentation.Row, _ view: some View) -> some View {
        view
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.contentSpace)) } action: {
                place.rowMoved(row.id, frame: $0)
            }
            .onDisappear { place.rowGone(row.id) }
            .id(row.id)
    }

    /// Whether a launch's start-up fold is drawn open: pressed open, or held open
    /// by a search. A search names lines, and a line inside a shut fold is a hit
    /// nobody can see — so while a word is being searched every fold is open, and
    /// closes again with the word.
    static func startupIsOpen(_ id: LogEntry.ID, opened: Set<LogEntry.ID>, query: String) -> Bool {
        opened.contains(id) || LogSearch.isActive(query)
    }

    /// **What a card's header says**, in the words of the app's language: a
    /// heading, and a quieter detail beside it. A run that began with its own
    /// start line is named by its time, with the version beside it; the head of
    /// the tail, whose start scrolled out of it, is an *earlier* launch with the
    /// time of its first line; and a run with no start line that is not the
    /// head — after a «terminating», after a «logging enabled» nothing answered
    /// — is named by the time of its first line alone, because it began later
    /// than the card above it and the file records no more (`LogCardTitle`).
    static func headerWords(for session: LogSession) -> (heading: String, detail: String?) {
        let began = HelmDates.dayAndMinute(session.lines[0].date)
        switch session.title {
        case .launch(let version): return (began, version.map { "Helm \($0)" })
        case .earlierLaunch: return (AppStr.logEarlierLaunch, began)
        case .noStartLine: return (began, nil)
        }
    }

    /// The launch's time and version, and its errors and warnings as badges.
    /// Two arrangements, the way the toolbar's own rows fold: on one line where
    /// the pane has the room, and the badges on a line of their own where a
    /// longer language does not.
    private func cardHeader(_ card: LogPresentation.Card) -> some View {
        let session = card.session
        let title = HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s4) {
            Image(systemName: "power").foregroundStyle(HelmText.quiet).accessibilityHidden(true)
            let words = Self.headerWords(for: session)
            // The launch's name is what the rotor jumps to; the card combines
            // its header into one element, and the trait is set on the text
            // that is the heading as well as on the element.
            Text(words.heading).font(HelmText.sectionHeading)
                .accessibilityAddTraits(.isHeader)
            if let detail = words.detail {
                Text(detail).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            }
        }
        let badges = HStack(spacing: HelmSpace.s3) {
            if card.errors > 0 {
                HelmBadge(AppStr.logErrorCount(card.errors), tint: HelmSignal.danger)
            }
            if card.warnings > 0 {
                HelmBadge(AppStr.logWarningCount(card.warnings), tint: HelmSignal.warning)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s4) {
                title
                Spacer(minLength: HelmSpace.s4)
                badges
            }
            VStack(alignment: .leading, spacing: HelmSpace.s3) {
                title
                badges
            }
        }
        .padding(.horizontal, HelmSpace.s5).padding(.top, HelmSpace.s5).padding(.bottom, HelmSpace.s4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The start-up burst as one line, opened by a press.
    ///
    /// **A swap and not a reveal, on purpose.** `helmAccordion` keeps its
    /// content mounted at a measured height, and here that would be a couple of
    /// dozen hidden rows for every launch in the tail, drawn for nobody. No
    /// curve is written, so there is nothing for a conditional insertion to
    /// collapse ahead of — the failure the accordion exists for is an animated
    /// removal, and this is not animated.
    private func startupFold(_ card: LogPresentation.Card, lines: Int, open: Bool) -> some View {
        Button {
            if openStartups.contains(card.id) { openStartups.remove(card.id) }
            else { openStartups.insert(card.id) }
        } label: {
            HStack(spacing: HelmSpace.s4) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(HelmText.rowDetail.weight(.semibold))
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Text(AppStr.logStartup(lines))
                    .font(HelmText.rowDetail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(HelmText.quiet)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, HelmSpace.s5).padding(.bottom, HelmSpace.s4)
        .accessibilityValue(HelmA11y.expanded(open))
    }

    /// The day a run of lines belongs to, written when it changes.
    ///
    /// **A heading and not a column.** The row carries a time to the
    /// millisecond, and a date beside it would cost every row about a third of
    /// its message width in the languages that spell a short date longest; the
    /// day changes a few times in a log and the row would repeat it a thousand.
    /// Inside a card it is written where a launch crosses midnight — the card's
    /// own header names the day it began.
    ///
    /// The spelling is `HelmDates.day` — the app's language, a formatter cached
    /// per language — and the comparison is the reader's calendar day, the same
    /// clock the row's time is drawn in. Nil for a line on the same day as the
    /// one above it in what is *shown*, never in what exists.
    static func dayHeading(for entry: LogEntry, after previous: LogEntry?,
                           language: String = AppLanguage.current.rawValue,
                           calendar: Calendar = .current) -> String? {
        if let previous, calendar.isDate(entry.date, inSameDayAs: previous.date) { return nil }
        return HelmDates.day(entry.date, language: language)
    }

    private func dayHeader(_ text: String) -> some View {
        Text(text)
            .font(HelmText.groupLabel).foregroundStyle(HelmText.quiet)
            .padding(.horizontal, HelmSpace.s5)
            .padding(.top, HelmSpace.s4).padding(.bottom, HelmSpace.s2)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Copy, Clear and the footer

    /// What the button puts on the pasteboard: the lines the file carries.
    ///
    /// It used to be `"\(time) [\(category)] \(message)"` — a second format,
    /// written here, which dropped the level, the date and the source site. On
    /// the machine this was measured on, 469 of 500 warnings in the file were one
    /// wording from one place, and pasted out of Helm they arrived with neither.
    static func pasteboardText(_ entries: [LogEntry]) -> String {
        LogLine.lines(entries)
    }

    /// Whether «Clear» has anything to clear.
    ///
    /// **The file, not the page.** It was gated on the tail, so a build with
    /// logging switched off said «Nothing logged yet», greyed both buttons, and
    /// left the log on disk — which is exactly the person who most wants it gone.
    /// Clear means the log: both files and the window onto them, which is what
    /// the button has always done once it could be pressed.
    static func canClear(entries: [LogEntry], storedLog: Bool) -> Bool {
        !entries.isEmpty || storedLog
    }

    /// Whether the file can hold lines the page does not: the tail is full, so
    /// the oldest went to make room, and there is a file. A short log shows
    /// everything it has, and saying «older lines are in the file» over it
    /// would be a sentence about lines that do not exist.
    static func olderLinesExist(entryCount: Int, storedLog: Bool) -> Bool {
        storedLog && entryCount >= HelmLog.tailLimit
    }

    /// **Counts, and where the tail begins** — «3 of 12 launches · 17 of 46
    /// lines · since 29.09.2026, 23:41 · older lines are in the file». Empty
    /// for an empty tail: there is nothing to count and nothing to date.
    static func footerCounts(_ page: LogPresentation, entries: [LogEntry],
                             storedLog: Bool) -> String {
        guard let oldest = entries.first else { return "" }
        var parts = [AppStr.logLaunches(page.cards.count, page.launchCount),
                     AppStr.logCount(page.shown, entries.count),
                     AppStr.logSince(HelmDates.dayAndMinute(oldest.date))]
        if olderLinesExist(entryCount: entries.count, storedLog: storedLog) {
            parts.append(AppStr.logOlderInFile)
        }
        return parts.joined(separator: " · ")
    }

    private func footer(_ page: LogPresentation) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s1) {
            let counts = Self.footerCounts(page, entries: entries, storedLog: hasStoredLog)
            if !counts.isEmpty {
                Text(counts).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(AppStr.logRedactionNote)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s4)
    }

    /// **Assigns only what changed.** A `@State` write re-runs the page's body
    /// whether or not the value differs, and this runs once a second for as long
    /// as the page is on screen: with nothing written in between, re-reading the
    /// tail was a full re-diff of up to a thousand rows for a page that had not
    /// moved (`LogPageTickChurnBenchmark` is the reading of what that cost).
    /// `LogEntry`'s `==` is its five parts — the id is not one of them — so a
    /// tail that says the same thing is the same tail.
    private func refresh() {
        let read = source()
        if read != entries { entries = read }
        let stored = storedLog()
        if stored != hasStoredLog { hasStoredLog = stored }
    }
}

/// One line, or a run of identical ones — see the row's own doc below.
///
/// **Equatable, so a tick that changed one line re-draws one row.** A card's
/// rows are lazy (see `LogView.cardView`), but every row that is drawn would
/// still re-run its body whenever the tail moves, and that is the cost this
/// buys back: a row is its lines, and the same lines are the same row. The day heading rides on the
/// comparison because it depends on the row above, which a filter can change
/// without touching this row's lines.
struct LogRowView: View, Equatable {
    let row: LogPresentation.Row

    nonisolated static func == (a: LogRowView, b: LogRowView) -> Bool {
        a.row.heading == b.row.heading && a.row.repeats == b.row.repeats
            && a.row.first.id == b.row.first.id && a.row.last.id == b.row.last.id
    }

    /// One line, or a run of identical ones. The level is a wash behind the
    /// whole row and a glyph, and its word is the row's accessibility value —
    /// so it is readable without the colour alone: the glyph is the shape that
    /// says it without the colour, and the value says it aloud. The category
    /// word is not tinted: the tint says "bad", and the word says "who".
    ///
    /// **No line is cut short.** A message runs as long as it is — the longest
    /// message in the owner's log copy is 902 characters (the file's
    /// line, with its stamp, level and category, is 949) — because a page whose
    /// point is showing exactly what the file holds does not get to decide
    /// which characters matter.
    var body: some View {
        let entry = row.first
        let signal = tint(for: entry.level)
        HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s4) {
            // One literal with two interpolations. Built as `"\(a)" + "\(b)"`
            // first, which is String concatenation — so each `Text` was rendered
            // through its own `description` and the row printed
            // `Text(storage: SwiftUI.Text.Storage.verbatim("16:29:07")…)`.
            Text("\(Text(HelmDates.logTime(entry.date)).foregroundStyle(HelmText.quiet))\(Text(HelmDates.logMillis(entry.date)).foregroundStyle(HelmText.faint))")
                .helmFigure()
            Image(systemName: glyph(for: entry.level) ?? "circle")
                .foregroundStyle(signal ?? .clear)
                .font(HelmText.rowDetail)
                .frame(width: 14)
                .opacity(signal == nil ? 0 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                if entry.category.isEmpty {
                    // A line this app did not write, or not all of one: whole,
                    // in the face that says it is not ours.
                    Text(entry.message)
                        .font(HelmText.rowDetail.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(Text(entry.category).fontWeight(.semibold).foregroundStyle(HelmText.faint))  \(Text(entry.message).foregroundStyle(entry.level == .info ? HelmText.quiet : Color.primary))")
                        .font(HelmText.rowDetail)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let site = entry.site {
                    Text("\(site.file):\(site.line)  \(site.function)")
                        .font(HelmText.rowDetail.monospaced()).foregroundStyle(HelmText.faint)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if row.repeats > 1 {
                HelmBadge("×\(Count(row.repeats))", tint: signal ?? .secondary)
                    .help(Self.repeatedUntilNote(row))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, HelmSpace.s5)
        // The wash fills the row and reaches its edges; nothing stands at the
        // left edge in a colour of its own (the owner took the direction without
        // the bar: the fill says it, the glyph says it, and the bar was a third,
        // louder voice down every warning card).
        .background {
            if let signal { signal.opacity(0.06) }
        }
        .accessibilityElement(children: .combine)
        // The row's marks of severity are a wash and a glyph, and a combined
        // element has neither. Empty for an ordinary line: see
        // `logLevelWord`.
        .accessibilityValue(AppStr.logLevelWord(entry.level) ?? "")
    }

    /// When the last repeat was written: the time, and the day too when the run
    /// crossed midnight — a time alone would put the last repeat on the first
    /// one's day.
    static func repeatedUntil(_ row: LogPresentation.Row, calendar: Calendar = .current) -> String {
        calendar.isDate(row.first.date, inSameDayAs: row.last.date)
            ? HelmDates.logTime(row.last.date) : HelmDates.dayAndMinute(row.last.date)
    }

    /// The tooltip of the ×N badge: «Repeated until 03:01:40», or — when the run
    /// crossed midnight — «Repeated until 22.09.2026, 03:01», each its own
    /// sentence because the languages that put an article before a date do not
    /// put one before a time.
    static func repeatedUntilNote(_ row: LogPresentation.Row, calendar: Calendar = .current) -> String {
        let until = repeatedUntil(row, calendar: calendar)
        return calendar.isDate(row.first.date, inSameDayAs: row.last.date)
            ? AppStr.logRepeatedUntil(until) : AppStr.logRepeatedUntilDay(until)
    }

    /// Nil for an ordinary line, so an info row gains no layers at all.
    private func tint(for level: LogLevel) -> Color? {
        switch level {
        case .info: return nil
        case .warn: return HelmSignal.warning
        case .error: return HelmSignal.danger
        }
    }

    private func glyph(for level: LogLevel) -> String? {
        switch level {
        case .info: return nil
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
