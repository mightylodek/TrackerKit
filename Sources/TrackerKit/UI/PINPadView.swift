import SwiftUI

/// The 4-digit keypad.
///
/// Built for a shared iPad held by a kid: big targets, obvious feedback, no
/// keyboard. The dots fill as digits land, the pad shakes on a wrong PIN, and a
/// lockout is stated plainly with a countdown rather than a generic failure.
public struct PINPadView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let profile: Profile
    private let pinLength: Int
    private let onSubmit: (String) -> PINVerification
    private let onCancel: (() -> Void)?
    private let title: String
    private let subtitle: String?

    @State private var entered = ""
    @State private var shake = 0
    @State private var message: String?
    @State private var lockedUntil: Date?
    @State private var now = Date.now

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(
        profile: Profile,
        pinLength: Int = 4,
        title: String? = nil,
        subtitle: String? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping (String) -> PINVerification
    ) {
        self.profile = profile
        self.pinLength = pinLength
        self.title = title ?? profile.name
        self.subtitle = subtitle
        self.onCancel = onCancel
        self.onSubmit = onSubmit
    }

    private var isLocked: Bool {
        guard let lockedUntil else { return false }
        return lockedUntil > now
    }

    private var lockoutRemaining: String {
        guard let lockedUntil else { return "" }
        let seconds = max(0, Int(lockedUntil.timeIntervalSince(now)))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return minutes > 0 ? "\(minutes)m \(remainder)s" : "\(remainder)s"
    }

    public var body: some View {
        VStack(spacing: 26) {
            header
            dots
            statusLine
            keypad

            if let onCancel {
                Button("Use a different profile", action: onCancel)
                    .font(theme.typography.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: 360)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 10) {
            ProfileAvatar(profile: profile, size: 68)
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text(subtitle ?? "Enter your \(pinLength)-digit PIN")
                .font(theme.typography.subheadline)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var dots: some View {
        HStack(spacing: 18) {
            ForEach(0..<pinLength, id: \.self) { index in
                Circle()
                    .strokeBorder(theme.axis, lineWidth: 1.5)
                    .background {
                        Circle().fill(index < entered.count ? theme.identityColor(for: profile) : .clear)
                    }
                    .frame(width: 17, height: 17)
                    .animation(theme.motion.snappyAnimation, value: entered.count)
            }
        }
        .modifier(ShakeEffect(travel: reduceMotion ? 0 : 8, shakes: shake))
        .accessibilityLabel("\(entered.count) of \(pinLength) digits entered")
    }

    @ViewBuilder
    private var statusLine: some View {
        if isLocked {
            Label("Locked — try again in \(lockoutRemaining)", systemImage: "lock.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(theme.statusColor(.red))
                .monospacedDigit()
        } else if let message {
            Text(message)
                .font(theme.typography.label)
                .foregroundStyle(theme.statusColor(.red))
                .transition(.opacity)
        } else {
            // Reserve the line so the pad doesn't jump when a message appears.
            Text(" ").font(theme.typography.label)
        }
    }

    private var keypad: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(1..<4, id: \.self) { column in
                        digitButton(row * 3 + column)
                    }
                }
            }
            HStack(spacing: 22) {
                Color.clear.frame(width: 74, height: 74)
                digitButton(0)
                deleteButton
            }
        }
        .disabled(isLocked)
        .opacity(isLocked ? 0.4 : 1)
    }

    private func digitButton(_ digit: Int) -> some View {
        Button {
            append(String(digit))
        } label: {
            Text("\(digit)")
                .font(theme.typography.displaySize(30).weight(.regular))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 74, height: 74)
                .background(Circle().fill(theme.plane))
                .overlay(Circle().strokeBorder(theme.border, lineWidth: 1))
        }
        .buttonStyle(PINButtonStyle())
        .accessibilityLabel("\(digit)")
    }

    private var deleteButton: some View {
        Button {
            guard !entered.isEmpty else { return }
            entered.removeLast()
        } label: {
            Image(systemName: "delete.left")
                .font(.title2)
                .foregroundStyle(entered.isEmpty ? theme.textMuted : theme.textPrimary)
                .frame(width: 74, height: 74)
        }
        .buttonStyle(PINButtonStyle())
        .disabled(entered.isEmpty)
        .accessibilityLabel("Delete")
    }

    // MARK: Behavior

    private func append(_ digit: String) {
        guard entered.count < pinLength, !isLocked else { return }
        message = nil
        entered += digit

        guard entered.count == pinLength else { return }

        // Submit on the last digit — no "OK" button. One less tap for a 4-year-old.
        let result = onSubmit(entered)
        handle(result)
    }

    private func handle(_ result: PINVerification) {
        switch result {
        case .success:
            entered = ""
            message = nil
            lockedUntil = nil

        case .incorrect(let remaining):
            fail(message: remaining > 0
                 ? "Wrong PIN — \(remaining) attempt\(remaining == 1 ? "" : "s") left"
                 : "Wrong PIN")

        case .lockedOut(let until):
            lockedUntil = until
            fail(message: nil)

        case .noPINSet:
            entered = ""
            message = nil
        }
    }

    private func fail(message text: String?) {
        withAnimation(.default) {
            message = text
            if !reduceMotion { shake += 1 }
        }
        // Clear the dots after the shake so the user sees what happened.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            entered = ""
        }
    }
}

// MARK: - ShakeEffect

/// Horizontal shake driven by `animatableData`, so it runs as a real animation
/// rather than a chain of dispatched offsets.
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 8
    var shakes: Int

    var animatableData: CGFloat {
        get { CGFloat(shakes) }
        set { shakes = Int(newValue) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = travel * sin(animatableData * .pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - PINButtonStyle

struct PINButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed)
    }
}

// MARK: - PINSetupView

/// Creates or changes a PIN: enter, then confirm.
public struct PINSetupView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let profile: Profile
    private let pinLength: Int
    private let onComplete: (String) -> Void

    @State private var firstEntry: String?
    @State private var errorText: String?

    public init(profile: Profile, pinLength: Int = 4, onComplete: @escaping (String) -> Void) {
        self.profile = profile
        self.pinLength = pinLength
        self.onComplete = onComplete
    }

    public var body: some View {
        PINPadView(
            profile: profile,
            pinLength: pinLength,
            title: firstEntry == nil ? "Choose a PIN" : "Confirm your PIN",
            subtitle: errorText ?? (firstEntry == nil
                ? "Pick \(pinLength) digits that aren't a birthday"
                : "Enter it once more"),
            onCancel: { dismiss() },
            onSubmit: handle
        )
    }

    private func handle(_ pin: String) -> PINVerification {
        guard let first = firstEntry else {
            if PINManager.weakPINs.contains(pin) {
                errorText = "That one's too easy to guess — try another"
                return .incorrect(remainingAttempts: 99)
            }
            firstEntry = pin
            errorText = nil
            return .incorrect(remainingAttempts: 99)
        }

        guard pin == first else {
            firstEntry = nil
            errorText = "Those didn't match. Start again."
            return .incorrect(remainingAttempts: 99)
        }

        onComplete(pin)
        dismiss()
        return .success
    }
}

#Preview("PIN pad") {
    let profile = Profile(name: "Jordan", colorHex: ChartPalette.standard.seriesHex(1), isPINProtected: true)
    var attempts = 0

    return PINPadView(profile: profile, onCancel: {}) { pin in
        attempts += 1
        return pin == "2468" ? .success : .incorrect(remainingAttempts: max(0, 5 - attempts))
    }
}
