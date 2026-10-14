import AppKit
@preconcurrency import Combine
import CoreGraphics
import Foundation
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Screenshots_UI

/// What the families about a display that comes or goes share: the notification AppKit posts and the wait for the
/// listener's answer, the plaque as the after-shot window holds it and the count of plaques it was given, a test clock
/// that stands still until it is opened, and a reading of ink in a picture.
@MainActor
enum DisplayChange {

    /// The notification as AppKit posts it (the application is its object), `times` times in a row, and a return once the
    /// main queue has delivered every one to a block of this test's own. That block is registered after every listener
    /// the capture holds, so the listeners' blocks of the same post have run first: nothing is waited for by the clock.
    /// Posting it moves no window and changes no display of the Mac.
    static func happens(times: Int = 1) async {
        final class Heard: @unchecked Sendable { var token: NSObjectProtocol?; var count = 0 }
        let heard = Heard()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            heard.token = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { _ in
                heard.count += 1
                guard heard.count == times else { return }
                if let token = heard.token { NotificationCenter.default.removeObserver(token) }
                done.resume()
            }
            for _ in 0..<times {
                NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApplication.shared)
            }
        }
    }

    /// The sentence of the plaque, spelled out for each language: the words of the string tables as they stand, so that a
    /// plaque saying another sentence, an empty one or the English one in a language that has its own reads red.
    static let sentences: [AppLanguage: String] = [
        .en: "The display configuration changed.",
        .de: "Die Bildschirmkonfiguration hat sich geändert.",
        .es: "La configuración de las pantallas cambió.",
        .fr: "La configuration des écrans a changé.",
        .ja: "ディスプレイの構成が変更されました。",
        .pt: "A configuração das telas mudou.",
        .ru: "Конфигурация дисплеев изменилась.",
        .zh: "显示器配置已更改。",
    ]

    /// The two titles a plaque for a display change has: for a capture that was under way, and for a shot that was taken.
    enum Title {
        case notTaken, ofAShot
        var text: String { self == .notTaken ? ScStr.failedTitle : ScStr.thumbnailLabel }
        var other: String { self == .notTaken ? ScStr.thumbnailLabel : ScStr.failedTitle }
    }

    /// Every plaque a toast was given, counted as it was given: a window that said the same sentence twice reads two.
    @MainActor final class Plaques {
        private var subscription: AnyCancellable?
        private(set) var heard: [(title: String, body: String)] = []
        var count: Int { heard.count }
        init(_ toast: ShotToast) {
            subscription = toast.model.$refusal.sink { [weak self] content in
                guard case .refusal(let title, let body, _)? = content else { return }
                MainActor.assumeIsolated { self?.heard.append((title, body)) }
            }
        }
    }

    /// The body of the plaque the toast holds now, nil where it holds none.
    static func plaque(of toast: ShotToast) -> String? {
        guard case .refusal(_, let body, _)? = toast.model.refusal else { return nil }
        return body
    }

    /// The body of the first plaque the toast shows: at once where it holds one, else when the toast is given it. Waits on
    /// the toast's own publication, and only the failing run spends the `limit`.
    static func nextPlaque(of toast: ShotToast, limit: TimeInterval = 10) async -> String? {
        if let body = plaque(of: toast) { return body }
        let arrivals = AsyncStream<String> { stream in
            let subscription = toast.model.$refusal.sink { content in
                if case .refusal(_, let body, _)? = content { stream.yield(body) }
            }
            let watchdog = Task { try? await Task.sleep(for: .seconds(limit)); stream.finish() }
            stream.onTermination = { _ in subscription.cancel(); watchdog.cancel() }
        }
        for await body in arrivals { return body }
        return nil
    }

    /// One plaque is up, in the language the case runs in: the sentence is the table's for that language, word for word, the
    /// title is the one asked for and not the other, the plaque does not offer «Open Settings», and the toast was given it once.
    static func assertPlaque(of toast: ShotToast, _ plaques: Plaques, _ what: String, titled title: Title,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard case .refusal(let heardTitle, let body, let offersSettings)? = toast.model.refusal else {
            return XCTFail("\(what): the window holds no plaque: \(String(describing: toast.model.content))", file: file, line: line)
        }
        let language = AppLanguage.current
        XCTAssertEqual(body, sentences[language], "\(what): the plaque does not say the sentence in \(language)", file: file, line: line)
        XCTAssertEqual(body, ScStr.refusal(.displayChanged), "\(what): the plaque does not say the sentence the strings accessor gives", file: file, line: line)
        XCTAssertEqual(heardTitle, title.text, "\(what): the plaque is titled «\(heardTitle)» in \(language)", file: file, line: line)
        XCTAssertNotEqual(title.text, title.other, "\(what): the two titles read alike in \(language), so the title is not told apart", file: file, line: line)
        XCTAssertFalse(offersSettings, "\(what): the plaque offers Open Settings", file: file, line: line)
        XCTAssertEqual(plaques.count, 1, "\(what): the window was given \(plaques.count) plaques: \(plaques.heard)", file: file, line: line)
    }

    /// A clock for the controller's countdown that stands still: every second after the first `passing` waits until the test
    /// opens it, and after that every second passes at once. It counts the seconds asked for and the seconds that passed.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var asked = 0, passed = 0
        private let gate = PromptGate()
        private let passing: Int
        init(passing: Int = 0) { self.passing = passing }
        /// Seconds the countdown asked this clock for.
        var calls: Int { lock.withLock { asked } }
        /// Seconds that came to their end.
        var returned: Int { lock.withLock { passed } }
        var tick: @Sendable (Duration) async throws -> Void {
            { [self] _ in
                let number = lock.withLock { asked += 1; return asked }
                if number > passing { await gate.arrive() }
                lock.withLock { passed += 1 }
            }
        }
        func reached(file: StaticString = #filePath, line: UInt = #line) async { await gate.reached(file: file, line: line) }
        func open() async { await gate.open() }
        /// A clock nobody holds: every second passes at once.
        static let idle: @Sendable (Duration) async throws -> Void = { _ in }
    }

    /// Pixels of `image` within `radius` of `point` that differ from the picture's own ground (its last pixel) by more
    /// than 60 in a channel: the ink of a mark, and nothing where there is none.
    static func ink(in image: CGImage, near point: CGPoint, radius: Int = 4) -> Int {
        guard let bytes = try? ScreenAndFile.rgb(image) else { return -1 }
        let width = image.width, height = image.height
        func at(_ x: Int, _ y: Int) -> [Int] {
            let i = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
            return [Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])]
        }
        let ground = at(width - 1, height - 1)
        var count = 0
        for y in Int(point.y) - radius...Int(point.y) + radius {
            for x in Int(point.x) - radius...Int(point.x) + radius where x >= 0 && y >= 0 && x < width && y < height {
                if zip(at(x, y), ground).contains(where: { abs($0 - $1) > 60 }) { count += 1 }
            }
        }
        return count
    }

    /// Where the rectangle `PileScene.draw` makes, (300, 300) to (500, 450) of the display, stands in a picture that the
    /// editor shows with its corner at `origin` of the display: a pixel on its right edge, a pixel inside it, and one far from it.
    static func mark(origin: CGPoint, size: CGSize) -> (onTheStroke: CGPoint, inside: CGPoint, far: CGPoint) {
        (CGPoint(x: 500 - origin.x, y: 375 - origin.y), CGPoint(x: 400 - origin.x, y: 375 - origin.y),
         CGPoint(x: size.width - 30, y: size.height - 30))
    }

    /// Whether `image` carries that mark and nothing else of the kind.
    static func isMarked(_ image: CGImage?, origin: CGPoint, size: CGSize) -> Bool {
        guard let image, CGFloat(image.width) == size.width, CGFloat(image.height) == size.height else { return false }
        let spots = mark(origin: origin, size: size)
        return ink(in: image, near: spots.onTheStroke) > 0 && ink(in: image, near: spots.inside) == 0 && ink(in: image, near: spots.far) == 0
    }

    /// Whether the controller has a display listener registered now, read from its private property; nil where the property
    /// is not there to read (a rename), so that a reading of nothing is not taken for «no listener».
    static func listening(_ controller: CaptureController) -> Bool? {
        guard let child = Mirror(reflecting: controller).children.first(where: { $0.label == "displayObserver" }) else { return nil }
        let reflected = Mirror(reflecting: child.value)
        guard reflected.displayStyle == .optional else { return nil }
        return !reflected.children.isEmpty
    }
}
