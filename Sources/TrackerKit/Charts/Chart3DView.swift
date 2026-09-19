// `Chart3D` is iOS/macOS only — there is no watchOS implementation, and a
// rotatable 3-D field would be meaningless at watch size regardless.
#if os(iOS)

import SwiftUI
import Charts

// MARK: - Chart3DData

/// What the third dimension means. A 3-D chart is only worth the depth when the
/// data genuinely has three axes — otherwise it is a 2-D chart wearing a costume,
/// and the perspective actively makes values harder to compare.
public enum Chart3DData: Sendable, Hashable {
    /// Weekday × week × value. The honest use: it exposes *rhythm* — the Tuesday
    /// slump, the weekend cliff — which a flat time series buries.
    case weekdayByWeek(values: [DailyValue], unit: String)
    /// Series × time × value. Several trackers side by side in depth.
    case seriesByTime(series: [ChartSeries])
}

// MARK: - Chart3DStyle

/// Which renderer draws the field.
///
/// This used to be a version fallback. Now that the floor is iOS 26 it is a
/// design choice, which is the better framing anyway — the two renderers say
/// different things about the same numbers.
public enum Chart3DStyle: String, Sendable, CaseIterable, Hashable {
    /// Hand-rolled shaded columns over a ground grid. Reads magnitude the way a
    /// bar chart does, and is the more distinctive of the two.
    case columns
    /// Apple's `Chart3D` point field, with system depth, lighting and gestures.
    /// Better for cloud-shaped data where the *distribution* is the subject.
    case native

    public var displayName: String {
        switch self {
        case .columns: "Columns"
        case .native: "Points"
        }
    }
}

// MARK: - Bar3D

/// One column in the 3-D field, in normalized data space.
struct Bar3D: Identifiable, Hashable {
    let id: String
    /// Column position along the x axis.
    let x: Double
    /// Height — the value.
    let y: Double
    /// Depth position.
    let z: Double
    let rawValue: Double
    let xLabel: String
    let zLabel: String
    let colorIndex: Int
    let colorHex: String?
}

// MARK: - Tracker3DChart

/// A 3-D field, drawn either as shaded columns or as Apple's native point cloud.
///
/// Both styles are drag-to-rotate, because a static 3-D chart is the worst of
/// both worlds — occlusion and foreshortening with no way to resolve either.
/// Rotation is what turns the depth from a liability into information.
///
/// `.columns` is the default and the distinctive one: it reads magnitude the way
/// a bar chart does, and nothing else on the App Store looks quite like it.
/// `.native` hands off to `Chart3D`, which brings system depth and lighting.
///
/// One API note worth keeping: the native path uses `PointMark`, the only 3-D
/// mark that accepts a single (x, y, z). `RectangleMark` publishes the same
/// initializer, compiles against it, and then traps at runtime demanding two
/// extents.
public struct Tracker3DChart: View {
    @Environment(\.trackerTheme) private var theme

    private let data: Chart3DData
    private let height: CGFloat
    private let title: String?
    private let style: Chart3DStyle

    public init(
        data: Chart3DData,
        style: Chart3DStyle = .columns,
        height: CGFloat = 300,
        title: String? = nil
    ) {
        self.data = data
        self.style = style
        self.height = height
        self.title = title
    }

