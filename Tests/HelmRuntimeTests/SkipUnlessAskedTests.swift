import HelmTestSupport
import XCTest

/// The call at the top of a test that is left red on purpose, which lets the suite read green while the
/// reproduction beneath it waits, and lets a person who asks for it run that reproduction.
///
/// `SkipUnlessAsked` either returns, and the reproduction runs, or throws `XCTSkip`, and the test is counted
/// as skipped. What this holds is the rule of *asked*: which switch, which value, and what the reason reads.
///
/// Every case hands the call its environment as an argument and none sets a variable in this process. A case
/// that set `HELM_KNOWN_GAPS` itself would switch on every known gap of the run it is part of; one that read
/// the run's own environment would pass in one run and fail in the other. Only the last case leaves the
/// argument out, because the default argument is the one thing it is there to hold, and it is written to
/// agree with the run it is in.
///
/// Total failure of the subject prints three different things, and none of them is a pass. A call that is not
/// there stops the build with `cannot find 'SkipUnlessAsked' in scope`, so no case of this target runs. A
/// call that never skips fails the cases that feed it a switch that is absent or misread, each saying which
/// environment it ran in, but for an assertion that compares the reason itself, which prints the reason it
/// read and no environment. A call that always skips fails the cases that feed it `1`, each saying it was
/// skipped, and, in a run with a switch at `1`, the case that reads the process's own environment, which
/// says the call and the process disagree about the switch. A skip is caught inside the case, never thrown
/// out of it, so no case here can end as skipped and be mistaken for a pass.
final class SkipUnlessAskedTests: XCTestCase {

    // MARK: - A known gap

    func testAKnownGapSkipsWhenTheSwitchIsAbsent() throws {
        let skipped = try skipMessage {
            try SkipUnlessAsked.knownGap("some-id", "what is wrong", environment: [:])
        }

        XCTAssertNotNil(skipped, "a known gap ran with no switch set, which puts a row that is red on "
                        + "purpose into every default run")
    }

    func testTheReasonIsKnownGapTheIdAndWhatIsWrong() throws {
        let skipped = try skipMessage {
            try SkipUnlessAsked.knownGap("some-id", "what is wrong", environment: [:])
        }

        XCTAssertEqual(skipped, "Known gap some-id: what is wrong")
    }

    func testAKnownGapRunsWhenTheSwitchReadsOne() throws {
        let skipped = try skipMessage {
            try SkipUnlessAsked.knownGap("some-id", "what is wrong",
                                         environment: ["HELM_KNOWN_GAPS": "1"])
        }

        XCTAssertNil(skipped, "a known gap was skipped with its switch at 1, so the reproduction "
                     + "beneath it can never be run")
    }

    func testOnlyOneCountsAsAsked() throws {
        for value in ["", "0", "true", " 1", "2"] {
            let skipped = try skipMessage {
                try SkipUnlessAsked.knownGap("some-id", "what is wrong",
                                             environment: ["HELM_KNOWN_GAPS": value])
            }
            XCTAssertNotNil(skipped, "a known gap ran with its switch reading \(String(reflecting: value))")
        }

        let other = try skipMessage {
            try SkipUnlessAsked.knownGap("some-id", "what is wrong", environment: ["HELM_BENCH": "1"])
        }
        XCTAssertNotNil(other, "a known gap ran because the benchmark switch was at 1")
    }

    /// Inputs the other cases do not feed: values that a reader which parses, trims or folds would take for
    /// one — a leading zero, a sign, a trailing space or newline, a full-width digit from somebody else's
    /// keyboard. The cases above pass for a reader that compares to `1` and for one that converts to a
    /// number and compares that; these tell the two apart.
    func testWhatOnlyReadsLikeOneIsNotOne() throws {
        for value in ["01", "+1", "1 ", "1\n", "\u{FF11}"] {
            let gap = try skipMessage {
                try SkipUnlessAsked.knownGap("some-id", "what is wrong",
                                             environment: ["HELM_KNOWN_GAPS": value])
            }
            XCTAssertNotNil(gap, "a known gap ran with its switch reading \(String(reflecting: value))")

            let benchmark = try skipMessage {
                try SkipUnlessAsked.benchmark(environment: ["HELM_BENCH": value])
            }
            XCTAssertNotNil(benchmark, "a benchmark ran with its switch reading \(String(reflecting: value))")
        }
    }

