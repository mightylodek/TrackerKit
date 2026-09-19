// iOS-only. These screens assume a phone or tablet canvas: navigation stacks,
// menus, segmented pickers, keyboard types and edit modes that either don't
// exist on watchOS or are the wrong interaction at 45mm.
//
// A watch app gets its own UI built on the same portable core (Model, Engine,
// Store, Theme, Security), not these views shrunk down. See docs/WATCH.md.
#if os(iOS)

import SwiftUI

/// Sets up a profile: pick a starting point, choose what to track, done.
///
/// Two steps, and the second is a list of tick boxes. Onboarding that asks a lot
/// of questions before showing anything working is how people decide an app is
/// a chore — so this suggests a sensible default, lets it be edited in one
/// screen, and gets out of the way. Everything stays editable afterwards.
public struct OnboardingView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let store: TrackerStore
    private let onFinish: () -> Void

    @State private var template: TrackerTemplate?
    @State private var selected: Set<UUID> = []

    public init(store: TrackerStore, onFinish: @escaping () -> Void = {}) {
        self.store = store
        self.onFinish = onFinish
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let template {
                    chooseTrackers(in: template)
                } else {
                    chooseTemplate
                }
            }
            .background(theme.plane)
            .navigationTitle(template == nil ? "What are you tracking?" : template!.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if template != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            withAnimation(theme.motion.snappyAnimation) { template = nil }
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") { finish(with: nil) }
                            .accessibilityIdentifier("onboarding.skip")
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Step one

    private var chooseTemplate: some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                Text("Pick a starting point. You can change everything later.")
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, theme.spacing.xs)

                ForEach(TrackerTemplate.all) { option in
                    Button {
                        withAnimation(theme.motion.snappyAnimation) {
                            template = option
                            selected = Set(option.recommended.map(\.id))
                        }
                    } label: {
                        templateRow(option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("template.\(option.id)")
                }
            }
            .padding(theme.spacing.screenMargin)
        }
    }

    private func templateRow(_ option: TrackerTemplate) -> some View {
        TrackerCard {
            HStack(spacing: theme.spacing.md) {
                Image(systemName: option.symbolName)
                    .font(.title2)
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.accent.opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.name)
                        .font(theme.typography.heading)
                        .foregroundStyle(theme.textPrimary)
                    Text(option.summary)
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.leading)

                    if !option.blueprints.isEmpty {
                        Text(option.recommended.map(\.title).joined(separator: " · "))
                            .font(theme.typography.micro)
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    // MARK: Step two

    private func chooseTrackers(in template: TrackerTemplate) -> some View {
        VStack(spacing: 0) {
            if template.blueprints.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to set up", systemImage: "square.dashed")
                } description: {
                    Text("You'll start with an empty dashboard and add trackers yourself.")
                }
            } else {
                List {
                    Section {
                        ForEach(template.blueprints) { blueprint in
                            row(blueprint)
                        }
                    } header: {
                        Text("Tick what you want to track")
                    } footer: {
                        Text("Targets and how much one tap adds are suggestions — all editable once you're in.")
                    }
                }
            }

            confirmButton(for: template)
                .padding(theme.spacing.screenMargin)
        }
    }

    private func row(_ blueprint: TrackerBlueprint) -> some View {
        Button {
            if selected.contains(blueprint.id) {
                selected.remove(blueprint.id)
            } else {
                selected.insert(blueprint.id)
            }
        } label: {
            HStack(spacing: theme.spacing.md) {
                Image(systemName: selected.contains(blueprint.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected.contains(blueprint.id) ? theme.accent : theme.axis)

                Image(systemName: blueprint.symbolName)
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(blueprint.title)
                        .font(theme.typography.heading)
                        .foregroundStyle(theme.textPrimary)
                    Text(blueprint.goalSummary)
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("blueprint.\(blueprint.title)")
    }

    private func confirmButton(for template: TrackerTemplate) -> some View {
        let chosen = template.blueprints.filter { selected.contains($0.id) }

        return Button {
            finish(with: template, chosen: chosen)
        } label: {
            Text(chosen.isEmpty ? "Start with an empty dashboard" : "Set up \(chosen.count) tracker\(chosen.count == 1 ? "" : "s")")
                .font(theme.typography.heading)
                .foregroundStyle(theme.inkOnControl(isProminent: true))
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.spacing.md)
        }
        .buttonStyle(TrackerControlButtonStyle())
        .trackerControlSurface(shape: theme.radii.actionShape, isProminent: true)
        .accessibilityIdentifier("onboarding.confirm")
    }

    private func finish(with template: TrackerTemplate?, chosen: [TrackerBlueprint] = []) {
        if let template, !chosen.isEmpty {
            store.apply(template, selecting: chosen)
        }
        onFinish()
        dismiss()
    }
}

#endif
