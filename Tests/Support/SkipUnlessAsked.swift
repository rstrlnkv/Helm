import Foundation
import XCTest

/// **A test that is left red on purpose, or that measures this Mac, runs only for a person who asked.**
///
/// Each entry point is the first line of the test it guards and either returns, and the body beneath it runs,
/// or throws `XCTSkip`, and the runner counts the test as skipped. The reproduction below the call is never
/// edited to make it so: a person who sets the switch to `1` gets the test as it was written.
///
/// **Only the value `1` asks.** Not an empty variable, not `0`, not `true`, not a `1` with a space or a sign
/// beside it. A switch that more spellings turned on would be turned on by a shell that exports it empty, and
/// every row that waits behind it would run in a suite that is meant to read green.
///
/// **The caller's file and line are forwarded to `XCTSkip`.** Left to its own defaults, the skip would carry
/// the location of the `throw` below, which is the same for every test that calls this; forwarded, it carries
/// the call in the test that was skipped.
///
/// **The environment is an argument**, defaulting to the process's own, so that a test of this type can hand
/// it any environment without setting a variable that every other test of the run would read.
public enum SkipUnlessAsked {
    /// The switch for a row that stands for a defect nobody has repaired.
    private static let knownGaps = "HELM_KNOWN_GAPS"

    /// The switch for a test that measures this Mac and prints a number.
    private static let bench = "HELM_BENCH"

    /// Skips the test unless `HELM_KNOWN_GAPS` reads `1`. The reason is «Known gap <id>: <gap>», with nothing
    /// added after `gap`, so a `gap` that ends in a full stop is read with it.
    ///
    /// - Parameters:
    ///   - id: the gap's name, as the sentence above the test spells it.
    ///   - gap: what is wrong, in one clause a person reads in the run's log.
    public static func knownGap(_ id: String, _ gap: String,
                                environment: [String: String] = ProcessInfo.processInfo.environment,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        try unless(knownGaps, in: environment, "Known gap \(id): \(gap)", file: file, line: line)
    }

    /// Skips the test unless `HELM_BENCH` reads `1`. The reason is «<what> — HELM_BENCH=1 to run».
    ///
    /// - Parameter what: what the test measures.
    public static func benchmark(_ what: String = "a measurement of this Mac",
                                 environment: [String: String] = ProcessInfo.processInfo.environment,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        try unless(bench, in: environment, "\(what) — HELM_BENCH=1 to run", file: file, line: line)
    }

    /// The one rule both entry points go through: `name` asks when it reads exactly `1`.
    private static func unless(_ name: String, in environment: [String: String], _ reason: String,
                               file: StaticString, line: UInt) throws {
        guard environment[name] != "1" else { return }
        throw XCTSkip(reason, file: file, line: line)
    }
}
