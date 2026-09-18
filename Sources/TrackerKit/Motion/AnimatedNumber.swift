import SwiftUI

// MARK: - AnimatedNumber

/// A number that counts up to its value.
///
/// Driven by an `animatableData` shape modifier rather than a timer, so it runs on
/// the render thread, respects Reduce Motion, and interrupts cleanly when the
/// value changes mid-flight.
public struct AnimatedNumber: View, Animatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var value: Double
    private let unit: String
    private let font: Font
    private let color: Color?
    private let maximumFractionDigits: Int

    public var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    public init(
        value: Double,
        unit: String = "",
        font: Font = .largeTitle.weight(.bold),
        color: Color? = nil,
        maximumFractionDigits: Int = 0
    ) {
        self.value = value
        self.unit = unit
        self.font = font
        self.color = color
        self.maximumFractionDigits = maximumFractionDigits
    }

    public var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color ?? .primary)
            .contentTransition(.numericText())
            .accessibilityLabel(text)
    }

    private var text: String {
        unit.isEmpty
            ? Formatters.number(value, maximumFractionDigits: maximumFractionDigits)
            : Formatters.value(value, unit: unit)
    }
}

// MARK: - CountUpText

/// Wraps ``AnimatedNumber`` with the count-up trigger built in, so a caller can
/// drop in a final value and get the animation for free.
public struct CountUpText: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Double = 0

    private let target: Double
    private let unit: String
    private let font: Font
    private let color: Color?

    public init(
        value: Double,
        unit: String = "",
        font: Font = .largeTitle.weight(.bold),
        color: Color? = nil
    ) {
        self.target = value
        self.unit = unit
        self.font = font
        self.color = color
    }

    public var body: some View {
        AnimatedNumber(value: displayed, unit: unit, font: font, color: color)
            .onAppear {
                guard theme.motion.animatesOnAppear, !reduceMotion else {
                    displayed = target
                    return
                }
                displayed = 0
                withAnimation(.easeOut(duration: theme.motion.countUpDuration)) {
                    displayed = target
                }
            }
            .onChange(of: target) { _, newValue in
                withAnimation(.easeOut(duration: theme.motion.countUpDuration * 0.6)) {
                    displayed = newValue
                }
            }
    }
}

// MARK: - PulseOnChange

/// A brief scale pulse when a value changes — the "that landed" feedback after
/// logging an entry. Silent under Reduce Motion.
public struct PulseOnChange<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    let value: Value

    public func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: value) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { scale = 1.12 }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.12)) { scale = 1 }
            }
    }
}

public extension View {
    /// Pulses this view whenever `value` changes.
    func pulse<Value: Equatable>(on value: Value) -> some View {
        modifier(PulseOnChange(value: value))
    }
}

// MARK: - StaggeredAppear

/// Fades and lifts a view in, offset by its position in a list. Used on dashboard
/// tiles so the screen assembles rather than snapping.
public struct StaggeredAppear: ViewModifier {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    let index: Int

    public func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                guard theme.motion.animatesOnAppear, !reduceMotion else {
                    shown = true
                    return
                }
                withAnimation(
                    theme.motion.fillAnimation.delay(Double(index) * theme.motion.stagger)
                ) {
                    shown = true
                }
            }
    }
}

public extension View {
    /// Staggered entrance. Pass the view's index in its container.
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}
