import SwiftUI

// MARK: - Animation System

/// Animation presets inspired by The Outsiders' buttery-smooth motion design
enum AppAnimation {
    // MARK: - Spring Animations

    /// Snappy spring - quick response, moderate damping
    /// Use for: button taps, quick state changes
    static let springSnappy = Animation.spring(response: 0.35, dampingFraction: 0.7)

    /// Gentle spring - slower response, high damping
    /// Use for: page transitions, large element movements
    static let springGentle = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// Bouncy spring - moderate response, lower damping for overshoot
    /// Use for: celebratory animations, emphasis effects
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)

    /// Smooth spring - balanced for general use
    /// Use for: most UI interactions
    static let springSmooth = Animation.spring(response: 0.45, dampingFraction: 0.75)

    // MARK: - Timing Curves

    /// Ease out - quick start, slow finish
    /// Use for: elements appearing
    static let easeOut = Animation.easeOut(duration: 0.3)

    /// Ease in - slow start, quick finish
    /// Use for: elements disappearing
    static let easeIn = Animation.easeIn(duration: 0.25)

    /// Ease in out - smooth both ends
    /// Use for: state transitions
    static let easeInOut = Animation.easeInOut(duration: 0.35)

    // MARK: - Duration Constants

    /// Quick duration for micro-interactions
    static let durationQuick: Double = 0.15

    /// Standard duration for most animations
    static let durationStandard: Double = 0.3

    /// Slow duration for emphasis
    static let durationSlow: Double = 0.5

    /// Extra slow for dramatic effect
    static let durationExtraSlow: Double = 0.8

    // MARK: - Stagger Delays

    /// Calculate stagger delay for list animations
    /// - Parameter index: The index of the item in the list
    /// - Returns: Delay in seconds
    static func staggerDelay(_ index: Int) -> Double {
        Double(index) * 0.05
    }

    /// Calculate stagger delay with custom interval
    /// - Parameters:
    ///   - index: The index of the item
    ///   - interval: Time between each item
    /// - Returns: Delay in seconds
    static func staggerDelay(_ index: Int, interval: Double) -> Double {
        Double(index) * interval
    }
}

// MARK: - Animated Appearance Modifier

/// A view modifier that animates content appearing with a staggered delay
struct AnimatedAppearance: ViewModifier {
    let index: Int
    let animation: Animation

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                withAnimation(animation.delay(AppAnimation.staggerDelay(index))) {
                    isVisible = true
                }
            }
    }
}

/// A view modifier for scale-based appearance animation
struct ScaleAppearance: ViewModifier {
    let index: Int
    let animation: Animation

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.8)
            .onAppear {
                withAnimation(animation.delay(AppAnimation.staggerDelay(index))) {
                    isVisible = true
                }
            }
    }
}

/// A view modifier for slide-in appearance animation
struct SlideAppearance: ViewModifier {
    let index: Int
    let edge: Edge
    let animation: Animation

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(x: offsetX, y: offsetY)
            .onAppear {
                withAnimation(animation.delay(AppAnimation.staggerDelay(index))) {
                    isVisible = true
                }
            }
    }

    private var offsetX: CGFloat {
        guard !isVisible else { return 0 }
        switch edge {
        case .leading: return -30
        case .trailing: return 30
        default: return 0
        }
    }

    private var offsetY: CGFloat {
        guard !isVisible else { return 0 }
        switch edge {
        case .top: return -30
        case .bottom: return 30
        default: return 0
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Applies staggered fade-in animation
    /// - Parameters:
    ///   - index: Position in list for stagger calculation
    ///   - animation: Animation to use (default: springSmooth)
    func animatedAppearance(
        index: Int = 0,
        animation: Animation = AppAnimation.springSmooth
    ) -> some View {
        modifier(AnimatedAppearance(index: index, animation: animation))
    }

    /// Applies staggered scale-in animation
    /// - Parameters:
    ///   - index: Position in list for stagger calculation
    ///   - animation: Animation to use (default: springBouncy)
    func scaleAppearance(
        index: Int = 0,
        animation: Animation = AppAnimation.springBouncy
    ) -> some View {
        modifier(ScaleAppearance(index: index, animation: animation))
    }

    /// Applies staggered slide-in animation
    /// - Parameters:
    ///   - index: Position in list for stagger calculation
    ///   - edge: Edge to slide from
    ///   - animation: Animation to use (default: springSmooth)
    func slideAppearance(
        index: Int = 0,
        from edge: Edge = .bottom,
        animation: Animation = AppAnimation.springSmooth
    ) -> some View {
        modifier(SlideAppearance(index: index, edge: edge, animation: animation))
    }
}

// MARK: - Pulsing Animation

/// A view modifier that creates a subtle pulsing glow effect
struct PulsingGlow: ViewModifier {
    let color: Color
    let radius: CGFloat

    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: color.opacity(isPulsing ? 0.6 : 0.3),
                radius: isPulsing ? radius * 1.2 : radius
            )
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    /// Adds a pulsing glow effect
    /// - Parameters:
    ///   - color: Glow color
    ///   - radius: Base glow radius
    func pulsingGlow(color: Color, radius: CGFloat = 10) -> some View {
        modifier(PulsingGlow(color: color, radius: radius))
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: Spacing.xl) {
            Text("Animation Demos")
                .font(AppFont.displaySmall)
                .foregroundStyle(Color.textPrimary)

            // Staggered appearance
            VStack(spacing: Spacing.sm) {
                Text("Staggered Appearance")
                    .sectionHeaderStyle()

                ForEach(0..<4) { index in
                    Text("Item \(index + 1)")
                        .font(AppFont.bodyLarge)
                        .foregroundStyle(Color.textPrimary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .cardBackground()
                        .animatedAppearance(index: index)
                }
            }

            // Scale appearance
            VStack(spacing: Spacing.sm) {
                Text("Scale Appearance")
                    .sectionHeaderStyle()

                HStack(spacing: Spacing.sm) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.accentPrimary)
                            .frame(width: 60, height: 60)
                            .scaleAppearance(index: index)
                    }
                }
            }

            // Pulsing glow
            VStack(spacing: Spacing.sm) {
                Text("Pulsing Glow")
                    .sectionHeaderStyle()

                Circle()
                    .fill(Color.statusExcellent)
                    .frame(width: 80, height: 80)
                    .pulsingGlow(color: .statusExcellent, radius: 15)
            }
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
