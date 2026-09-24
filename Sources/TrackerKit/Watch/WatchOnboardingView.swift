// watchOS-only. See rule 17 in CLAUDE.md.
#if os(watchOS)

import SwiftUI

// MARK: - WatchOnboardingView

/// Setting up the first habits, with no keyboard.
///
/// The phone's wizard asks for a name, a goal, a cadence and a unit. None of
/// that is reasonable at 45mm, and a child setting up their own watch has no
/// phone to do it on — so the templates built for the phone do the typing. Pick
/// "Youth sport", get four habits with sensible goals and increments, type
/// nothing.
public struct WatchOnboardingView: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore

    @State private var chosen: TrackerTemplate?

    public init(store: TrackerStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            if let chosen {
                WatchTemplateDetail(template: chosen, store: store) {
                    self.chosen = nil
                }
            } else {
                templateList
            }
        }
    }

    private var templateList: some View {
        List {
            Section {
                ForEach(TrackerTemplate.all.filter { !$0.blueprints.isEmpty }) { template in
                    Button {
                        chosen = template
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Label(template.name, systemImage: template.symbolName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Text(template.blueprints.map(\.title).joined(separator: " · "))
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .accessibilityIdentifier("watch.template.\(template.id)")
                }
            } header: {
                Text("What are you tracking?")
            }
        }
        .navigationTitle("Set up")
    }
}

// MARK: - WatchTemplateDetail

/// Confirming a template, with the chance to drop anything unwanted.
struct WatchTemplateDetail: View {
    @Environment(\.trackerTheme) private var theme

    let template: TrackerTemplate
    let store: TrackerStore
    let onBack: () -> Void

    @State private var selected: Set<UUID>

    init(template: TrackerTemplate, store: TrackerStore, onBack: @escaping () -> Void) {
        self.template = template
        self.store = store
        self.onBack = onBack
        _selected = State(initialValue: Set(
            template.blueprints.filter(\.isRecommended).map(\.id)
        ))
    }

    private var chosen: [TrackerBlueprint] {
        template.blueprints.filter { selected.contains($0.id) }
    }

    var body: some View {
        List {
            ForEach(template.blueprints) { blueprint in
                Button {
                    if selected.contains(blueprint.id) {
                        selected.remove(blueprint.id)
                    } else {
                        selected.insert(blueprint.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selected.contains(blueprint.id)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(blueprint.id)
                                             ? theme.accent : theme.textMuted)
                        Text(blueprint.title)
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textPrimary)
                    }
                }
                .accessibilityIdentifier("watch.blueprint.\(blueprint.title)")
            }

            Button {
                store.apply(template, selecting: chosen)
            } label: {
                Text(chosen.isEmpty
                     ? "Pick at least one"
                     : "Start tracking \(chosen.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(chosen.isEmpty)
            .accessibilityIdentifier("watch.startTracking")

            Button("Back", action: onBack)
                .font(.system(size: 13))
        }
        .navigationTitle(template.name)
    }
}

#endif
