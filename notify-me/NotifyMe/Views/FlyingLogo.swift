import SwiftUI
import UIKit

/// Drives the "answered row drops out and falls into the stats tab" flourish.
/// A row hands off its logo + global frame; ContentView renders the fall as an overlay
/// and lights up the stats tab icon as the logo lands.
@MainActor
final class FlyCoordinator: ObservableObject {
    struct Flight: Identifiable {
        let id = UUID()
        let image: UIImage?
        let color: Color
        let start: CGRect   // global coordinates
        let velocity: CGSize  // swipe velocity at release, points/sec
    }

    @Published var flight: Flight?

    func launch(image: UIImage?, color: Color, from start: CGRect, velocity: CGSize) {
        flight = Flight(image: image, color: color, start: start, velocity: velocity)
    }

    func clear() { flight = nil }
}

/// The condensed logo that falls from the row, arcing down into the stats tab.
struct FlyingLogoView: View {
    let flight: FlyCoordinator.Flight
    let target: CGPoint
    let screen: CGSize
    let onDone: () -> Void

    // KeyframeAnimator snaps its content back to the initial value when it finishes;
    // this hard-hides the whole flight once it's landed so that revert never shows.
    @State private var done = false

    /// Animatable bundle interpolated by the keyframe tracks below.
    private struct Values {
        var x: CGFloat
        var y: CGFloat
        var side: CGFloat
        var angle: Double
        var opacity: Double
    }

    private var start: CGPoint { CGPoint(x: flight.start.midX, y: flight.start.midY) }
    private var startSide: CGFloat { max(36, flight.start.height) }

    /// The top of the throw's arc: the icon launches along the swipe velocity to here,
    /// then gravity bends it down toward the stats tab. Travel scales with fling speed.
    private var apex: CGPoint {
        let v = flight.velocity
        // Swipe-to-answer is a rightward fling, so always carry a little to the right.
        let throwX = min(max(v.width * 0.13, 60), screen.width * 0.6)
        let throwY = min(max(v.height * 0.13, -screen.height * 0.22), screen.height * 0.10)
        let x = min(max(start.x + throwX, 28), screen.width - 28)
        let y = min(max(start.y + throwY, 80), target.y - 50)
        return CGPoint(x: x, y: y)
    }

    /// Spin scales with how hard it was flung; direction follows the swipe.
    private var tumble: Double {
        let v = flight.velocity
        let speed = (v.width * v.width + v.height * v.height).squareRoot()
        return min(max(speed * 0.35, 160), 540) * (v.width >= 0 ? 1 : -1)
    }

    var body: some View {
        KeyframeAnimator(
            initialValue: Values(x: start.x, y: start.y, side: startSide, angle: 0, opacity: 1)
        ) { v in
            logo
                .frame(width: v.side, height: v.side)
                .clipShape(RoundedRectangle(cornerRadius: v.side * 0.24, style: .continuous))
                .rotationEffect(.degrees(v.angle))
                .opacity(v.opacity)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
                .position(x: v.x, y: v.y)
                // Pin `.position` to an explicit full-screen frame so it resolves in
                // global coords (KeyframeAnimator otherwise collapses it to icon size).
                .frame(width: screen.width, height: screen.height)
        } keyframes: { _ in
            // Horizontal: punchy launch along the swipe, then curve in toward the stats tab.
            KeyframeTrack(\.x) {
                LinearKeyframe(apex.x, duration: 0.22)
                CubicKeyframe(target.x, duration: 0.56)
            }
            // Vertical: thrown out to the apex, then an accelerating gravity fall (two
            // segments — slower near the top, faster as it drops into the tab).
            KeyframeTrack(\.y) {
                LinearKeyframe(apex.y, duration: 0.22)
                CubicKeyframe(apex.y + (target.y - apex.y) * 0.45, duration: 0.32)
                CubicKeyframe(target.y, duration: 0.24)
            }
            // Hold size through the throw, then shrink to tab-icon size as it lands.
            KeyframeTrack(\.side) {
                LinearKeyframe(startSide, duration: 0.22)
                CubicKeyframe(24, duration: 0.56)
            }
            // Tumble through the whole flight.
            KeyframeTrack(\.angle) {
                CubicKeyframe(tumble, duration: 0.78)
            }
            // Fade out as it sinks into the stats icon (fully gone before it lands).
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 0.54)
                LinearKeyframe(0, duration: 0.16)
            }
        }
        // Once landed, force-hide outside the animator so its end-of-run revert to the
        // initial value (icon back at the row) never flashes on screen.
        .opacity(done ? 0 : 1)
        .allowsHitTesting(false)
        .onAppear {
            // Hard-hide just as the fade completes...
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) { done = true }
            // ...then tear the overlay down.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.82) { onDone() }
        }
    }

    @ViewBuilder private var logo: some View {
        if let image = flight.image {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(flight.color)
        }
    }
}
