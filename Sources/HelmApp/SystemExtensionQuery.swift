import Foundation
import Module_Uninstaller_Engine

/// The settings screen lists system extensions whether or not the Uninstaller
/// module is enabled, so it reads them directly rather than over the module's
/// transport. Runs off the main thread: the lookup shells out.
enum SystemExtensionQuery {
    static func installed() async -> [SystemExtensionInfo] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: SystemExtensionLister().installedExtensions())
            }
        }
    }
}
