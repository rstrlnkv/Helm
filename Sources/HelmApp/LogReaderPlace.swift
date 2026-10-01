// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmRuntime
import HelmUI

/// **Where the reader is on the Log page, held by the line and not by the
/// offset.**
///
/// A scroll view keeps its offset while the content under it changes, and the
/// line the person was reading is somewhere else: the oldest line leaves the top
/// of a full tail as a new one arrives, a fold opens, a narrower window wraps
/// every row above. `TheLogKeepsAReaderWhereTheyWereTests` puts each of those
/// under a reader in a window on screen.
///
/// So the page remembers the line at the top of the view and how far from the
/// top it was (`anchor`), is told every time a drawn row's place in the content
/// changes (`rowMoved`), and when it is that line that moved while the view did
/// not, moves the view by the difference (`holdLine`). Where the rows above are
/// measured the line stays where it was on screen, with one exception: a line
/// taller than the room below it is moved by the hold itself (300 pt to 200 pt in
/// `TheReadersLineLandsWhereItWasTests`, the known gap `log-tall-line`).
///
/// **What it can hold, and what it cannot.** A row's place is a reading only
/// where the rows above it are measured. A card's rows are plain up to
/// `LogView.lazyAbove` of them, and every height in the page is then a
/// measurement; above that they are lazy, and the height of what the view has
/// scrolled past is an estimate, re-made whenever rows are drawn or dropped — a
/// reader inside such a card is held no better than the estimate allows. The
/// choice is `LogView`'s, and its doc says what each side costs.
///
/// **Only a layout at rest is believed for remembering.** While a change is laid
/// out the rows report places one after another, so the line is remembered when
/// every report has been quiet for `quiet` — and a person's scroll is what the
/// remembering is for, so the line being held is the one remembered after the
/// last of them.
///
/// **Who holds what.** Follow lit and the view at the end: the scroll view's own
/// bottom anchor is asked to keep the end, and when the page comes to rest short
/// of it with nobody having scrolled, the end is asked for again; this holds no
/// line, because it would keep the top line and leave the end. A change of what is
/// shown — a level, a module, a search — holds no line either (`forget`): it is a
/// different page, not the same one moved. Follow lit
/// and the view not at the end (the person scrolled up; Follow does not go out
/// when they do), or Follow off: this holds the line. And while Follow *wants* the
/// end and has not got it (`seeking`: a filter changed, Follow was pressed, the
/// page has just opened) this holds nothing and asks for the end again after each
/// quiet period, up to `attempts` times — the first landing is on an estimate when
/// rows are lazy, and the rows it realised are measured after.
///
/// A plain reference type, held in `@State` and never read by a body: what it
/// remembers changes on every scroll, and a body that read it would be redrawn by
/// the thing it is trying to keep still.
@MainActor
final class LogReaderPlace {
    /// What the scroll view reports, in the content's own coordinates.
    struct Metrics: Equatable {
        /// The content's top edge the view shows, in content coordinates.
        var top: CGFloat = 0
        var visibleHeight: CGFloat = 0
        var contentHeight: CGFloat = 0

        /// How far the content runs on below the view.
        var gap: CGFloat { contentHeight - (top + visibleHeight) }
    }

    /// How far the end may be and still count as reached: the page's bottom
    /// padding, which is where the end marker leaves the view, and a point or two.
    static let endTolerance: CGFloat = HelmSpace.s5 + 2

    /// How many times the end is asked for again after one request. The page's
    /// height settles in a few turns; a bound is what keeps a page that never
    /// settles from holding a person away from where they scrolled to.
    static let attempts = 8

    /// How long nothing may have been reported before the layout is taken to be
    /// at rest. The passes of one change arrive within a few milliseconds of one
    /// another; a person cannot see this long.
    static let quiet: TimeInterval = 0.08

    /// A drawn row's place in the content, by the line it starts at.
    private var frames: [LogEntry.ID: CGRect] = [:]
    private var metrics = Metrics()
    /// The line at the top of the view when it was remembered: from the view's
    /// top to the line's top edge, where the view's top was, and where in the
    /// view a scroll to the line by identity must put it for that distance to come
    /// out — a point of the line and the same fraction of the view are brought
    /// together, so a line `h` tall in a view `V` tall at distance `d` is the
    /// point `d / (V − h)`.
    private var anchor: (id: LogEntry.ID, distance: CGFloat, top: CGFloat, fraction: CGFloat)?
    /// Follow wants the end and has not reached it. True until the end is first
    /// seen at rest, so a page that opens is not held anywhere.
    private var seeking = true
    /// Where the view's top was the last time the page came to rest at the end
    /// with Follow lit; nil when it was not at the end then.
    private var endTop: CGFloat?
    private var asked = 0
    private var lastReport = Date.distantPast
    private var timerPending = false

