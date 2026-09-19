// iOS-only. These screens assume a phone or tablet canvas: navigation stacks,
// menus, segmented pickers, keyboard types and edit modes that either don't
// exist on watchOS or are the wrong interaction at 45mm.
//
// A watch app gets its own UI built on the same portable core (Model, Engine,
// Store, Theme, Security), not these views shrunk down. See docs/WATCH.md.
#if os(iOS)

import SwiftUI

/// Create or edit a profile, including its PIN.
public struct ProfileEditorView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let store: TrackerStore
    private let session: ProfileSession
    /// `nil` creates a new profile.
    private let existing: Profile?

    @State private var name: String
    @State private var colorHex: String
    @State private var symbolName: String
    @State private var role: ProfileRole
    @State private var wantsPIN: Bool
    @State private var isSettingPIN = false
    @State private var showDeleteConfirmation = false
    @State private var showPINResetConfirmation = false

    /// Only an owner grants ownership.
    ///
    /// An unconditional picker let a member promote themselves, which would hand
    /// them every other profile's data and the PIN reset button along with it.
    private var canChangeRole: Bool {
        // The first profile on a fresh device becomes the owner on save; there is
        // nobody signed in yet to authorise it.
        guard session.isActive else { return true }
        return session.activeProfileIsOwner
    }

    /// What the signed-in profile is allowed to do to *this* one.
    private var authority: PINAuthority {
        // A profile being created has no holder yet, so its creator sets its PIN.
        guard let existing else { return .selfService }
        return session.authority(over: existing)
    }

    public init(store: TrackerStore, session: ProfileSession, profile: Profile?) {
        self.store = store
        self.session = session
        self.existing = profile

        let palette = ChartPalette.standard
        _name = State(initialValue: profile?.name ?? "")
        _colorHex = State(initialValue: profile?.colorHex ?? palette.seriesHex(store.profiles.count))
        _symbolName = State(initialValue: profile?.symbolName ?? "person.fill")
        _role = State(initialValue: profile?.role ?? .member)
        _wantsPIN = State(initialValue: profile?.isPINProtected ?? false)
    }

    private var isNew: Bool { existing == nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ProfileAvatar(profile: previewProfile, size: 88)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    TextField("Name", text: $name)
                        .accessibilityIdentifier("profile.name")
                        .textInputAutocapitalization(.words)
                }

                Section("Color") {
                    ColorSwatchPicker(selection: $colorHex)
                }

                Section("Icon") {
                    SymbolPicker(selection: $symbolName, symbols: Self.profileSymbols)
                }

                Section {
                    if canChangeRole {
                        Picker("Role", selection: $role) {
                            ForEach(ProfileRole.allCases, id: \.self) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                    } else {
                        LabeledContent("Role", value: role.displayName)
                    }
                } footer: {
                    Text(canChangeRole
                         ? "Owners can see every profile's data, change export settings, and reset a forgotten PIN. Members only see their own."
                         : "Only an owner can change a role.")
                }

                Section {
                    switch authority {
                    case .selfService:
                        Toggle("Require a PIN", isOn: $wantsPIN)

                        if wantsPIN {
                            Button(hasPIN ? "Change PIN" : "Set PIN") {
                                isSettingPIN = true
                            }
                            .disabled(isNew && !canSave)
                            .accessibilityIdentifier("profile.setPIN")
                        }

                    case .owner:
                        // An owner restores access without ever learning the
                        // code: clear it, and let its holder choose a new one.
                        // Nothing here can read or set someone else's PIN.
                        if hasPIN {
                            Button("Reset PIN", role: .destructive) {
                                showPINResetConfirmation = true
                            }
                            .accessibilityIdentifier("profile.resetPIN")
                        } else {
                            Text("No PIN set.")
                                .foregroundStyle(theme.textSecondary)
                        }

                    case .none:
                        Text("Only \(existing?.name ?? "this profile") can change this PIN.")
                            .foregroundStyle(theme.textSecondary)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    switch authority {
                    case .owner:
                        Text("As the device owner you can clear this PIN so \(existing?.name ?? "they") can set a new one. You can't see the current one.")
                    case .none:
                        Text("Ask an owner to reset it if it's been forgotten.")
                    case .selfService:
                        Text("A 4-digit PIN keeps other people on this device out of this profile. It's a gate for a shared iPad, not encryption — don't store anything here you'd need protected from someone determined.")
                    }
                }

                if let existing, !isNew {
                    Section {
                        Button("Delete profile", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    } footer: {
                        Text("Deletes \(existing.name) and every tracker, entry and goal underneath. This cannot be undone.")
                    }
                }
            }
            .confirmationDialog(
                "Reset this PIN?",
                isPresented: $showPINResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset PIN", role: .destructive) {
                    if let existing {
                        session.resetPIN(for: existing)
                        wantsPIN = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(existing?.name ?? "This profile") will open without a PIN until a new one is set. Nothing else is removed.")
            }
            .navigationTitle(isNew ? "New profile" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("profile.save")
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isSettingPIN) {
                if let profile = savedProfileForPIN() {
                    PINSetupView(profile: profile) { pin in
                        try? session.setPIN(pin, for: profile)
                        wantsPIN = true
                    }
                }
            }
            .confirmationDialog(
                "Delete \(existing?.name ?? "profile")?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    if let existing {
                        store.deleteProfile(existing.id)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every tracker, entry and goal for this profile is removed. There is no undo.")
            }
        }
    }

    private var previewProfile: Profile {
        Profile(
            id: existing?.id ?? UUID(),
            name: name.isEmpty ? "New" : name,
            colorHex: colorHex,
            symbolName: symbolName,
            role: role,
            isPINProtected: wantsPIN
        )
    }

    private var hasPIN: Bool {
        guard let existing else { return false }
        return session.hasPIN(for: existing.id)
    }

    /// The PIN sheet needs a persisted profile to attach to; save a new one first.
    private func savedProfileForPIN() -> Profile? {
        if let existing { return existing }
        return store.profiles.first { $0.name == name.trimmingCharacters(in: .whitespaces) }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if var profile = existing {
            profile.name = trimmed
            profile.colorHex = colorHex
            profile.symbolName = symbolName
            profile.role = role
            profile.isPINProtected = wantsPIN
            store.update(profile)

            if !wantsPIN {
                session.removePIN(for: profile)
            }
        } else {
            let created = store.addProfile(
                name: trimmed,
                colorHex: colorHex,
                symbolName: symbolName,
                role: role
            )
            if wantsPIN {
                // Nudge straight into PIN setup rather than leaving a profile
                // marked protected with no PIN behind it.
                isSettingPIN = true
                _ = created
                return
            }
            // The very first profile has no picking to do. Dropping the user
            // back to a grid of one and asking them to tap it is a step that
            // exists only because the screen behind the sheet happens to be a
            // picker — select it and let the first run continue.
            if store.profiles.count == 1 {
                session.select(created)
            }
        }
        dismiss()
    }

    static let profileSymbols = [
        "person.fill", "figure.run", "figure.basketball", "figure.soccer",
        "star.fill", "bolt.fill", "leaf.fill", "pawprint.fill",
        "gamecontroller.fill", "music.note", "book.fill", "paintbrush.fill"
    ]
}

