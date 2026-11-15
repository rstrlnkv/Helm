import Foundation

/// What a child process printed and how it ended.
public struct ChildResult {
    public let status: Int32
    public let output: String
    public let errors: String
}

/// Runs `executable` to its end and returns what it wrote.
///
/// **Standard output is read before the wait, and standard error beside it.** A pipe nobody drains is how a
/// test of a child process hangs for ever: the child blocks on a full pipe, and `waitUntilExit` waits on the
/// child. `mergeStderr` sends both streams into the one pipe, in the order the child wrote them; otherwise
/// `errors` holds standard error, drained on its own queue so neither pipe can stall the other.
/// `environment` nil inherits this process's, as `Process` does.
public func runChild(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                     directory: URL? = nil, mergeStderr: Bool = false) throws -> ChildResult {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = arguments
    proc.environment = environment
    proc.currentDirectoryURL = directory
    let out = Pipe(), err = Pipe()
    proc.standardOutput = out
    proc.standardError = mergeStderr ? out : err
    try proc.run()
    let errorData = Locked(Data())
    let drained = DispatchGroup()
    if !mergeStderr {
        DispatchQueue.global().async(group: drained) {
            errorData.value = err.fileHandleForReading.readDataToEndOfFile()
        }
    }
    let output = out.fileHandleForReading.readDataToEndOfFile()
    drained.wait()
    proc.waitUntilExit()
    return ChildResult(status: proc.terminationStatus, output: String(decoding: output, as: UTF8.self),
                       errors: String(decoding: errorData.value, as: UTF8.self))
}
