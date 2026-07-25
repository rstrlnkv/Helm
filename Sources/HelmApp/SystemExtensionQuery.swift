import Foundation
import HelmRuntime

/// Settings lists system extensions whether or not any module is enabled, so
/// it reads them via the shared CLI. Off the main thread: the lookup shells out.
enum SystemExtensionQuery {
    static func installed() async -> [SystemExtensionInfo] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: SystemExtensionCLI.installed())
            }
        }
    }
}
