import XCTest
import HelmContract
import HelmTestSupport
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// The whole path of a press on Stop: view model → port → engine → the child's
/// handle. Driven over the real engine, because the act crosses a target
/// boundary and only the trip proves the two sides agree.
/// Kept: guards the defect fixed in 882fe986 fix(homebrew): the batch — a hang has a deadline, a press has an answer, a phase has a name.
@MainActor
final class TheStopButtonReachesTheChildTests: XCTestCase {

    func testStopFromTheViewModelTerminatesTheChild() async {
        let runner = FakeBrew(hangingStreams: true)
        let news = EngineNews<HomebrewNews>()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    news: news)
        defer { _ = engine }
        let model = HomebrewViewModel(work: engine)

        model.upgradeAll()
        await waitUntil("the operation was seen running") { model.op.phase == .running }
        await waitUntil("the stream started") { !runner.handles.isEmpty }

        model.stopOperation()

        await waitUntil("the child was terminated") { runner.handles.first?.terminated == true }
    }
}
