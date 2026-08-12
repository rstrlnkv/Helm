import Foundation
import UserNotifications

/// What macOS says about this app's permission to post banners.
public enum NoticeAuthorization: Sendable {
    case notDetermined, authorized, denied
}

/// A notification's two lines, written by whoever speaks the person's language.
///
/// The port below takes `title:` and `body:` because that is
/// `UNMutableNotificationContent`'s own shape. This type exists for the other
/// half of the journey: `L()` lives in `HelmUI`, which no engine may import, so
/// an engine that posts a banner is handed the words already written and never
/// composes them. Two strings travelling together as one value, so a caller
/// cannot hand over a body with no title or swap the pair.
public struct NoticeText: Sendable, Equatable {
    public let title: String
    public let body: String
    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// Posts a macOS banner, and answers for the permission macOS gates it behind.
///
/// Reading the state and asking for it are separate calls on purpose: reading
/// prompts nobody, asking prompts once and is never undone. Which of the two
/// happens is each module's own policy — VPN asks when the person picks the
/// banner mode, Keep Awake asks the first time its battery guard has something
/// to say — and this port has no opinion about it.
public protocol AutomationNoticePort: AnyObject, Sendable {
    func authorizationState() async -> NoticeAuthorization
    func requestAuthorization() async -> NoticeAuthorization
    func post(title: String, body: String) async
}

/// Production `AutomationNoticePort`: `UNUserNotificationCenter`.
///
/// It lived in VPN's engine until Keep Awake's battery veto needed one too —
/// the veto being the one event this app has that happens with nobody in front
/// of the screen. Two modules, so it is plumbing, and plumbing lives here.
///
/// `UNUserNotificationCenter.current()` raises `NSInternalInconsistencyException`
/// — "bundleProxyForCurrentProcess is nil" — in any process that is not a
/// bundled app, and an ObjC exception does not fail a test case: it kills the
/// whole `swift test` run. Hence two defences. The centre is reached inside
/// each method and never in `init`, so constructing one stays free for the
/// tests that build a descriptor or an engine; and `isBundledApp` below answers
/// before anything is asked, so a test that does reach one of these methods
/// gets a refusal instead of ending the run.
public final class SystemAutomationNotice: AutomationNoticePort {
    /// The log area of the module this one belongs to — «vpn», «keepawake».
    /// Passed in rather than fixed, because the one thing this class says in the
    /// log is that the banners are dead, and the module it is dead for is the
    /// whole of that line's value.
    private let area: String

    public init(area: String) { self.area = area }

    /// Whether this process is the kind macOS will answer for.
    ///
    /// Measured, not assumed — the identifier is no help: under `xctest`
    /// `Bundle.main.bundleIdentifier` is `com.apple.dt.xctest.tool`, thoroughly
    /// non-nil, while its bundle path is
    /// `/Applications/Xcode.app/Contents/Developer/usr/bin`, which is a
    /// directory and not a bundle. The shipped app's is `Helm.app`.
    private var isBundledApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Says so in the log, because in the app this can only mean the banners
    /// are dead: `notDetermined` is what an unbundled process knows about
    /// permissions, which is nothing.
    @discardableResult
    private func unbundled() -> NoticeAuthorization {
        HelmLog.shared.warn(area, "no bundle identity, so macOS was not asked about banners")
        return .notDetermined
    }

    public func authorizationState() async -> NoticeAuthorization {
        guard isBundledApp else { return unbundled() }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        // Provisional and ephemeral both post without a prompt, so for the one
        // question this port answers — will a banner appear — they are yes.
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// macOS shows the prompt only the first time; afterwards this returns the
    /// standing answer without troubling anyone.
    public func requestAuthorization() async -> NoticeAuthorization {
        guard isBundledApp else { return unbundled() }
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert])
            return granted ? .authorized : .denied
        } catch {
            HelmLog.shared.warn(area, "could not ask macOS about banners: "
                + HelmFailure.describe(error))
            return .denied
        }
    }

    /// No trigger: nil means now, which is what a rule that has already fired
    /// needs. The identifier is fresh each time so two firings stack instead of
    /// the second replacing the first.
    public func post(title: String, body: String) async {
        guard isBundledApp else { unbundled(); return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Whatever the banner names is in `body`, and the log carries no names.
            HelmLog.shared.warn(area, "macOS refused the banner: "
                + HelmFailure.describe(error))
        }
    }
}
