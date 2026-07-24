import Foundation

/// Folds hover/drag/event inputs into the island's presentation state. Pure —
/// timers live outside (the UI arms a grace timer on hover/drag exit and feeds
/// `.graceElapsed` back in; sources feed `.event`/`.eventExpired`).
public struct IslandStateMachine: Equatable, Sendable {
    public enum State: Equatable, Sendable { case hidden, peek, expanded }

    public enum Input: Equatable, Sendable {
        case hoverEntered, hoverExited
        case dragEntered, dragExited
        case dropped
        case graceElapsed
        case event(id: String)
        case eventExpired(id: String)
        case dismiss
    }

    private var hovering = false
    private var dragging = false
    /// Set by a drop: keeps the island open for review until dismissed.
    private var pinned = false
    /// Exit happened; stay expanded until the grace timer fires (or re-entry).
    private var graceOpen = false
    private var liveEvents: Set<String> = []

    public init() {}

    public var state: State {
        if hovering || dragging || pinned || graceOpen { return .expanded }
        if !liveEvents.isEmpty { return .peek }
        return .hidden
    }

    public mutating func apply(_ input: Input) {
        switch input {
        case .hoverEntered:
            hovering = true
            graceOpen = false          // re-entry cancels a pending collapse
        case .hoverExited:
            hovering = false
            graceOpen = true
        case .dragEntered:
            dragging = true
            graceOpen = false
        case .dragExited:
            dragging = false
            graceOpen = true
        case .dropped:
            pinned = true
        case .graceElapsed:
            graceOpen = false
        case .event(let id):
            liveEvents.insert(id)
        case .eventExpired(let id):
            liveEvents.remove(id)
        case .dismiss:
            hovering = false; dragging = false; pinned = false; graceOpen = false
            liveEvents.removeAll()
        }
    }
}