    /// Convenience: weekday-by-week rhythm for a single tracker.
    public init(
        values: [DailyValue],
        unit: String = "",
        style: Chart3DStyle = .columns,
        height: CGFloat = 300
    ) {
        self.init(data: .weekdayByWeek(values: values, unit: unit), style: style, height: height)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if bars.isEmpty {
                ChartEmptyState(message: "Not enough history for a 3-D view", symbolName: "cube")
                    .frame(height: height)
            } else {
                switch style {
                case .native:
                    NativeChart3D(bars: bars, unit: unit, height: height)
                case .columns:
                    ProjectedBarField3D(bars: bars, unit: unit, height: height)
                }
                caption
            }
        }
    }

    private var caption: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
                .font(theme.typography.micro)
            Text("Drag to rotate")
                .font(theme.typography.micro)
        }
        .foregroundStyle(theme.textMuted)
    }

    private var unit: String {
        switch data {
        case .weekdayByWeek(_, let unit): unit
        case .seriesByTime(let series): series.first?.unit ?? ""
        }
    }

    // MARK: Data shaping

    private var bars: [Bar3D] {
        switch data {
        case .weekdayByWeek(let values, _):
            return weekdayBars(values)
        case .seriesByTime(let series):
            return seriesBars(series)
        }
    }

    /// x = weekday, z = week index. Zero-value days are dropped rather than drawn
    /// flat, so the floor of the field reads as "nothing here".
    private func weekdayBars(_ values: [DailyValue]) -> [Bar3D] {
        guard !values.isEmpty else { return [] }
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols

        guard let firstDate = values.first?.date else { return [] }
        let anchor = calendar.dateInterval(of: .weekOfYear, for: firstDate)?.start ?? firstDate

        return values.compactMap { day in
            guard day.value > 0 else { return nil }
            let weekday = calendar.component(.weekday, from: day.date) - 1
            let weekIndex = calendar.dateComponents([.weekOfYear], from: anchor, to: day.date).weekOfYear ?? 0

            return Bar3D(
                id: day.date.description,
                x: Double(weekday),
                y: day.value,
                z: Double(weekIndex),
                rawValue: day.value,
                xLabel: symbols.indices.contains(weekday) ? symbols[weekday] : "",
                zLabel: Formatters.dayMonth(day.date),
                colorIndex: 0,
                colorHex: nil
            )
        }
    }

    /// x = time index, z = series index.
    private func seriesBars(_ series: [ChartSeries]) -> [Bar3D] {
        let capped = series.capped(at: 6)
        let dates = capped.allDates
        var result: [Bar3D] = []

        for (seriesIndex, item) in capped.enumerated() {
            for (dateIndex, date) in dates.enumerated() {
                guard let point = item.points.first(where: { $0.date == date }), point.value > 0 else {
                    continue
                }
                result.append(
                    Bar3D(
                        id: "\(item.id)-\(date.timeIntervalSince1970)",
                        x: Double(dateIndex),
                        y: point.value,
                        z: Double(seriesIndex),
                        rawValue: point.value,
                        xLabel: Formatters.dayMonth(date),
                        zLabel: item.name,
                        colorIndex: item.colorIndex,
                        colorHex: item.colorHex
                    )
                )
            }
        }
        return result
    }
}

// MARK: - Native Chart3D

private struct NativeChart3D: View {
    @Environment(\.trackerTheme) private var theme
    @State private var pose: Chart3DPose = .default

    let bars: [Bar3D]
    let unit: String
    let height: CGFloat

    var body: some View {
        Chart3D(bars) { bar in
            PointMark(
                x: .value("Across", bar.x),
                y: .value("Value", bar.y),
                z: .value("Depth", bar.z)
            )
            .foregroundStyle(color(for: bar))
        }
        .chart3DPose($pose)
        .chart3DCameraProjection(.perspective)
        .frame(height: height)
    }

    private func color(for bar: Bar3D) -> Color {
        if let hex = bar.colorHex { return Color(hex: hex) }
        return theme.palette.series(bar.colorIndex)
    }
}

// MARK: - Projected column field

/// A hand-rolled 3-D bar field.
///
/// Rotates the data by yaw and pitch, projects to 2-D, then paints back to front.
/// Each column gets a top face and two side faces at different brightnesses so the
/// solid reads as a solid — the shading *is* the depth cue, with no lighting model
/// behind it.
private struct ProjectedBarField3D: View {
    @Environment(\.trackerTheme) private var theme

    let bars: [Bar3D]
    let unit: String
    let height: CGFloat

    @State private var yaw: Double = 0.62
    @State private var pitch: Double = 0.52
    @GestureState private var dragOffset: CGSize = .zero

    private var currentYaw: Double { yaw + dragOffset.width * 0.01 }
    private var currentPitch: Double {
        min(max(pitch - dragOffset.height * 0.006, 0.12), 1.35)
    }

