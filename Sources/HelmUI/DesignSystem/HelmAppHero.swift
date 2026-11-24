import SwiftUI

/// The app's mark in its bezel over the wordmark and a tagline — what the About page introduces itself with.
///
/// The bezel turns only while `active`: motion here means work, not decoration. No halo behind the mark:
/// `HelmAppMark` casts its own shadow, and a radial gradient would be a second light source with a visible rim.
public struct HelmAppHero<Badge: View>: View {
    private let active: Bool
    private let tagline: String
    private let spoken: String
    private let badge: Badge

    /// - Parameters:
    ///   - spoken: what VoiceOver reads for the wordmark with its badge.
    ///   - badge: hangs off the wordmark and takes no width (see `body`).
    public init(active: Bool, tagline: String, spoken: String, @ViewBuilder badge: () -> Badge) {
        self.active = active
        self.tagline = tagline
        self.spoken = spoken
        self.badge = badge()
    }

    public var body: some View {
        VStack(spacing: HelmSpace.s5) {
            ZStack {
                HelmBezel(active: active)
                    .frame(width: 172, height: 172)
                HelmAppMark(size: 92)
            }
            .frame(height: 186)
            VStack(spacing: 5) {
                // The badges hang off the wordmark instead of sharing a row with it: in an HStack the pair is
                // centred together, which puts the name off the axis the mark and the tagline are centred on.
                // As an overlay they take no width, so "Helm" is centred on the same line as everything else.
                Text(verbatim: "Helm")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.4)
                    .overlay(alignment: .topTrailing) {
                        badge
                            .fixedSize()
                            // The overlay's own leading edge, placed 7 pt past the end of the word.
                            .alignmentGuide(.trailing) { $0[.leading] - 7 }
                            // The top of the capsule on the top of the H: at 34 pt semibold the cap starts 9 pt
                            // below the line box's top, measured off rendered pixels.
                            .alignmentGuide(.top) { $0[.top] - 9 }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(spoken)
                Text(tagline)
                    .helmQuietDetail()
            }
        }
    }
}

/// A compass/helm bezel: fine tick marks ringing the app icon, every fifth one
/// longer. It rotates only while an update check is in flight.
private struct HelmBezel: View {
    var active: Bool
    /// Where the dial stands when nothing is driving it.
    @State private var resting: Double = 0
    /// When the current turn began — the angle is a **function of time**, not a
    /// value being animated towards.
    ///
    /// With `repeatForever` the model sits at 360 while the dial is somewhere
    /// inside the turn, so a stop by retargeting runs backwards. Driven from a
    /// clock there is no target: the stop reads the angle reached and coasts
    /// forward from there.
    @State private var since: Date?

    private static let secondsPerTurn: Double = 6

    private func angle(_ now: Date) -> Double {
        guard let since else { return resting }
        return resting + now.timeIntervalSince(since) / Self.secondsPerTurn * 360
    }

    var body: some View {
        // Paused rather than switched away from: an `if` here would swap the
        // view's identity at the moment of stopping, and a newly inserted view
        // has no previous angle to interpolate from — the coast would not play.
        TimelineView(.animation(paused: since == nil)) { timeline in
            dial.rotationEffect(.degrees(angle(timeline.date)))
        }
        .onChange(of: active) { _, running in
            if running {
                // Reduce Motion: no spin at all, rather than a fast one.
                guard !HelmMotion.reduceMotion else { return }
                since = .now
            } else if since != nil {
                let reached = angle(.now)
                since = nil
                resting = reached
                withAnimation(HelmMotion.spinDown) { resting = reached + 24 }
            }
        }
        .accessibilityHidden(true)
    }

    private var dial: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for tick in 0..<60 {
                let long = tick % 5 == 0
                let length: CGFloat = long ? 7 : 4
                let a = Double(tick) / 60 * 2 * .pi
                let outer = CGPoint(x: center.x + cos(a) * radius,
                                    y: center.y + sin(a) * radius)
                let inner = CGPoint(x: center.x + cos(a) * (radius - length),
                                    y: center.y + sin(a) * (radius - length))
                var path = Path()
                path.move(to: inner)
                path.addLine(to: outer)
                context.stroke(path,
                               with: .color(.primary.opacity(long ? 0.20 : 0.10)),
                               lineWidth: long ? 1.4 : 1)
            }
        }
    }
}
