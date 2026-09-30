import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
import HelmRuntime
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// While Homebrew's installer waits on Apple's window, the page says what for —
/// the window may be behind Settings, and a bare spinner over an empty screen
/// reads as a hang. The engine names the state (`OpState.waiting`) and the words
/// are the page's, in each of the eight languages.
@MainActor
final class TheWaitSaysWhatItWaitsForTests: XCTestCase {

    private let running = OpState(phase: .running, label: "install Homebrew")
    private let waiting = OpState(phase: .running, label: "install Homebrew", waiting: .commandLineTools)

    /// «Stop waiting» ends the waiting and leaves Apple's window to finish; a
    /// bare «Stop» would promise to end something Helm cannot. Both directions,
    /// so the title cannot be one constant.
    func testStopSaysWhatItStops() {
        AppLanguage.each { language in
            XCTAssertEqual(HomebrewSettingsPage.stopTitle(for: waiting), HbStr.stopWaiting, language.rawValue)
            XCTAssertEqual(HomebrewSettingsPage.stopTitle(for: running), HbStr.stop, language.rawValue)
            XCTAssertNotEqual(HbStr.stopWaiting, HbStr.stop,
                              "\(language.rawValue): the two buttons read as one word")
        }
    }

    /// The pill names what is waited for in Apple's own words for it, and never
    /// falls back to the operation's raw label.
    func testThePillNamesTheTools() {
        AppLanguage.each { language in
            let pill = HbStr.waitingForTools(language: language)
            XCTAssertTrue(pill.contains(HbStr.appleTools(language: language)),
                          "\(language.rawValue): the pill does not name what it waits for: \(pill)")
            XCTAssertNotEqual(pill, waiting.label)
        }
    }

    /// The engine names the install operation in English — it is a log line and
    /// a state's name — so the pill has to word it, or it changes from a
    /// translated sentence to a lowercase English one the moment Apple's tools
    /// arrive. Every other label is the arguments of a brew run as the engine
    /// writes them (`upgrade wget`), not a sentence, and is shown as it is. The first
    /// assertion pins this file's literal to the engine's constant: were the
    /// engine's label to change, the pill would fall through to the raw label and
    /// this case would read a state that no longer is the install.
    func testTheRunningPillWordsTheInstallAndLeavesBrewCommandsWhole() {
        XCTAssertEqual(running.label, HomebrewEngine.installBrewLabel)
        let upgrade = OpState(phase: .running, label: "upgrade wget")
        AppLanguage.each { language in
            let pill = HomebrewSettingsPage.pillTitle(for: running, language: language)
            XCTAssertEqual(pill, L("Installing Homebrew", language: language), language.rawValue)
            XCTAssertNotEqual(pill, running.label, "\(language.rawValue): the pill shows the engine's own label")
            if language != .en {
                XCTAssertNotEqual(pill, HomebrewSettingsPage.pillTitle(for: running, language: .en),
                                  "\(language.rawValue): the pill is English")
            }
            XCTAssertEqual(HomebrewSettingsPage.pillTitle(for: upgrade, language: language),
                           "upgrade wget", language.rawValue)
            XCTAssertEqual(HomebrewSettingsPage.pillTitle(for: waiting, language: language),
                           HbStr.waitingForTools(language: language), language.rawValue)
        }
    }

    /// Entering the wait says where the person's part is — Apple's window, its
    /// Install button, possibly behind this one — and leaving it says the tools
    /// are there, or that the person stopped waiting (`testStoppingTheWaitSaysHelmWillNotCarryOn`).
    /// Nothing else says anything: not a failure, not the same state twice, not
    /// a stop of an operation that was not waiting.
    func testTheConsoleSaysTheTwoStepsAndNothingElse() {
        AppLanguage.each { language in
            let entering = HomebrewViewModel.consoleLine(from: .idle, to: waiting, language: language)
            XCTAssertEqual(entering, HbStr.toolsWaitingConsole(language: language), language.rawValue)
            let button = Quoted(L("Install", language: language), language: language)
            XCTAssertTrue(entering?.contains(button) ?? false,
                          "\(language.rawValue): the line does not name Apple's button as «\(button)»: \(entering ?? "nil")")

            let running = OpState(phase: .running, label: "install Homebrew")
            XCTAssertEqual(HomebrewViewModel.consoleLine(from: waiting, to: running, language: language),
                           HbStr.toolsArrivedConsole(language: language), language.rawValue)

            let failed = OpState(phase: .failed, label: "install Homebrew", reason: .toolsNotInstalled)
            let stopped = OpState(phase: .failed, label: "install Homebrew", reason: .stopped)
            XCTAssertNil(HomebrewViewModel.consoleLine(from: waiting, to: failed, language: language), language.rawValue)
            XCTAssertNil(HomebrewViewModel.consoleLine(from: running, to: stopped, language: language), language.rawValue)
            XCTAssertNil(HomebrewViewModel.consoleLine(from: waiting, to: waiting, language: language), language.rawValue)
            XCTAssertNil(HomebrewViewModel.consoleLine(from: .idle, to: running, language: language), language.rawValue)
        }
    }

    /// The wait's first line ends on «Helm carries on by itself once they are
    /// installed», and a press on «Stop waiting» makes that untrue: the engine
    /// takes the wait away and nothing ticks again. The console is not cleared
    /// by the stop, so without a line of its own that promise stays on the
    /// screen under «Stopped». The line says Helm stopped, that Apple's window
    /// goes on, and which button to press when it is done — the button by the
    /// string the button is drawn with, so it cannot drift from it.
    func testStoppingTheWaitSaysHelmWillNotCarryOn() {
        AppLanguage.each { language in
            let stopped = OpState(phase: .failed, label: "install Homebrew", reason: .stopped)
            let line = HomebrewViewModel.consoleLine(from: waiting, to: stopped, language: language)
            XCTAssertEqual(line, HbStr.toolsWaitStoppedConsole(language: language), language.rawValue)
            let button = Quoted(L("Install Homebrew", language: language), language: language)
            XCTAssertTrue(line?.contains(button) ?? false,
                          "\(language.rawValue): the line does not name the button as «\(button)»: \(line ?? "nil")")
            XCTAssertNotEqual(line, HbStr.toolsWaitingConsole(language: language), language.rawValue)
            if language != .en {
                XCTAssertNotEqual(line, HbStr.toolsWaitStoppedConsole(language: .en),
                                  "\(language.rawValue): the line is English")
            }
        }
    }

    /// The installer's own code is what somebody searches for.
    func testTheInstallerNoteNamesItsCode() {
        AppLanguage.each { language in
            let op = OpState(phase: .failed, label: "install Homebrew", exitCode: 71, reason: .installerFailed)
            XCTAssertTrue(HomebrewSettingsPage.failureNote(op, language: language)?.contains("71") ?? false,
                          "\(language.rawValue): the note does not carry the exit code")
        }
    }

    /// The four words the notes are made of are distinct sentences in every
    /// language — checked in `ARefusedDoctorIsNotAHealthyMacTests` for the whole
    /// enum; here, that the neutral pill for a cancelled password is not Stop's.
    func testACancelledPasswordIsNotStopped() {
        AppLanguage.each { language in
            XCTAssertNotEqual(HbStr.cancelled, HbStr.stopped, language.rawValue)
            XCTAssertNotEqual(HbStr.cancelled, HbStr.failed, language.rawValue)
        }
    }
}
