import CoreGraphics
import Foundation

/// The lift's first cut of numbers, in one place; tuned live.
enum LaunchpadLiftTiming {
    /// How far the pointer goes from where it went down before a press is a lift (pt).
    static let threshold: CGFloat = 5
    /// The pointer stays this long (s) in a tile's margin before the gap takes that tile's place.
    static let marginDebounce: TimeInterval = 0.12
    /// The pointer stays this long (s) in a tile's icon before it is the target of a drop onto it.
    static let ontoArm: TimeInterval = 0.30
    /// The strip along the window's side that turns the page (pt), after `edgeFirst` s, then every `edgeRepeat` s; on the
    /// last page it makes a new one. An open card with pages has its own strips, at its sides, which turn its pages and make none.
    static let edgeWidth: CGFloat = 40
    static let edgeFirst: TimeInterval = 0.6
    static let edgeRepeat: TimeInterval = 0.9
    /// The pointer stays this long (s) on a folder's tile, counted from its arrival like `ontoArm` is (not from the drop being armed), before the folder opens.
    static let folderOpen: TimeInterval = 0.70
    /// The pointer stays this long (s) outside the open card, its margin included, before the card closes.
    static let leaveCard: TimeInterval = 0.25
    static let cardMargin: CGFloat = 12
    /// A press with nothing to wait for is looked at this often (s), by the one tick that asks whether the button is still down:
    /// a mouse-up that never came must not leave the window pressed or lifted for good.
    static let stuckCheck: TimeInterval = 0.5
    /// A press that stays this long (s) without a lift begins the edit mode.
    static let editHold: TimeInterval = 0.5
}

/// A press on a tile, as the machine of what it becomes: a click, or a lift that is carried, turns pages, and ends in
/// exactly one of a release or a cancel. Pure: no timer, no view; time comes in with the event, and `wake` says when a
/// `tick` would change something, for the caller to arm one timer.
///
/// **One effect per feed**, and an effect names addresses (`LaunchpadSurface`), never entries: the state maps them. The gap
/// follows the pointer by *dwell* (`marginDebounce`), not at once, and a pointer over the gap itself changes nothing: the tile
/// that made way is under the pointer again only because the gap took its place.
struct LaunchpadLift {
    enum Input: Equatable { case down, moved, up, escape, tick, abort }
    enum Drop: Equatable { case gap, onto(address: Int) }
    enum Effect: Equatable {
        case none
        /// The press became a lift of the tile at this address.
        case lift(address: Int)
        /// The gap takes the place of the tile at this address (an empty cell: the end of its page).
        case moveGap(to: Int)
        /// The tile at this address is where a drop goes onto, or nobody.
        case arm(address: Int?)
        case turn(Int)
        case newPage
        /// The pointer stayed on the folder at this address: it opens, and the lift goes on inside its card.
        case openFolder(address: Int)
        /// The pointer stayed outside the open card: it closes, and the lift goes on over the grid.
        case closeFolder
        case release(Drop)
        case cancel
        /// Let go without having moved: the tile at this address was pressed.
        case click(address: Int)
        /// The press stayed `LaunchpadLiftTiming.editHold` on the tile at this address without a lift: the edit mode begins, and the press goes on (a move then lifts the tile, a release is no click).
        case beginEditing(address: Int)
    }

    /// `held`: the press has begun the edit mode and is still down.
    private enum Phase: Equatable { case idle, pressed(address: Int, at: CGPoint), held(address: Int, at: CGPoint), lifted }
    private enum Dwell: Equatable { case none, margin(Int), core(Int), edge(Int), away }

    private var phase = Phase.idle
    private var dwell = Dwell.none
    private var since: TimeInterval = 0
    private var nextEdge: TimeInterval = 0
    private var checkAt: TimeInterval = 0
    /// When the press went down, and whether it may become the edit mode's hold (`LaunchpadSurface.holdsToEdit` then).
    private var pressedAt: TimeInterval = 0
    private var holds = false
    private var armed: Int?
    /// The tile in the icon's middle holds a folder, which a longer dwell opens.
    private var opens = false
    /// The pointer has been inside the open card: only then is leaving it a reason to close it, since a folder that opens
    /// under the pointer opens somewhere the pointer is not.
    private var inCard = false

    /// A press is down, lifted or not.
    var isEngaged: Bool { phase != .idle }
    var isLifted: Bool { phase == .lifted }
    var pressedAddress: Int? { if case .pressed(let a, _) = phase { a } else { nil } }

