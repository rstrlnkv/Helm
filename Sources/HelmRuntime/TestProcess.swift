import Foundation

/// Whether this is a test runner rather than the app.
///
/// Asked by anything that would otherwise write into somebody's real files
/// (the scan journal, the log, the support folder), so every answer to
/// "may a suite run touch a file a person keeps" is the same one.
///
/// **The test is whether XCTest is loaded, not an environment variable.**
/// `XCTestConfigurationFilePath` is Xcode's and `swift test` does not set it.
/// XCTest is in the process that runs tests and in no build of the app, the
/// env-gated screenshot harness included, which *is* the app.
///
/// Read once, because it cannot change while the process lives.
public enum TestProcess {
    public static let isRunning = NSClassFromString("XCTestCase") != nil
}
