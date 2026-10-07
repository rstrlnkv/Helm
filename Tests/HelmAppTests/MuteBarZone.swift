import AppKit
@testable import HelmApp

/// A zone that holds no view, shows nothing, measures nothing and applies nothing:
/// the `ShellBarZone` port with every state it can be in answered by silence.
///
/// It stands for one side of the port, the zone, so a bar can be built around the
/// zone under test without a second real zone drawing or taking room.
@MainActor
final class MuteBarZone: ShellBarZone {
    var view: NSView? { nil }
    var measuresMoved: (() -> Void)?
    func show(_ state: ShellBarZoneState) {}
    func measure(into measures: inout ShellPageBarView.Measures) {}
    func apply(_ verdicts: ShellPageBarView.Verdicts) {}
}
