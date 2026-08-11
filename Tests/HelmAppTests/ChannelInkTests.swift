import XCTest
import AppKit
import HelmTestSupport
import SwiftUI
@testable import HelmApp
@testable import HelmUI
import HelmRuntime

/// The two update channels are told apart by colour, and one place decides it.
///
/// The About page names each channel twice — the badge on the wordmark says
/// which build this is, the picker below says which one to follow — and before
/// this the two disagreed: the badge drew a *dev* build blue and a beta build
/// orange, while the picker was about to draw the Dev pill orange. One page,
/// one word, two colours.
///
/// The contrast test is here rather than in `SignalColourContrastTests` because
/// what it measures is different: that one asks whether a token is readable on
/// the *window*, and a filled pill is its own background.
@MainActor
final class ChannelInkTests: XCTestCase {

    /// `Contrast`'s, in `HelmTestSupport`: the same four functions were spelled
    /// out here and in three other test files.
    private func resolved(_ color: Color, _ appearance: NSAppearance.Name) -> NSColor {
        Contrast.resolved(color, appearance)
    }

    private func ratio(_ a: NSColor, _ b: NSColor) -> Double { Contrast.ratio(a, b) }

    /// The whole point of the change: two channels a colour-blind-to-nothing
    /// reader can tell apart at a glance, in both appearances.
    func testTheTwoChannelsAreNotTheSameColour() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let beta = resolved(ChannelInk.fill(.beta), appearance)
            let dev = resolved(ChannelInk.fill(.dev), appearance)
            let red = abs(beta.redComponent - dev.redComponent)
            let green = abs(beta.greenComponent - dev.greenComponent)
            let blue = abs(beta.blueComponent - dev.blueComponent)
            let distance: CGFloat = red + green + blue
            XCTAssertGreaterThan(distance, 0.30,
                                 "beta and dev are the same fill in \(appearance.rawValue): "
                                 + "\(beta) vs \(dev)")
        }
    }

    /// Dev's orange is the app's orange, not a literal somebody typed: the
    /// signal tokens exist so that a meaning has one colour across the app.
    func testDevReadsTheSignalTokenAndBetaTheAccent() {
        XCTAssertEqual(ChannelInk.fill(.dev), HelmSignal.warning)
        XCTAssertEqual(ChannelInk.fill(.beta), Color.accentColor)
    }

    /// A chosen pill is its own background, so its label answers to it. 4.5:1
    /// is the body-text floor `HelmSignal` was solved against, and this label
    /// is smaller than body text.
    func testTheChosenPillsLabelIsReadableOnItsOwnFill() {
        for channel in UpdateCheck.Channel.allCases {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let measured = ratio(resolved(ChannelInk.chosenLabel, appearance),
                                     resolved(ChannelInk.chosenFill(channel), appearance))
                XCTAssertGreaterThanOrEqual(
                    measured, Contrast.bodyFloor,
                    "\(channel.rawValue) in \(appearance.rawValue): "
                    + String(format: "%.2f", measured) + ":1")
            }
        }
    }
}
