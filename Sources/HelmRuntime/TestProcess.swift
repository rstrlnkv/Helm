import Foundation

/// Whether this is a test runner rather than the app.
///
/// Asked by anything that would otherwise write into somebody's real files. The
/// scan journal redirects into a temporary directory rather than into their
/// Application Support; so does the log, whose file is what a dev build is
/// triaged against before it ships. Both had spelled the question themselves,
/// which is the duplication `HelmRuntime` exists to end — and the two answers
/// have to agree, because the thing they decide is the same thing: whether a
/// suite run is allowed to touch a file a person keeps.
///
/// **The test is whether XCTest is loaded, not an environment variable.**
/// `XCTestConfigurationFilePath` is Xcode's and `swift test` does not set it,
/// which is how an earlier isolation guard read clean while the suite went on
/// writing into the real store. XCTest is in the process that runs tests and in
/// no build of the app — not the shipped bundle, and not the env-gated
/// screenshot harness, which *is* the app.
///
/// Read once, because it cannot change while the process lives.
public enum TestProcess {
    public static let isRunning = NSClassFromString("XCTestCase") != nil
}