    private var maxValue: Double { max(bars.map(\.y).max() ?? 1, 0.0001) }
    private var maxX: Double { max(bars.map(\.x).max() ?? 1, 1) }
    private var maxZ: Double { max(bars.map(\.z).max() ?? 1, 1) }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                draw(context: context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        yaw += value.translation.width * 0.01
                        pitch = min(max(pitch - value.translation.height * 0.006, 0.12), 1.35)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Three dimensional bar field, \(bars.count) columns. Drag to rotate.")
        }
        .frame(height: height)
    }

    // MARK: Projection

    /// Rotate around the vertical axis by `yaw`, tilt by `pitch`, project.
    /// Returns the screen point plus a depth value for painter ordering.
    private func project(x: Double, y: Double, z: Double) -> (point: CGPoint, depth: Double) {
        let cx = x - maxX / 2
        let cz = z - maxZ / 2

        let rotatedX = cx * cos(currentYaw) - cz * sin(currentYaw)
        let depth = cx * sin(currentYaw) + cz * cos(currentYaw)

        let screenX = rotatedX
        let screenY = -y * cos(currentPitch) + depth * sin(currentPitch)

        return (CGPoint(x: screenX, y: screenY), depth)
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        guard !bars.isEmpty else { return }

        // Uniform scale that keeps the whole field inside the canvas whatever the
        // rotation, computed from the projected extents of the bounding box.
        var minX = Double.infinity, maxScreenX = -Double.infinity
        var minY = Double.infinity, maxScreenY = -Double.infinity

        for cornerX in [0.0, maxX] {
            for cornerZ in [0.0, maxZ] {
                for cornerY in [0.0, maxValue] {
                    let projected = project(x: cornerX, y: cornerY / maxValue * (maxX + maxZ) / 2.2, z: cornerZ)
                    minX = min(minX, projected.point.x)
                    maxScreenX = max(maxScreenX, projected.point.x)
                    minY = min(minY, projected.point.y)
                    maxScreenY = max(maxScreenY, projected.point.y)
                }
            }
        }

        let spanX = max(maxScreenX - minX, 0.0001)
        let spanY = max(maxScreenY - minY, 0.0001)
        let scale = min(size.width * 0.86 / spanX, size.height * 0.86 / spanY)
        let offsetX = size.width / 2 - CGFloat((minX + maxScreenX) / 2) * scale
        let offsetY = size.height / 2 - CGFloat((minY + maxScreenY) / 2) * scale

        func toScreen(_ point: CGPoint) -> CGPoint {
            CGPoint(x: CGFloat(point.x) * scale + offsetX, y: CGFloat(point.y) * scale + offsetY)
        }

        // Height normalization: tallest bar occupies a sensible share of the field.
        let heightScale = (maxX + maxZ) / 2.2 / maxValue
        let barHalfWidth = 0.34

        drawFloor(context: context, toScreen: toScreen)

        // Painter's algorithm — farthest first.
        let ordered = bars.sorted {
            project(x: $0.x, y: 0, z: $0.z).depth < project(x: $1.x, y: 0, z: $1.z).depth
        }

        for bar in ordered {
            let color = bar.colorHex.map { Color(hex: $0) } ?? theme.palette.series(bar.colorIndex)
            let top = bar.y * heightScale

            // Eight corners of the column.
            let corners: [(Double, Double)] = [
                (-barHalfWidth, -barHalfWidth),
                (barHalfWidth, -barHalfWidth),
                (barHalfWidth, barHalfWidth),
                (-barHalfWidth, barHalfWidth)
            ]

            let base = corners.map { project(x: bar.x + $0.0, y: 0, z: bar.z + $0.1) }
            let cap = corners.map { project(x: bar.x + $0.0, y: top, z: bar.z + $0.1) }

            // Side faces, drawn back to front within the column.
            let sideOrder = (0..<4).sorted {
                (base[$0].depth + base[($0 + 1) % 4].depth) < (base[$1].depth + base[($1 + 1) % 4].depth)
            }

            for index in sideOrder {
                let next = (index + 1) % 4
                var path = Path()
                path.move(to: toScreen(base[index].point))
                path.addLine(to: toScreen(base[next].point))
                path.addLine(to: toScreen(cap[next].point))
                path.addLine(to: toScreen(cap[index].point))
                path.closeSubpath()

                // Two brightness steps — one for each visible pair of faces.
                let shade = index % 2 == 0 ? 0.78 : 0.62
                context.fill(path, with: .color(color.opacity(shade)))
            }

            // Top face, brightest.
            var capPath = Path()
            capPath.move(to: toScreen(cap[0].point))
            for index in 1..<4 { capPath.addLine(to: toScreen(cap[index].point)) }
            capPath.closeSubpath()
            context.fill(capPath, with: .color(color))
            context.stroke(capPath, with: .color(theme.surface.opacity(0.5)), lineWidth: 0.5)
        }
    }

    /// A ground grid so the columns have something to stand on — without it the
    /// bars float and the rotation is impossible to read.
    private func drawFloor(context: GraphicsContext, toScreen: (CGPoint) -> CGPoint) {
        var grid = Path()

        for x in stride(from: 0.0, through: maxX + 0.5, by: 1) {
            grid.move(to: toScreen(project(x: x - 0.5, y: 0, z: -0.5).point))
            grid.addLine(to: toScreen(project(x: x - 0.5, y: 0, z: maxZ + 0.5).point))
        }
        for z in stride(from: 0.0, through: maxZ + 0.5, by: 1) {
            grid.move(to: toScreen(project(x: -0.5, y: 0, z: z - 0.5).point))
            grid.addLine(to: toScreen(project(x: maxX + 0.5, y: 0, z: z - 0.5).point))
        }

        context.stroke(grid, with: .color(theme.gridline.opacity(0.75)), lineWidth: 0.5)
    }
}

#Preview("3D field") {
    let sample = SampleData.previewTracker()
    let values = ProgressEngine().dailyValues(
        tracker: sample.tracker, entries: sample.entries, dayCount: 56
    )

    return TrackerCard(title: "Rhythm", subtitle: "Weekday across weeks") {
        Tracker3DChart(values: values, unit: "min", height: 320)
    }
    .padding()
}

#endif
