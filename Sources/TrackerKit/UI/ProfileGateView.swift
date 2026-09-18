import SwiftUI

/// The front door: pick a profile, prove it if it's locked, then hand off to the app.
///
/// Designed for a device on a kitchen counter with several kids using it. Tiles
/// are large, each carries its owner's color and a lock glyph when protected, and
/// nothing about one profile's data is visible before unlocking it — the tile
/// shows a streak only for unprotected profiles, because a PIN that still leaks
/// activity isn't much of a PIN.
public struct ProfileGateView<Content: View>: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore
    private let session: ProfileSession
    private let content: () -> Content
    private let allowsProfileCreation: Bool

    @State private var isAddingProfile = false

    public init(
        store: TrackerStore,
        session: ProfileSession,
        allowsProfileCreation: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.store = store
        self.session = session
        self.allowsProfileCreation = allowsProfileCreation
        self.content = content
    }

    public var body: some View {
        Group {
            switch session.state {
            case .active:
                content()
                    .transition(.opacity)

            case .authenticating:
                if let profile = session.pendingProfile {
                    pinScreen(for: profile)
                } else {
                    picker
                }

            case .choosing:
                picker
            }
        }
        .animation(theme.motion.snappyAnimation, value: session.isActive)
        .sheet(isPresented: $isAddingProfile) {
            ProfileEditorView(store: store, session: session, profile: nil)
        }
    }

    // MARK: Picker

    private var picker: some View {
        if store.profiles.isEmpty {
            return AnyView(welcome)
        }
        return AnyView(profileGrid)
    }

    /// The true first screen of the app.
    ///
    /// The picker's own copy ("pick up where you left off") is addressed to
    /// someone who has been here before, and a grid holding nothing but an Add
    /// tile reads as a screen that failed to load rather than one waiting on a
    /// first step.
    private var welcome: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer(minLength: 0)

            Image(systemName: "target")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(theme.accent)

            VStack(spacing: theme.spacing.sm) {
                Text("Track what matters")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                Text("Set up a profile to get started. Everyone sharing this device gets their own.")
                    .font(theme.typography.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if allowsProfileCreation {
                Button("Create a profile") { isAddingProfile = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(theme.accent)
                    // `.borderedProminent` picks its own white label, which on a
                    // bright accent lands near 2:1. The theme already carries the
                    // ink meant to sit on the accent.
                    .foregroundStyle(theme.onAccent)
                    .accessibilityIdentifier("welcome.createProfile")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.plane)
    }

    private var profileGrid: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text("Who's tracking?")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Pick a profile to pick up where you left off.")
                        .font(theme.typography.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.top, 40)
                .multilineTextAlignment(.center)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                        ProfileTile(
                            profile: profile,
                            streak: profile.isPINProtected ? nil : store.loginStreak(for: profile.id)
                        ) {
                            withAnimation(theme.motion.snappyAnimation) {
                                session.select(profile)
                            }
                        }
                        .staggeredAppear(index: index)
                    }

                    if allowsProfileCreation {
                        AddProfileTile { isAddingProfile = true }
                            .staggeredAppear(index: store.profiles.count)
                    }
                }
                .padding(.horizontal, 24)

                if store.profiles.isEmpty {
                    Text("No profiles yet — add the first one to get started.")
                        .font(theme.typography.callout)
                        .foregroundStyle(theme.textMuted)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 40)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(theme.plane)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 20)]
    }

    // MARK: PIN

    private func pinScreen(for profile: Profile) -> some View {
        VStack {
            Spacer(minLength: 0)
            PINPadView(
                profile: profile,
                onCancel: { session.cancelAuthentication() },
                onSubmit: { session.submit(pin: $0) }
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.plane)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - ProfileTile

/// One profile in the picker.
public struct ProfileTile: View {
    @Environment(\.trackerTheme) private var theme

    private let profile: Profile
    private let streak: StreakSummary?
    private let action: () -> Void

    public init(profile: Profile, streak: StreakSummary?, action: @escaping () -> Void) {
        self.profile = profile
        self.streak = streak
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatar(profile: profile, size: 92)

                    if profile.isPINProtected {
                        Image(systemName: "lock.fill")
                            .font(theme.typography.label.weight(.bold))
                            .foregroundStyle(theme.textPrimary)
                            .padding(7)
                            .background(Circle().fill(theme.surface))
                            .overlay(Circle().strokeBorder(theme.border, lineWidth: 1))
                            .offset(x: 3, y: 3)
                    }
                }

                VStack(spacing: 3) {
                    Text(profile.name)
                        .font(theme.typography.heading)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    if let streak, streak.current > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(theme.typography.micro)
                            Text("\(streak.current)")
                                .font(theme.typography.label.weight(.semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(theme.identityColor(for: profile))
                    } else if profile.isPINProtected {
                        Text("Locked")
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textMuted)
                    } else {
                        Text(profile.role.displayName)
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(theme.surface, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(ProfileTileButtonStyle())
        .accessibilityLabel(
            "\(profile.name)\(profile.isPINProtected ? ", PIN protected" : "")"
        )
    }
}

// MARK: - AddProfileTile

public struct AddProfileTile: View {
    @Environment(\.trackerTheme) private var theme
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(theme.typography.display(.title))
                    .foregroundStyle(theme.textMuted)
                    .frame(width: 92, height: 92)
                    .background {
                        Circle().strokeBorder(
                            theme.axis,
                            style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                        )
                    }

                Text("Add profile")
                    .font(theme.typography.heading)
                    .foregroundStyle(theme.textSecondary)
                Text(" ")
                    .font(theme.typography.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(theme.surface.opacity(0.5), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(ProfileTileButtonStyle())
    }
}

struct ProfileTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview("Profile gate") {
    let store = TrackerStore.preview()
    let session = ProfileSession(store: store)
    store.activeProfileID = nil

    return ProfileGateView(store: store, session: session) {
        Text("Signed in")
    }
}
