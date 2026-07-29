import XCTest
import SwiftUI
@testable import HelmUI

/// "We are working" is one event and it had four shapes: a bare spinner, a
/// spinner with a caption, a spinner with a caption at another size, and a
/// spinner with a caption and a Stop button — which is why the fourth one was
/// hand-rolled out of a `VStack` and two `Spacer()`s instead of using
/// `HelmBusyState` at all. Work that can be stopped is the normal case in this
/// app, not the exception.
///
/// The slot mirrors `HelmEmptyState`'s, including the `Actions == EmptyView`
/// overload — a busy state with nothing to do about it stays one argument long,
/// and no existing call site has to change to keep compiling.
final class BusyStateActionsTests: XCTestCase {

    /// The overload that keeps every current call site compiling. Written as a
    /// type assertion rather than a construction, because "it compiled" is what
    /// this is actually claiming.
    func testAMessageOnlyBusyStateHasNoActions() {
        let plain = HelmBusyState("Scanning")
        XCTAssertTrue(type(of: plain) == HelmBusyState<EmptyView>.self,
                      "the message-only overload stopped resolving to EmptyView, "
                      + "so every existing call site is now ambiguous")
    }

    /// A spinner with nothing to say is still legal: it was one of the four.
    func testABareBusyStateStillHasNoActions() {
        XCTAssertTrue(type(of: HelmBusyState()) == HelmBusyState<EmptyView>.self)
    }

    func testABusyStateCarriesTheActionsItIsGiven() {
        let stoppable = HelmBusyState("Scanning") {
            Button("Stop") {}
        }
        XCTAssertTrue(type(of: stoppable) == HelmBusyState<Button<Text>>.self,
                      "the actions slot did not carry its content through")
    }

    /// The slot is the same slot `HelmEmptyState` has, so a caller moving
    /// between them is not learning a second convention.
    func testTheSlotMirrorsTheEmptyState() {
        let empty = HelmEmptyState(message: "Nothing") { Button("Again") {} }
        let busy = HelmBusyState("Working") { Button("Stop") {} }
        XCTAssertTrue(type(of: empty) == HelmEmptyState<Button<Text>>.self)
        XCTAssertTrue(type(of: busy) == HelmBusyState<Button<Text>>.self)
    }
}
