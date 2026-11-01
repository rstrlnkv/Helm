import HelmUI
import SwiftUI

/// The motion modifiers, each in its states. It starts open so the accordion's block is measured at once.
private struct MotionSamples: View {
    @State private var open = true
    @State private var height: CGFloat?
    @State private var on = false
    @State private var since = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s6) {
            Button(Sample.short) { withAnimation(HelmMotion.disclosure) { open.toggle() }; on.toggle() }
            Text(verbatim: Sample.russianNote).fixedSize(horizontal: false, vertical: true)
                .helmAccordion(open: open, height: $height).frame(width: 320)
            HStack(spacing: HelmSpace.s6) {
                Image(systemName: "arrow.clockwise").helmSteadySpin(true)
                Image(systemName: "arrow.clockwise").helmSteadySpin(false)
                Image(systemName: on ? "info.circle.fill" : "info.circle")
                    .helmSymbolSwap(on ? "info.circle.fill" : "info.circle")
            }
            HStack(spacing: HelmSpace.s6) {
                HelmExpectedWait(started: nil, expected: 20)
                HelmExpectedWait(started: since, expected: 3600)
                HelmExpectedWait(started: since.addingTimeInterval(-60), expected: 20)
            }
            Text(verbatim: Sample.title).padding(HelmSpace.s5).helmCard().helmMeasuringSlot(true).frame(width: 200)
            Text(verbatim: Sample.title).padding(HelmSpace.s5).helmCard().helmMeasuringSlot(false).frame(width: 200)
        }
    }
}

struct MotionBoard: View {
    var body: some View {
        Board(name: "Motion", caption: """
            A still is one frame: motion is judged by a recording of this window, by its number. The button \
            opens and closes the accordion and swaps the symbol. Spin on and off; the wait shows an unknown \
            wait, one within its expectation and one past it; the measuring slot true and false.
            """) {
            MotionSamples()
        }
    }
}
