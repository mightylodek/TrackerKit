import SwiftUI

/// Plays a tracker's history back as an animation — the chart drawing itself in
/// one period at a time, with the goal line stepping whenever the target changed.
///
/// This is the view that makes goal history legible. A static chart of the last
/// six months shows *where you ended up*; the replay shows the target moving under
/// you, which is usually the more interesting story and the harder one to see.
///
/// Transport is a play/pause button plus a scrubber. It stops at the end rather
/// than looping — a looping chart is a screensaver.
public struct ProgressReplayView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let snapshots: [ProgressSnapshot]
    private let title: String
    private let colorHex: String?
    private let height: CGFloat
    private let autoPlays: Bool

    @State private var frame: Int = 0
    @State private var isPlaying = false
    @State private var timerTask: Task<Void, Never>?

    public init(
        snapshots: [ProgressSnapshot],
        title: String = "Progress over time",
        colorHex: String? = nil,
        height: CGFloat = 220,
        autoPlays: Bool = true
    ) {
        self.snapshots = snapshots
        self.title = title
        self.colorHex = colorHex
        self.height = height
        self.autoPlays = autoPlays
    }

    private var color: Color {
        colorHex.map { Color(hex: $0) } ?? theme.accent
    }

    /// The slice of history visible at the current frame.
    private var visible: [ProgressSnapshot] {
        Array(snapshots.prefix(max(frame, 1)))
    }

    private var currentSnapshot: ProgressSnapshot? {
        visible.last
    }

    /// Whether the goal changed at this exact frame — the moment worth calling out.
    private var goalJustChanged: Bool {
        guard frame >= 2, frame <= snapshots.count else { return false }
        let current = snapshots[frame - 1].goal?.target
        let previous = snapshots[frame - 2].goal?.target
        return current != previous && current != nil && previous != nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshots.count < 2 {
                ChartEmptyState(message: "Not enough history to replay", symbolName: "play.slash")
                    .frame(height: height)
            } else {
                header
                chart
                transport
            }
        }
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentSnapshot?.period.label() ?? title)
                    .font(theme.typography.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .contentTransition(.numericText())

                if let snapshot = currentSnapshot, let target = snapshot.target {
                    HStack(spacing: 4) {
                        Text("Goal at the time:")
                            .font(theme.typography.label)
                            .foregroundStyle(theme.textMuted)
                        Text(Formatters.value(target, unit: snapshot.unit))
                            .font(theme.typography.label.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(goalJustChanged ? theme.statusColor(.yellow) : theme.textSecondary)
                            .contentTransition(.numericText())
                        if goalJustChanged {
                            Text("changed")
                                .font(theme.typography.micro.weight(.bold))
                                .foregroundStyle(theme.statusColor(.yellow))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(theme.statusColor(.yellow).opacity(0.15)))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }

            Spacer()

            if let snapshot = currentSnapshot {
                VStack(alignment: .trailing, spacing: 2) {
                    AnimatedNumber(
                        value: snapshot.actual,
                        unit: snapshot.unit,
                        font: .title2.weight(.bold),
                        color: theme.textPrimary
                    )
                    StoplightBadge(status: snapshot.status, size: .small)
                }
            }
        }
        .animation(theme.motion.snappyAnimation, value: frame)
    }

    // MARK: Chart

    private var chart: some View {
        TrackerPeriodBarChart(
            snapshots: visible,
            colorByStatus: true,
            seriesColorHex: colorHex,
            height: height,
            showAxes: true
        )
        // A fixed domain across the whole replay: rescaling the axis mid-animation
        // would make every frame look identical and the growth invisible.
        .id("replay")
        .animation(reduceMotion ? nil : theme.motion.snappyAnimation, value: frame)
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                isPlaying ? pause() : play()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause replay" : "Play replay")

            Slider(
                value: Binding(
                    get: { Double(frame) },
                    set: { newValue in
                        pause()
                        frame = Int(newValue.rounded())
                    }
                ),
                in: 1...Double(max(snapshots.count, 2)),
                step: 1
            )
            .tint(color)
            .accessibilityLabel("Scrub through history")
            .accessibilityValue(currentSnapshot?.period.label() ?? "")

            Text("\(frame)/\(snapshots.count)")
                .font(theme.typography.label)
                .monospacedDigit()
                .foregroundStyle(theme.textMuted)
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: Playback

    private func start() {
        frame = reduceMotion ? snapshots.count : 1
        guard autoPlays, !reduceMotion, snapshots.count > 1 else { return }
        play()
    }

    private func play() {
        guard snapshots.count > 1 else { return }
        if frame >= snapshots.count { frame = 1 }
        isPlaying = true

        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled, frame < snapshots.count {
                try? await Task.sleep(for: .seconds(theme.motion.replayStepDuration))
                guard !Task.isCancelled, isPlaying else { return }
                withAnimation(theme.motion.snappyAnimation) { frame += 1 }
            }
            isPlaying = false
        }
    }

    private func pause() {
        isPlaying = false
        timerTask?.cancel()
        timerTask = nil
    }

    private func stop() {
        pause()
    }
}

#Preview("Replay") {
    let sample = SampleData.previewTracker(cadence: .weekly, target: 350)
    let history = ProgressEngine().history(
        tracker: sample.tracker, entries: sample.entries, periodCount: 16, cadence: .weekly
    )

    return TrackerCard(title: "Focus Time", subtitle: "Replayed against the goal of the day") {
        ProgressReplayView(
            snapshots: history,
            colorHex: sample.tracker.colorHex
        )
    }
    .padding()
}
