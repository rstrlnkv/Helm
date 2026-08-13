import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **A row offers «Turn off» for a label the switch behind it will not carry.**
///
/// The label is not Helm's: it is whatever string a `.plist` in a LaunchAgents
/// folder put in its `Label` key, and `LaunchAgentReader` passes it through
/// untouched (its only rule is that an empty one falls back to the file name). Two
/// characters in it are not ordinary text by the time the switch runs:
///
///   • **`/`** — `ActiveExtensions.setDisabled` refuses it outright, and its own
///     comment says why: «A `/` in it re-points the service target at the domain
///     itself, and `launchctl bootout gui/<uid>` ends the user's login session».
///     So the guard is right, and the row above it does not know about it:
///     `LeftoverActions.available` inserts `.turnOff` for any launch agent with a
///     non-empty label, the page draws a live button, and the press does nothing
///     at all. «The model refuses this while a removal runs; the page has to say
///     so, or the press is a control that does nothing» is that page's own comment
///     about the *other* reason it can refuse.
///
///   • **`"` and a newline** — carried through to `launchctl`, and read back by
///     `LaunchctlDisabled.parse`, which is line-oriented over
///     `launchctl print-disabled`'s own format (verified on this Mac,
///     2026-08-13):
///
///         	disabled services = {
///         		"com.apple.Siri.agent" => enabled
///         		"com.vendor.updater" => disabled
///
///     A label of `x" => disabled` + newline + `\t\t"com.vendor.updater` therefore
///     prints as two lines that parse as two labels, and the second one is a job
///     nobody switched off. The badge that says «Disabled» is the whole of what
///     this module offers as reassurance that a login item will not run, and it
///     would be drawn on a row that runs at every login. This is the VPN pass's
///     forged row — a name that stands in for an identity — in launchd's list
///     instead of `scutil`'s.
///
/// **What is asserted is the implication, not the fix.** A row may offer the switch
/// only if the label it would send is one the switch will act on. That leaves both
/// repairs open: withhold `.turnOff` (one predicate, read by `available` and by
/// `setDisabled`, so the page and the port cannot come to disagree — the shape
/// `StaleItem.removable` already uses), or refuse the label at the reader and fall
/// back to the file name the way a blank one does. Either satisfies this file; a
/// row that offers a switch nothing can throw does not.
///
/// Expected to fail until one of those lands.
final class ASwitchTheSystemWillRefuseTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    /// Characters that stop a label being a label by the time it reaches launchd.
    /// Read by the assertion below rather than spelled per case, so the rule and
    /// the reason it exists stay together.
    private static func unusableAsALabel(_ label: String) -> Bool {
        label.isEmpty || label.contains("/") || label.contains("\"")
            || label.contains(where: \.isNewline)
    }

    private func agent(labelled label: String) throws -> StaleItem {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.vendor.updater.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.vendor.updater.plist"] =
            PlistData(["Label": label, "Program": "/Applications/Gone.app/Contents/MacOS/updater"])
        let items = LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                                     extensions: LeftoversFakeLoaded()).scan()
        return try XCTUnwrap(items.first { $0.kind == .launchAgent },
                            "precondition: the agent is listed at all")
    }

    /// A label with a path separator in it: the switch refuses it, the row offers
    /// it, and the press is a control that does nothing.
    ///
    /// **Three dot-separated components, because two are covered by accident.**
    /// `com.vendor/updater` is turned away by `StaleItemRules.isRemovable`'s
    /// reverse-DNS rule — «at least vendor + name» — which makes it
    /// `.protectedItem`, and a protected row offers nothing but Reveal. That is not
    /// this rule doing its job, it is a different rule catching one spelling of the
    /// problem; move the separator one component along and the row is an ordinary
    /// leftover with a live switch. A fixture that had used the shorter form would
    /// have passed and proved nothing.
    func testAnAgentWhoseLabelCarriesASeparatorIsNotOfferedTheSwitch() throws {
        let item = try agent(labelled: "com.vendor.updater/x")
        XCTAssertEqual(item.status, .orphaned,
                       "precondition: an ordinary leftover row, not one protected by another rule")

        XCTAssertFalse(item.canToggle && Self.unusableAsALabel(item.identifier), """
            the row offers «Turn off» for the label «\(item.identifier)», which \
            `ActiveExtensions.setDisabled` refuses before it runs anything — so the button is live, \
            the press asks launchd nothing, and the page then rescans and draws the same row \
            unchanged. The port's guard is right; the offer above it has never heard of it.
            """)
    }

    /// And a label that can forge a line in the list Helm reads back.
    func testAnAgentWhoseLabelCanForgeALineInTheDisabledListIsNotOfferedTheSwitch() throws {
        let forged = "com.vendor.updater\" => disabled\n\t\t\"com.apple.Siri.agent"
        let item = try agent(labelled: forged)

        XCTAssertFalse(item.canToggle && Self.unusableAsALabel(item.identifier), """
            the row offers «Turn off» for a label carrying a quote and a newline, so what \
            `launchctl print-disabled` prints for it is two lines and \
            `LaunchctlDisabled.parse` reads two labels — the second of them a job nobody switched \
            off, wearing this module's «Disabled» badge at every scan from then on.
            """)
    }

    /// The rule itself recognises the shapes it is written for, and lets an ordinary
    /// label through — otherwise the two assertions above would hold for a rule that
    /// refuses everything.
    func testTheRuleIsAboutTheseLabelsAndNotAboutEveryLabel() {
        XCTAssertFalse(Self.unusableAsALabel("com.vendor.updater"))
        XCTAssertFalse(Self.unusableAsALabel("com.vendor.updater.helper-2"))
        XCTAssertTrue(Self.unusableAsALabel(""))
        XCTAssertTrue(Self.unusableAsALabel("com.vendor/updater"))
        XCTAssertTrue(Self.unusableAsALabel("com.vendor\"updater"))
        XCTAssertTrue(Self.unusableAsALabel("com.vendor\nupdater"))
    }
}
