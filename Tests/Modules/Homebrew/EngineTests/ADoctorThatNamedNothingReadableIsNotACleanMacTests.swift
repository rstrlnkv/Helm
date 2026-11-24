import XCTest
@testable import Module_Homebrew_Engine

/// **`brew doctor` exiting 1 is brew saying the Mac is not clean**, and an
/// answer this module could not read a finding out of is then not «Nothing to
/// fix».
///
/// `cmd/doctor.rb` sets `Homebrew.failed` for every check that returns a
/// finding, and a Mac with nothing to report exits 0 with «Your system is ready
/// to brew.». So exit 1 with no finding parsed is never a clean Mac, and must not
/// become `.examined([])`, which the Health tab draws as «Nothing to fix.».
///
/// **Colour.** brew colours output on a non-TTY stream when `HOMEBREW_COLOR` is
/// set, read also from `brew.env` files it loads itself (`/etc/homebrew/brew.env`,
/// `$HOMEBREW_PREFIX/etc/homebrew/brew.env`, `~/.homebrew/brew.env`), which
/// override the environment. Every `Warning:` then arrives as
/// `ESC[33mWarning:ESC[0m`, which `DoctorParser` does not see as a block start.
/// `HOMEBREW_NO_COLOR` wins over it (`Tty.color?` asks `no_color?` first).
///
/// Both fixtures were captured with a `PATH` that puts `/usr/bin` first so
/// doctor has something to say:
///
///     $ env PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin HOMEBREW_NO_AUTO_UPDATE=1 \
///           [HOMEBREW_COLOR=1] /opt/homebrew/bin/brew doctor > out 2>&1; echo "EXIT=$?"
///     EXIT=1        (808 bytes plain, 834 coloured)
///
/// The fake answers as brew does: coloured unless the environment it is handed
/// says `HOMEBREW_NO_COLOR`.
private func colouringDoctor(status: Int32, plain: String, coloured: String) -> ScriptedRunner {
    ScriptedRunner(diagnostics: { env in
        // `brew.env` says HOMEBREW_COLOR=1; only HOMEBREW_NO_COLOR (or NO_COLOR,
        // its documented default) in what Helm hands over switches it off.
        let noColour = !(env["HOMEBREW_NO_COLOR"] ?? "").isEmpty || !(env["NO_COLOR"] ?? "").isEmpty
        return (status, noColour ? plain : coloured)
    })
}

final class ADoctorThatNamedNothingReadableIsNotACleanMacTests: XCTestCase {

    private static let esc = "\u{1B}"

    /// The body both captures share after their first line.
    private static func capture(warning: String, bold: String, reset: String) -> String {
        """
        \(bold)Please note that these warnings are just used to help the Homebrew maintainers
        with debugging if you file an issue. If everything you use Homebrew for is
        working fine: please don't worry or file an issue; just ignore this. Thanks!\(reset)

        \(warning) /usr/bin occurs before /opt/homebrew/bin in your PATH.
        This means that system-provided programs will be used instead of those
        provided by Homebrew.

        The following tools exist at both paths:
          openssl
          pip3
          pp
          python3

        Consider setting your PATH for example like so:
          echo 'export PATH=/opt/homebrew/bin:$PATH' >> ~/.zshrc

        \(warning) Homebrew's "sbin" was not found in your PATH but you have installed
        formulae that put executables in /opt/homebrew/sbin.

        Consider setting your PATH for example like so:
          echo 'export PATH=/opt/homebrew/sbin:$PATH' >> ~/.zshrc


        """
    }

    private static let plain = capture(warning: "Warning:", bold: "", reset: "")
    private static let coloured = capture(warning: "\(esc)[33mWarning:\(esc)[0m",
                                          bold: "\(esc)[1m", reset: "\(esc)[0m")

    /// The fixtures parse into the plain capture's two findings and match the
    /// byte counts above, so a red below is about colour.
    func testTheFixturesAreTheCapturedBytes() {
        XCTAssertEqual(Self.plain.utf8.count, 808)
        XCTAssertEqual(Self.coloured.utf8.count, 834)
        XCTAssertEqual(DoctorParser.parse(Self.plain)?.count, 2)
    }

    /// `brew.env` carries HOMEBREW_COLOR=1: doctor exits 1 with two findings
    /// in colour. The reading must be the two findings, or no reading — never
    /// an examined, empty one, which the page draws as «Nothing to fix.».
    func testAColouredDoctorIsNotReadAsNothingToFix() {
        let runner = colouringDoctor(status: 1, plain: Self.plain, coloured: Self.coloured)
        let answer = brewEngine(runner).doctor()
        XCTAssertNotEqual(answer, [],
                          "brew doctor exited 1 with two warnings in colour and Helm read it as a clean Mac")
        if let answer { XCTAssertEqual(answer.count, 2, "a reading, when there is one, holds both findings") }
    }

    /// The same contradiction with no colour: exit 1 and nothing that starts a
    /// block, which is the one byte of stdout `puts nil` leaves when stderr is
    /// lost. Exit 1 is brew saying it found something.
    func testExitOneWithNoFindingLineIsNotReadAsNothingToFix() {
        let runner = colouringDoctor(status: 1, plain: "\n", coloured: "\n")
        XCTAssertNotEqual(brewEngine(runner).doctor(), [],
                          "brew doctor exited 1 and printed no finding; Helm read it as a clean Mac")
    }

    /// The control: exit 0 and brew's clean sentence is an examined, empty Mac,
    /// so the two above cannot pass by refusing every empty answer.
    func testExitZeroWithTheReadySentenceIsAClean() {
        let runner = colouringDoctor(status: 0, plain: "Your system is ready to brew.\n", coloured: "Your system is ready to brew.\n")
        XCTAssertEqual(brewEngine(runner).doctor(), [])
    }
}