    /// The other half of the same question: a variable whose name only resembles the switch asks for
    /// nothing. An environment is case-sensitive, and a reader that matched the name by case or by prefix
    /// would take any of these for the switch.
    func testOnlyTheSwitchesWholeNameAsksForIt() throws {
        for name in ["helm_known_gaps", "HELM_KNOWN_GAP", "HELM_KNOWN_GAPS_", "HELM_KNOWN_GAPS "] {
            let skipped = try skipMessage {
                try SkipUnlessAsked.knownGap("some-id", "what is wrong", environment: [name: "1"])
            }
            XCTAssertNotNil(skipped, "a known gap ran with \(String(reflecting: name)) at 1")
        }
        for name in ["helm_bench", "HELM_BENC", "HELM_BENCH_", "HELM_BENCH "] {
            let skipped = try skipMessage {
                try SkipUnlessAsked.benchmark(environment: [name: "1"])
            }
            XCTAssertNotNil(skipped, "a benchmark ran with \(String(reflecting: name)) at 1")
        }
    }

    // MARK: - A measurement of this Mac

    func testABenchmarkSkipsUnlessItsOwnSwitchReadsOne() throws {
        let absent = try skipMessage { try SkipUnlessAsked.benchmark(environment: [:]) }
        XCTAssertEqual(absent, "a measurement of this Mac — HELM_BENCH=1 to run")

        let named = try skipMessage {
            try SkipUnlessAsked.benchmark("a walk of this volume", environment: [:])
        }
        XCTAssertEqual(named?.hasPrefix("a walk of this volume"), true,
                       "a benchmark's reason does not begin with what it measures: "
                       + String(reflecting: named))

        let asked = try skipMessage {
            try SkipUnlessAsked.benchmark(environment: ["HELM_BENCH": "1"])
        }
        XCTAssertNil(asked, "a benchmark was skipped with its switch at 1")

        let other = try skipMessage {
            try SkipUnlessAsked.benchmark(environment: ["HELM_KNOWN_GAPS": "1"])
        }
        XCTAssertNotNil(other, "a benchmark ran because the known-gaps switch was at 1")
    }

    // MARK: - The process's own environment

    /// The only case that leaves the argument out. It asks of each call whether it skipped exactly when this
    /// process's own variable is not `1`, so it is green when a person has asked for neither, for one or for
    /// both. That also bounds it: a call that read an empty environment would agree with a run in which
    /// nothing was asked for, and only a run with a switch at `1` can tell the two apart.
    func testTheDefaultReadsTheProcesssOwnEnvironment() throws {
        let own = ProcessInfo.processInfo.environment

        let gap = try skipMessage { try SkipUnlessAsked.knownGap("some-id", "what is wrong") }
        XCTAssertEqual(gap != nil, own["HELM_KNOWN_GAPS"] != "1",
                       "a known gap and the process disagree about HELM_KNOWN_GAPS="
                       + String(reflecting: own["HELM_KNOWN_GAPS"]))

        let benchmark = try skipMessage { try SkipUnlessAsked.benchmark() }
        XCTAssertEqual(benchmark != nil, own["HELM_BENCH"] != "1",
                       "a benchmark and the process disagree about HELM_BENCH="
                       + String(reflecting: own["HELM_BENCH"]))
    }

    // MARK: - Catching the skip

    /// What `body` skipped with, or `nil` when it came back. The skip stops here, so the case that called
    /// this never ends as skipped; any other error goes on out and fails the case.
    private func skipMessage(_ body: () throws -> Void) throws -> String? {
        do {
            try body()
            return nil
        } catch let skip as XCTSkip {
            return skip.message ?? "(skipped with no reason)"
        }
    }
}