    /// What the page does for the place, set by the page.
    var following: () -> Bool = { true }
    var scrollToLine: (LogEntry.ID, CGFloat) -> Void = { _, _ in }
    var scrollToEnd: () -> Void = {}

    private var isAtEnd: Bool { metrics.gap <= Self.endTolerance }

    /// Follow asked for the end (a filter changed, Follow was pressed, a new
    /// line came, the page opened): hold nothing until it has been reached.
    func seekTheEnd() {
        seeking = true
        asked = 0
        anchor = nil
        restart()
    }

    /// The person asked for a different page — a level, a module, a search: the
    /// lines under the reader are not the lines they were reading, and the page
    /// does not second-guess where they were. Nothing is held across it.
    func forget() {
        anchor = nil
        restart()
    }

    func rowMoved(_ id: LogEntry.ID, frame: CGRect) {
        frames[id] = frame
        if id == anchor?.id { holdLine(frame) }
        restart()
    }

    func rowGone(_ id: LogEntry.ID) {
        frames[id] = nil
        restart()
    }

    func scrolled(_ now: Metrics) {
        metrics = now
        restart()
    }

    /// Whether a line is held at all: not while Follow wants the end, and not
    /// when Follow is lit and the view is at it.
    private var holding: Bool {
        guard !seeking else { return false }
        return !following() || !isAtEnd
    }

    /// The line being held moved in the content while the view did not: put the
    /// view where the line is, the distance from its top it was.
    private func holdLine(_ frame: CGRect) {
        guard holding, var held = anchor, abs(metrics.top - held.top) < 1 else { return }
        let delta = (frame.minY - metrics.top) - held.distance
        guard abs(delta) > 0.5 else { return }
        // The view's own reading catches up after this; until it does, the
        // line's place must not be taken for a person's scroll.
        held.top = metrics.top + delta
        anchor = held
        scrollToLine(held.id, held.fraction)
    }

    // MARK: - At rest

    private func restart() {
        lastReport = Date()
        guard !timerPending else { return }
        timerPending = true
        schedule(after: Self.quiet)
    }

    private func schedule(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let waited = Date().timeIntervalSince(self.lastReport)
            if waited < Self.quiet {
                self.schedule(after: Self.quiet - waited)
            } else {
                self.timerPending = false
                self.atRest()
            }
        }
    }

    private func atRest() {
        if following() {
            if seeking {
                if isAtEnd {
                    seeking = false
                    endTop = metrics.top
                    asked = 0
                    capture()
                } else if asked < Self.attempts {
                    asked += 1
                    scrollToEnd()
                } else {
                    seeking = false
                    asked = 0
                    capture()
                }
                return
            }
            let was = endTop
            endTop = isAtEnd ? metrics.top : nil
            asked = 0
            if isAtEnd { anchor = nil; return }
            // The view was at the end when the page last came to rest and the
            // content has grown under it, with nobody having scrolled: the end
            // is asked for again, as a landing is.
            if let was, abs(metrics.top - was) < 1 {
                seeking = true
                asked = 1
                scrollToEnd()
                return
            }
        } else {
            seeking = false
            endTop = nil
        }
        capture()
    }

    /// The first drawn row whose top is in the view, and how far that top is from
    /// the view's top. Only the top is tested: a row taller than the view's remaining
    /// room is chosen too, which is the known gap `log-tall-line`.
    private func capture() {
        let top = metrics.top
        var best: (id: LogEntry.ID, frame: CGRect)?
        for (id, frame) in frames where frame.minY >= top - 0.5 {
            if best == nil || frame.minY < best!.frame.minY { best = (id, frame) }
        }
        anchor = best.map { found in
            let distance = found.frame.minY - top
            let room = metrics.visibleHeight - found.frame.height
            // With `room` of 1 or less there is no room to be a fraction of, so the
            // fraction is 0 and no division happens. Past that check a not-a-number
            // cannot arise (finite frames); if one did, it reads as the bottom of
            // the room.
            let fraction = room > 1
                ? (distance / room).clamped(to: 0...1, whenNotANumber: 1)
                : 0
            return (found.id, distance, top, fraction)
        }
    }
}