// MARK: - ColorSwatchPicker

/// Picks from the categorical palette rather than a full color wheel.
///
/// Constraining the choice is the point: every profile and tracker color comes
/// from the validated set, so two people never end up with colors nobody can tell
/// apart, and the charts stay readable no matter what gets picked.
public struct ColorSwatchPicker: View {
    @Environment(\.trackerTheme) private var theme
    @Binding var selection: String

    public init(selection: Binding<String>) {
        self._selection = selection
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 12)], spacing: 12) {
            ForEach(Array(theme.palette.categorical.enumerated()), id: \.offset) { index, pair in
                let hex = pair.light
                Button {
                    selection = hex
                } label: {
                    Circle()
                        .fill(pair.color)
                        .frame(width: 38, height: 38)
                        .overlay {
                            if selection.caseInsensitiveCompare(hex) == .orderedSame {
                                Circle()
                                    .strokeBorder(theme.textPrimary, lineWidth: 2.5)
                                    .padding(-4)
                            }
                        }
                        .overlay {
                            if selection.caseInsensitiveCompare(hex) == .orderedSame {
                                Image(systemName: "checkmark")
                                    .font(theme.typography.label.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(index + 1)")
                .accessibilityAddTraits(
                    selection.caseInsensitiveCompare(hex) == .orderedSame ? .isSelected : []
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - SymbolPicker

public struct SymbolPicker: View {
    @Environment(\.trackerTheme) private var theme
    @Binding var selection: String
    let symbols: [String]

    public init(selection: Binding<String>, symbols: [String]) {
        self._selection = selection
        self.symbols = symbols
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
            ForEach(symbols, id: \.self) { symbol in
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(selection == symbol ? theme.surface : theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selection == symbol ? theme.textPrimary : theme.plane)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
            }
        }
        .padding(.vertical, 4)
    }
}

#endif
