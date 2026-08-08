import XCTest
@testable import HelmContract

final class StatusPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private func spinning(_ seconds: TimeInterval) -> StatusAppearance {
        StatusAppearance(tintToken: "green", spinUntil: now.addingTimeInterval(seconds))
    }

    func testAModuleThatIsSpinningTakesTheIcon() {
        let quiet = StatusAppearance(tintToken: "orange")
        let chosen = StatusPlan.choose([quiet, spinning(0.5)], now: now)
        XCTAssertEqual(chosen.spinUntil, spinning(0.5).spinUntil,
                       "a spin was invisible because another module sorted first")
    }

    func testWithoutASpinTheFirstTintedModuleStillWins() {
        let first = StatusAppearance(tintToken: "orange")
        let second = StatusAppearance(tintToken: "green")
        XCTAssertEqual(StatusPlan.choose([first, second], now: now).tintToken, "orange")
    }

    /// Two modules spinning at once: the newer spin wins, not whichever module
    /// the user happened to order first. Tying this to ModuleOrder would hide a
    /// module's own feedback behind an unrelated one for up to a second.
    func testTheNewestSpinWins() {
        let earlier = StatusAppearance(tintToken: "orange", spinUntil: now.addingTimeInterval(0.2))
        let later = StatusAppearance(tintToken: "green", spinUntil: now.addingTimeInterval(1.0))
        XCTAssertEqual(StatusPlan.choose([earlier, later], now: now).tintToken, "green")
        XCTAssertEqual(StatusPlan.choose([later, earlier], now: now).tintToken, "green",
                       "the answer must not depend on the order the modules arrive in")
    }

    func testAnExpiredSpinIsNotASpin() {
        let stale = StatusAppearance(tintToken: "green", spinUntil: now.addingTimeInterval(-1))
        let active = StatusAppearance(tintToken: "orange")
        XCTAssertEqual(StatusPlan.choose([active, stale], now: now).tintToken, "orange")
    }

    /// Tier three. A module can have nothing but something to say — VPN names
    /// the connection a rule raised for three seconds, while its spin lasts
    /// only 1.2 s, and it deliberately tints nothing. Without this the name
    /// died with the ring: measured in the menu bar, gone by 1.8 s.
    func testATitleAloneIsChosenWhenNothingTints() {
        let naming = StatusAppearance(title: "Office VPN")
        XCTAssertEqual(StatusPlan.choose([StatusAppearance(), naming], now: now).title,
                       "Office VPN")
    }

    /// And never above a module that tints. A name is a moment; a countdown is
    /// continuous state, and Keep Awake tints while one runs — the same rule
    /// the countdown's suppression of the spin already encodes. `naming` is
    /// first here on purpose: "the first that tints or titles" would pick it.
    func testATitleAloneDoesNotDisplaceATintedModule() {
        let naming = StatusAppearance(title: "Office VPN")
        let counting = StatusAppearance(tintToken: "orange", timerProgress: 0.5)
        XCTAssertEqual(StatusPlan.choose([naming, counting], now: now).tintToken, "orange")
        XCTAssertEqual(StatusPlan.choose([counting, naming], now: now).tintToken, "orange",
                       "the answer must not depend on the order the modules arrive in")
    }

    func testNothingActiveIsInactive() {
        XCTAssertEqual(StatusPlan.choose([StatusAppearance()], now: now), .inactive)
    }

    // MARK: - A countdown against a spin

    /// The composition the app actually produces: Keep Awake counts down on one
    /// appearance, VPN asks for a spin on another. No descriptor ever puts both
    /// fields on one appearance, so this — not the hand-built single appearance
    /// below — is the shape the rule has to hold on.
    private var countdown: StatusAppearance {
        StatusAppearance(tintToken: "red", timerProgress: 0.4, title: "14:22")
    }
    private var firing: StatusAppearance {
        StatusAppearance(title: "Office VPN", spinUntil: now.addingTimeInterval(1))
    }

    /// A countdown is continuous state; a spin is a moment. The moment must not
    /// interrupt the state — a countdown arc that jumped backwards for a second
    /// reads as a bug, and on screen the arc and its remaining time were
    /// *replaced* by a grey spinning ring for 1.2 s.
    func testACountdownOutranksASpinForTheIcon() {
        XCTAssertEqual(StatusPlan.choose([countdown, firing], now: now), countdown)
        XCTAssertEqual(StatusPlan.choose([firing, countdown], now: now), countdown,
                       "the answer must not depend on the order the modules arrive in")
    }

    /// And the guard that reads the chosen appearance then answers for the
    /// right reason: the appearance it is handed is the counting one.
    func testTheChosenAppearanceOfACountdownDoesNotSpin() {
        let chosen = StatusPlan.choose([countdown, firing], now: now)
        XCTAssertFalse(StatusPlan.spins(chosen, now: now, reduceMotion: false))
        XCTAssertNil(StatusPlan.frame(spinUntil: chosen.spinUntil, now: now, frameCount: 36),
                     "the host would still have had a frame to draw")
    }

    /// The honest consequence, asserted rather than described. There is one
    /// title slot, and while a countdown owns the icon it holds the countdown's
    /// own remaining time — so a firing arriving then is not announced in the
    /// menu bar at all, neither by the ring nor by the name. Someone who wants
    /// to be told regardless picks the banner.
    func testWhileACountdownOwnsTheIconAFiringIsNotNamed() {
        XCTAssertEqual(StatusPlan.choose([countdown, firing], now: now).title, "14:22",
                       "the connection's name displaced the countdown's remaining time")
    }

    /// The shape no descriptor produces, kept because `spins` is public and the
    /// two fields are independent: one appearance carrying both must still
    /// refuse to move. On its own this proved nothing about the app — it was
    /// the only coverage the rule had, and it passed while the menu bar spun.
    func testACountdownSuppressesTheSpinWithinOneAppearance() {
        let counting = StatusAppearance(tintToken: "green", timerProgress: 0.5,
                                        spinUntil: now.addingTimeInterval(1))
        XCTAssertFalse(StatusPlan.spins(counting, now: now, reduceMotion: false))
    }

    /// A countdown outranks a spin, not every tint: an ordinary tinted module
    /// still loses the icon to a live spin, which is the borrow the feature is
    /// built on.
    func testOnlyACountdownOutranksASpinAndNotAnyTint() {
        let tinted = StatusAppearance(tintToken: "orange")
        XCTAssertEqual(StatusPlan.choose([tinted, firing], now: now), firing)
    }

    /// Reduce Motion removes the movement and keeps the information.
    func testReduceMotionSuppressesTheSpin() {
        XCTAssertFalse(StatusPlan.spins(spinning(1), now: now, reduceMotion: true))
        XCTAssertTrue(StatusPlan.spins(spinning(1), now: now, reduceMotion: false))
    }

    /// The spin is over the moment its window closes — nothing keeps asking.
    func testASpinThatHasEndedIsNotSpinning() {
        let ended = StatusAppearance(tintToken: "green", spinUntil: now.addingTimeInterval(-0.01))
        XCTAssertFalse(StatusPlan.spins(ended, now: now, reduceMotion: false))
        XCTAssertEqual(StatusPlan.choose([ended], now: now).tintToken, "green",
                       "an ended spin should still be an ordinary tinted module")
    }

    // MARK: - Which frame belongs to now

    private let frames = 36

    /// A spin that has just been asked for starts at its first frame: the host
    /// derives the phase from what is left of `spinUntil`, and getting the
    /// direction wrong would run the whole animation backwards.
    func testASpinOpensOnItsFirstFrame() {
        let spinUntil = now.addingTimeInterval(StatusPlan.spinDuration)
        XCTAssertEqual(StatusPlan.frame(spinUntil: spinUntil, now: now, frameCount: frames), 0)
    }

    /// The instant before the window closes is the last frame, not one past it:
    /// the host subscripts an array with this.
    func testTheLastInstantOfASpinIsTheLastFrame() {
        let spinUntil = now.addingTimeInterval(0.0001)
        XCTAssertEqual(StatusPlan.frame(spinUntil: spinUntil, now: now, frameCount: frames), 35)
    }

    func testNoFrameWhenNothingIsSpinning() {
        XCTAssertNil(StatusPlan.frame(spinUntil: nil, now: now, frameCount: frames))
        XCTAssertNil(StatusPlan.frame(spinUntil: now, now: now, frameCount: frames),
                     "a spin ending exactly now is over")
        XCTAssertNil(StatusPlan.frame(spinUntil: now.addingTimeInterval(-1), now: now,
                                      frameCount: frames))
    }

    /// Nothing promises `spinUntil` is inside one spin's length — a module could
    /// ask for longer, or a clock could jump. Every answer still has to be a
    /// subscript that exists.
    func testEveryFrameIsInsideTheArray() {
        for offset in stride(from: -0.5, through: 5.0, by: 0.05) {
            guard let frame = StatusPlan.frame(spinUntil: now.addingTimeInterval(offset),
                                               now: now, frameCount: frames) else { continue }
            XCTAssertTrue((0..<frames).contains(frame),
                          "frame \(frame) at offset \(offset) is not an index of the array")
        }
    }

    /// The clamp did not protect the conversion, because the conversion was
    /// inside it: `min(max(Int(phase * Double(frameCount)), 0), frameCount - 1)`
    /// evaluates `Int(_:)` first, and `Int(_:)` traps on anything outside `Int`'s
    /// range. So the bounds that exist to keep the index sane never saw the
    /// number — the process was already gone.
    ///
    /// This is the KeepAwake family one target over. `spinUntil` reaches the host
    /// from a module, over JSON, as a `Date`, and a `Date` is a `Double` of
    /// seconds: nothing between the payload and this line says how large. The
    /// module writing it is not the check.
    ///
    /// Asserted as the property the host needs — a subscript that exists — rather
    /// than as a particular index, so a fix may choose either end.
    func testASpinFartherOffThanIntCanHoldStillDrawsAFrame() {
        for wild in [1e300, .greatestFiniteMagnitude, Double.infinity] {
            let spinUntil = Date(timeIntervalSinceReferenceDate: wild)
            guard let frame = StatusPlan.frame(spinUntil: spinUntil, now: now,
                                               frameCount: frames) else { continue }
            XCTAssertTrue((0..<frames).contains(frame),
                          "a spinUntil of \(wild) gave \(frame), which is not an index "
                          + "of the array the host is about to subscript")
        }
    }

    /// The other half of the same arithmetic, and the reason the fix cannot stop
    /// at moving the conversion outwards. Bounding a `Double` cannot remove a NaN
    /// — `max(.nan, 0)` is NaN and `min(.nan, high)` is NaN — and `phase` is
    /// infinite for a wild `spinUntil`, so `phase * 0` is NaN and the conversion
    /// traps again on the far side of a clamp that looks right.
    ///
    /// An empty array has no index either way, which is the answer.
    func testAnEmptyFrameArrayHasNoFrameToDraw() {
        XCTAssertNil(StatusPlan.frame(spinUntil: now.addingTimeInterval(0.5), now: now,
                                      frameCount: 0),
                     "there is no still to draw, and -1 is not one")
        XCTAssertNil(StatusPlan.frame(spinUntil: Date(timeIntervalSinceReferenceDate: .infinity),
                                      now: now, frameCount: 0))
    }

    // MARK: - What counts as a redraw

    /// The key exists to skip redundant redraws, so a key that ignores the
    /// frame skips the animation itself — every frame of a spin would answer
    /// "nothing changed" and the ring would sit still. This is the assertion
    /// that catches that; nothing else can see it without a menu bar.
    func testEveryFrameOfASpinIsItsOwnRedraw() {
        let keys = (0..<frames).map {
            StatusPlan.redrawKey(style: "ring", size: "medium", tint: "green",
                                 progress: nil, title: nil, frame: $0)
        }
        XCTAssertEqual(Set(keys).count, frames, "frames share a key, so the spin would not move")
    }

    func testTheSameIconIsNotRedrawn() {
        let key = { StatusPlan.redrawKey(style: "ring", size: "medium", tint: "green",
                                         progress: nil, title: "12:00", frame: nil) }
        XCTAssertEqual(key(), key())
    }

    /// A countdown moves by a hair per tick; redrawing per pixel is why this is
    /// bucketed. Two progresses inside one percent are the same icon.
    func testACountdownRedrawsAboutOncePerPercent() {
        let key = { (progress: Double) in
            StatusPlan.redrawKey(style: "ring", size: "medium", tint: "green",
                                 progress: progress, title: nil, frame: nil)
        }
        XCTAssertEqual(key(0.500), key(0.5001))
        XCTAssertNotEqual(key(0.50), key(0.51))
    }

    func testEachPartOfTheAppearanceCanChangeTheIcon() {
        let base = StatusPlan.redrawKey(style: "ring", size: "medium", tint: "green",
                                        progress: 0.5, title: "12:00", frame: nil)
        XCTAssertNotEqual(base, StatusPlan.redrawKey(style: "dot", size: "medium", tint: "green",
                                                     progress: 0.5, title: "12:00", frame: nil))
        XCTAssertNotEqual(base, StatusPlan.redrawKey(style: "ring", size: "large", tint: "green",
                                                     progress: 0.5, title: "12:00", frame: nil))
        XCTAssertNotEqual(base, StatusPlan.redrawKey(style: "ring", size: "medium", tint: "orange",
                                                     progress: 0.5, title: "12:00", frame: nil))
        XCTAssertNotEqual(base, StatusPlan.redrawKey(style: "ring", size: "medium", tint: "green",
                                                     progress: 0.5, title: "11:59", frame: nil))
    }

    /// The defect the `frame` fix closed, fifteen lines below it. The bucket is
    /// `Int((progress * 100).rounded())` and `Int(_:)` of a `Double` **traps**
    /// outside `Int`'s range and on a value that is not a number — before
    /// `MenuBarIcon.make` is reached, so the key traps first, on a status tick
    /// that runs once a second.
    ///
    /// `timerProgress` is a field of a public struct that any module's
    /// descriptor fills in; nothing between that and this line says how large
    /// it may be, which is the argument `frame` already makes about
    /// `spinUntil`.
    ///
    /// The bounds are the ones the icon draws with, so the key says what the
    /// icon shows: `MenuBarIcon.make` clamps to 0…1 and refuses to stroke an
    /// arc for a value that is not a number, which is the same nothing it draws
    /// at 0.
    func testAProgressNoModuleCouldMeanIsStillOneKey() {
        let key = { (progress: Double) in
            StatusPlan.redrawKey(style: "ring", size: "medium", tint: "green",
                                 progress: progress, title: nil, frame: nil)
        }
        XCTAssertEqual(key(.nan), key(0), "a NaN draws no arc, which is what 0 draws")
        XCTAssertEqual(key(1e300), key(1), "past the bound is the bound, as the ring draws it")
        XCTAssertEqual(key(.infinity), key(1))
        XCTAssertEqual(key(-.infinity), key(0))
    }

    /// And the control, so the bounding above cannot be satisfied by a key that
    /// has stopped reading the countdown at all.
    func testTheBucketStillFollowsAnOrdinaryCountdown() {
        let key = { (progress: Double) in
            StatusPlan.redrawKey(style: "ring", size: "medium", tint: "green",
                                 progress: progress, title: nil, frame: nil)
        }
        XCTAssertNotEqual(key(0), key(1))
        XCTAssertNotEqual(key(0.25), key(0.75))
    }

    /// A title that ends and a title that reads "-" are different icons; so are
    /// a missing tint and a tint literally spelled the way the key spells nil.
    func testAnAbsentPartIsNotTheSameAsAPartSpelledLikeIt() {
        XCTAssertNotEqual(StatusPlan.redrawKey(style: "ring", size: "medium", tint: nil,
                                               progress: nil, title: nil, frame: nil),
                          StatusPlan.redrawKey(style: "ring", size: "medium", tint: "",
                                               progress: nil, title: "", frame: nil))
    }

    /// The animation has to advance: sampling across one spin must produce
    /// frames that never go backwards and do not all sit on the same image.
    func testFramesAdvanceAcrossTheSpin() {
        let spinUntil = now.addingTimeInterval(StatusPlan.spinDuration)
        let samples = stride(from: 0.0, to: StatusPlan.spinDuration, by: 1.0 / 30).map {
            StatusPlan.frame(spinUntil: spinUntil, now: now.addingTimeInterval($0),
                             frameCount: frames)
        }
        XCTAssertNil(samples.first(where: { $0 == nil }), "the spin ended before its window did")
        let indices = samples.compactMap { $0 }
        XCTAssertEqual(indices, indices.sorted(), "the spin ran backwards")
        XCTAssertGreaterThan(Set(indices).count, 1, "every sample drew the same frame")
    }

    /// The whole point of the separate field. `tintToken` is a claim on the
    /// menu bar between moments; a module that only wants its own second of
    /// animation coloured must not become the module that owns the icon.
    func testASpinTintIsNotAClaimOnTheIcon() {
        let now = Date()
        let spinner = StatusAppearance(spinUntil: now.addingTimeInterval(1),
                                       spinTintToken: "green")
        let tinter = StatusAppearance(tintToken: "orange")

        // While the spin runs it wins on its own tier, as before.
        XCTAssertEqual(StatusPlan.choose([spinner, tinter], now: now), spinner)

        // Once it is over, the module that actually tints takes the icon back —
        // the spinner's colour must not have registered as a tint.
        let after = now.addingTimeInterval(5)
        XCTAssertEqual(StatusPlan.choose([spinner, tinter], now: after), tinter)
    }

    func testASpinTintAloneNeverWinsTheTintTier() {
        let now = Date()
        // Spin already finished, so only the fallback tiers can answer.
        let spent = StatusAppearance(spinUntil: now.addingTimeInterval(-1),
                                     spinTintToken: "green")
        XCTAssertEqual(StatusPlan.choose([spent], now: now), .inactive,
                       "a spent spin with a colour is not a module with a tint")
    }

    func testTheRedrawKeyNoticesTheSpinTint() {
        let green = StatusPlan.redrawKey(style: "ring", size: "medium", tint: nil,
                                         progress: nil, title: nil, frame: 3,
                                         spinTint: "green")
        let orange = StatusPlan.redrawKey(style: "ring", size: "medium", tint: nil,
                                          progress: nil, title: nil, frame: 3,
                                          spinTint: "orange")
        XCTAssertNotEqual(green, orange,
                          "the same frame in two colours must not report 'nothing changed'")
    }
}