    /// When a `tick` would do something, or nil.
    var wake: TimeInterval? {
        if case .pressed = phase, holds { return pressedAt + LaunchpadLiftTiming.editHold }
        guard phase == .lifted else { return nil }
        switch dwell {
        case .none: return nil
        case .margin: return since + LaunchpadLiftTiming.marginDebounce
        case .core: return armed == nil ? since + LaunchpadLiftTiming.ontoArm : opens ? since + LaunchpadLiftTiming.folderOpen : nil
        case .edge: return nextEdge
        case .away: return since + LaunchpadLiftTiming.leaveCard
        }
    }

    /// When the button is next looked at while a press is engaged, or nil: `stuckCheck` after the last input.
    var stuckWake: TimeInterval? { phase == .idle ? nil : checkAt }

    /// What was waited on is not what is there any more (the tiles moved under the pointer).
    mutating func resetDwell() { dwell = .none; armed = nil; inCard = false }

    mutating func feed(_ input: Input, at point: CGPoint = .zero, surface: LaunchpadSurface, time: TimeInterval = 0) -> Effect {
        defer { checkAt = time + LaunchpadLiftTiming.stuckCheck }
        switch (phase, input) {
        case (.idle, .down):
            if case .tile(let address, _) = LaunchpadHit.at(point, in: surface), address != surface.gap {
                phase = .pressed(address: address, at: point)
                pressedAt = time
                holds = surface.holdsToEdit
            }
            return .none
        case (.idle, _), (_, .down):
            return .none
        case (.pressed(let address, let from), .moved):
            let away = hypot(point.x - from.x, point.y - from.y)
            guard away.isFinite, away >= LaunchpadLiftTiming.threshold else { return .none }
            return beginLift(address, surface)
        case (.pressed(let address, _), .up):
            phase = .idle
            return .click(address: address)
        case (.pressed(let address, let from), .tick):
            guard holds, time >= pressedAt + LaunchpadLiftTiming.editHold else { return .none }
            phase = .held(address: address, at: from)
            return .beginEditing(address: address)
        case (.held(let address, let from), .moved):
            guard hypot(point.x - from.x, point.y - from.y) >= LaunchpadLiftTiming.threshold else { return .none }
            return beginLift(address, surface)
        case (.held, .up):
            phase = .idle
            return .none
        case (.held, .tick):
            return .none
        case (_, .escape), (_, .abort):
            phase = .idle
            resetDwell()
            return .cancel
        case (.lifted, .up):
            phase = .idle
            let drop = armed.map { Drop.onto(address: $0) } ?? .gap
            resetDwell()
            return .release(drop)
        case (.lifted, .moved), (.lifted, .tick):
            return follow(point, surface, time)
        }
    }

    private mutating func beginLift(_ address: Int, _ surface: LaunchpadSurface) -> Effect {
        phase = .lifted
        resetDwell()
        inCard = surface.card != nil
        return .lift(address: address)
    }

    private mutating func follow(_ point: CGPoint, _ surface: LaunchpadSurface, _ time: TimeInterval) -> Effect {
        let next: Dwell
        let hit = LaunchpadHit.at(point, in: surface)
        switch hit {
        case .tile(let address, let core): next = address == surface.gap ? .none : core ? .core(address) : .margin(address)
        case .gap(let address): next = .margin(address)
        case .edge(let side): next = .edge(side)
        case .away: next = inCard ? .away : .none
        case .none: next = .none
        }
        if surface.card != nil, hit != .away { inCard = true }
        if next != dwell {
            let wasArmed = armed != nil
            dwell = next
            since = time
            armed = nil
            if case .edge = next { nextEdge = time + LaunchpadLiftTiming.edgeFirst }
            if case .core(let address) = next { opens = surface.folders.contains(address) }
            if wasArmed { return .arm(address: nil) }
        }
        switch dwell {
        case .margin(let address) where time - since >= LaunchpadLiftTiming.marginDebounce:
            dwell = .none
            return .moveGap(to: address)
        case .core(let address) where armed == nil && time - since >= LaunchpadLiftTiming.ontoArm:
            armed = address
            return .arm(address: address)
        case .core(let address) where opens && time - since >= LaunchpadLiftTiming.folderOpen:
            dwell = .none
            armed = nil
            return .openFolder(address: address)
        case .away where time - since >= LaunchpadLiftTiming.leaveCard:
            dwell = .none
            inCard = false
            return .closeFolder
        case .edge(let side) where time >= nextEdge:
            nextEdge = time + LaunchpadLiftTiming.edgeRepeat
            let (page, count) = surface.card.map { ($0.page, $0.pageCount) } ?? (surface.page, surface.pageCount)
            if side > 0, page == count - 1 { return surface.card == nil ? .newPage : .none }
            if side < 0, page == 0 { return .none }
            return .turn(side)
        default:
            return .none
        }
    }
}
