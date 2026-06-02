import SwiftUI
import UIKit

/// A reminder row with a custom swipe-right-to-answer gesture. The green "answered"
/// area shares the row's rounded shape (no boxy system button). There's resistance +
/// a haptic detent once "answered" is fully revealed, and committing hands the row's
/// global frame to `onAnswer` so it can fling away.
struct AnswerSwipeRow<Content: View>: View {
    private let content: Content
    private let logo: UIImage?
    private let color: Color
    private let onAnswer: (CGRect, CGSize) -> Void

    @State private var offset: CGFloat = 0
    @State private var detented = false
    @State private var frame: CGRect = .zero

    private let revealWidth: CGFloat = 110
    private var commitWidth: CGFloat { UIScreen.main.bounds.width * 0.55 }

    init(
        logo: UIImage?,
        color: Color,
        onAnswer: @escaping (CGRect, CGSize) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.logo = logo
        self.color = color
        self.onAnswer = onAnswer
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accent)
                .overlay(alignment: .leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("answered")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.leading, 22)
                    .opacity(Double(min(1, offset / revealWidth)))
                }

            content.offset(x: offset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: RowFrameKey.self, value: geo.frame(in: .global))
            }
        )
        .onPreferenceChange(RowFrameKey.self) { frame = $0 }
        .simultaneousGesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let x = value.translation.width
                guard x > 0 else { offset = 0; return }
                // Move freely up to the reveal point, then add resistance (the "hesitation").
                offset = x <= revealWidth ? x : revealWidth + (x - revealWidth) * 0.28
                if !detented, x >= revealWidth {
                    detented = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } else if detented, x < revealWidth {
                    detented = false
                }
            }
            .onEnded { value in
                let x = value.translation.width
                let flung = value.predictedEndTranslation.width >= commitWidth * 1.3
                if x >= commitWidth || flung {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    onAnswer(frame, value.velocity)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = 0 }
                    detented = false
                }
            }
    }
}

private struct RowFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
