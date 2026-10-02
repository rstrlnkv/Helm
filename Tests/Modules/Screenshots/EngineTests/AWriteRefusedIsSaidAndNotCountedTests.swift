import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A refused write is a refusal in the answer and a line in the log, and is
/// never counted as a file.** The clipboard is a separate fact: a save that was
/// refused while the copy landed is one thing done and one not, and the answer
/// says both.
final class AWriteRefusedIsSaidAndNotCountedTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    func testEveryKindOfRefusalReachesTheAnswer() async throws {
        let reasons: [WriteRefusal] = [.noFolder, .notAFolder, .noPermission, .diskFull, .namesExhausted, .failed(5)]
        for reason in reasons {
            let rig = Rig(home: scratchDirectory("shots-refused"))
            rig.writer.refuse = reason
            let delivery = await rig.session.deliver(makeImage(width: 10, height: 10), saves: true, copies: false)
            XCTAssertEqual(delivery.files, [], "\(reason) was counted as a file")
            XCTAssertEqual(delivery.refusals, [.write(reason)])
        }
    }

    func testARefusedSaveStillCopiesAndSaysBoth() async throws {
        let rig = Rig(home: scratchDirectory("shots-refused-copy"))
        rig.writer.refuse = .diskFull
        let delivery = await rig.session.deliver(makeImage(width: 10, height: 10), saves: true, copies: true)
        XCTAssertTrue(delivery.copied)
        XCTAssertEqual(delivery.files, [])
        XCTAssertEqual(delivery.refusals, [.write(.diskFull)])
    }

    func testAClipboardThatRefusesIsSaid() async throws {
        let rig = Rig(home: scratchDirectory("shots-refused-clip"))
        rig.pasteboard.accepts = false
        let delivery = await rig.session.deliver(makeImage(width: 10, height: 10), saves: true, copies: true)
        XCTAssertFalse(delivery.copied)
        XCTAssertEqual(delivery.refusals, [.pasteboard])
        XCTAssertEqual(delivery.files.count, 1, "a refused clipboard stopped the save")
    }

    func testTheLogSaysWhyAndNamesNoPath() async throws {
        ScreenshotsLog.proveTheLogIsOn()
        // The real home, so `Redact.path` has a prefix to turn into «~». The fake
        // writer writes nothing; the only thing this touches on disk is that
        // `~/Desktop` exists, as it does on every Mac.
        let rig = Rig(home: URL(fileURLWithPath: NSHomeDirectory()))
        rig.writer.refuse = .noPermission
        _ = await rig.session.deliver(makeImage(width: 10, height: 10), saves: true, copies: false)

        let refusal = ScreenshotsLog.lines.filter { $0.contains("save refused") }
        XCTAssertEqual(refusal.count, 1, "\(ScreenshotsLog.lines)")
        XCTAssertTrue(refusal[0].contains("noPermission"), refusal[0])
        XCTAssertTrue(refusal[0].contains("~/Desktop"), "the folder is not named at all, so the next assertion proves nothing: \(refusal[0])")
        // The home is somebody's name: `Redact.path` turns the prefix into «~».
        XCTAssertFalse(refusal[0].contains(NSHomeDirectory()), "a home path reached the log: \(refusal[0])")
        XCTAssertFalse(refusal[0].contains("Screenshot 2"), "a file name reached the log: \(refusal[0])")
    }
}
