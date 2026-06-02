import SwiftUI
import UIKit

/// Drives the "fling the answered row across the screen and into the stats tab" flourish.
/// A row hands off its logo + global frame; ContentView renders the flight as an overlay.
@MainActor
final class FlyCoordinator: ObservableObject {
    struct Flight: Identifiable {
        let id = UUID()
        let image: UIImage?
        let color: Color
        let start: CGRect   // global coordinates
    }

    @Published var flight: Flight?

    func launch(image: UIImage?, color: Color, from start: CGRect) {
        flight = Flight(image: image, color: color, start: start)
    }

    func clear() { flight = nil }
}

/// The condensed logo that flings to a random spot, then homes into the stats tab.
struct FlyingLogoView: View {
    let flight: FlyCoordinator.Flight
    let target: CGPoint
    let screen: CGSize
    let onDone: () -> Void

    @State private var position: CGPoint
    @State private var side: CGFloat
    @State private var angle: Double = 0
    @State private var opacity: Double = 1

    init(flight: FlyCoordinator.Flight, target: CGPoint, screen: CGSize, onDone: @escaping () -> Void) {
        self.flight = flight
        self.target = target
        self.screen = screen
        self.onDone = onDone
        _position = State(initialValue: CGPoint(x: flight.start.midX, y: flight.start.midY))
        _side = State(initialValue: max(36, flight.start.height))
    }

    var body: some View {
        logo
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
            .rotationEffect(.degrees(angle))
            .opacity(opacity)
            .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
            .position(position)
            .allowsHitTesting(false)
            .onAppear(perform: fling)
    }

    @ViewBuilder private var logo: some View {
        if let image = flight.image {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(flight.color)
        }
    }

    private func fling() {
        let randomSpot = CGPoint(
            x: CGFloat.random(in: 50...max(60, screen.width - 50)),
            y: CGFloat.random(in: 90...max(120, screen.height * 0.5))
        )
        // 1) fling out to a random spot with a tumble
        withAnimation(.easeOut(duration: 0.38)) {
            position = randomSpot
            angle = Double.random(in: -540...540)
            side = 54
        }
        // 2) home into the stats tab, shrinking away
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation(.easeIn(duration: 0.5)) {
                position = target
                side = 22
                opacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onDone() }
    }
}
