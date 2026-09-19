// iOS-only: this helper renders the phone screens through UIHostingController
// and UIWindow, neither of which exists on watchOS. The screens it captures are
// iOS-only too.
#if os(iOS)

import Testing
import SwiftUI
import SwiftData
import UIKit
import Foundation
@testable import TrackerKit

/// Renders a visual catalog of every screen to PNGs.
///
/// Not a test — a generator. Off unless `TRACKERKIT_CATALOG` is set, so normal
/// runs stay fast:
///
/// ```bash
/// TRACKERKIT_CATALOG=1 xcodebuild -scheme TrackerKit \
///   -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
/// ```
///
/// Output lands in the simulator's temporary directory; the path is printed at
/// the end of the run.
@MainActor
struct ScreenshotCatalog {

    nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TRACKERKIT_CATALOG"] != nil
    }

    private static let phone = CGSize(width: 402, height: 874)

    private func outputDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trackerkit-catalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Renders through a real `UIWindow` rather than `ImageRenderer`.
    ///
    /// `ImageRenderer` cannot draw a `NavigationStack` — it substitutes SwiftUI's
    /// yellow "unsupported view" placeholder, which is easy to miss when you're
    /// only checking that a file was written. Hosting the view in a window and
    /// drawing the hierarchy renders navigation chrome, scroll content and all.
    @discardableResult
    private func capture(
        _ name: String,
        size: CGSize = phone,
        scale: CGFloat = 2,
        colorScheme: ColorScheme = .light,
        theme: TrackerTheme = .standard,
        settleTime: TimeInterval = 0.45,
        @ViewBuilder content: () -> some View
    ) -> Bool {
        let controller = UIHostingController(
            rootView: AnyView(content().trackerTheme(theme.with { $0.motion.animatesOnAppear = false }))
        )
        controller.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        // SwiftUI commits asynchronously; charts and animated fills need a beat
        // before the hierarchy is worth drawing.
        RunLoop.current.run(until: Date().addingTimeInterval(settleTime))

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }

        window.isHidden = true

        guard let data = image.pngData(), let directory = try? outputDirectory() else {
            return false
        }
        try? data.write(to: directory.appendingPathComponent("\(name).png"))
        return true
    }

    @Test(.enabled(if: ScreenshotCatalog.isEnabled))
    func generateCatalog() throws {
        let store = TrackerStore.preview()
        let session = ProfileSession(store: store)
        let profile = try #require(store.profiles.first)
        session.select(profile)

        let tracker = try #require(
            store.activeTrackers.first { $0.goalHistory.count > 1 } ?? store.activeTrackers.first
        )

        // Screens
        capture("01-profile-gate") {
            ProfileGateView(store: store, session: ProfileSession(store: store)) { EmptyView() }
        }

        capture("02-pin-pad") {
            ZStack {
                ChartPalette.standard.chrome.plane.color
                PINPadView(
                    profile: Profile(
                        name: "Jordan",
                        colorHex: ChartPalette.standard.seriesHex(1),
                        isPINProtected: true
                    ),
                    onCancel: {},
                    onSubmit: { _ in .verified(.incorrect(remainingAttempts: 4)) }
                )
            }
        }

        capture("03-dashboard", size: CGSize(width: 402, height: 1500)) {
            NavigationStack { TrackerDashboardView(store: store, session: session) }
        }

        capture("04-tracker-detail", size: CGSize(width: 402, height: 1700)) {
            NavigationStack {
                TrackerDetailView(tracker: tracker, store: store, session: session)
            }
        }

        capture("05-goal-history", size: CGSize(width: 402, height: 1500)) {
            NavigationStack { GoalHistoryView(tracker: tracker, store: store) }
        }

        capture("06-log-entry", size: CGSize(width: 402, height: 1100)) {
            LogEntryView(
                tracker: store.activeTrackers.first { $0.kind == .count } ?? tracker,
                store: store
            )
        }

        capture("07-tracker-editor", size: CGSize(width: 402, height: 1300)) {
            TrackerEditorView(store: store, tracker: tracker)
        }

        capture("08-export-settings", size: CGSize(width: 402, height: 1100)) {
            NavigationStack { ExportSettingsView(store: store) }
        }

        capture("09-settings") {
            NavigationStack { TrackerKitSettingsView(store: store, session: session) }
        }

        // Gallery sections
        for section in ChartGalleryView.Section.allCases {
            capture(
                "10-gallery-\(section.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))",
                size: CGSize(width: 402, height: 1700)
            ) {
                NavigationStack {
                    ChartGalleryView(store: store, initialSection: section)
                }
            }
        }

        // Widgets on a plate
        capture("11-widgets", size: CGSize(width: 420, height: 880)) {
            let snapshot = store.widgetSnapshot() ?? .placeholder
            return ZStack {
                ChartPalette.standard.chrome.plane.color
                VStack(spacing: 18) {
                    ForEach(TrackerWidgetSize.allCases, id: \.self) { size in
                        WidgetPreviewTile(snapshot: snapshot, size: size)
                    }
                }
                .padding()
            }
        }

        // Report, as delivered
        if let report = store.buildReport(lookbackDays: 7) {
            capture("12-report-page", size: ReportDocumentView.pageSize, scale: 2) {
                ReportDocumentView(
                    report: report,
                    pageIndex: 0,
                    pageCount: ReportDocumentView.pageCount(for: report)
                )
            }
        }

        // Dark mode proof
        capture("13-dashboard-dark", size: CGSize(width: 402, height: 1500), colorScheme: .dark) {
            NavigationStack { TrackerDashboardView(store: store, session: session) }
        }

        capture("14-gallery-dark", size: CGSize(width: 402, height: 1700), colorScheme: .dark) {
            NavigationStack {
                ChartGalleryView(store: store, initialSection: .goals)
            }
        }

        // Theme comparison — the same screens under each preset. This is the
        // rebranding claim, made visible: identical views and data, only tokens
        // differ between these files.
        for (name, preset) in TrackerTheme.presets {
            let slug = name.lowercased()

            capture("20-theme-\(slug)-dashboard", size: CGSize(width: 402, height: 1500), theme: preset) {
                NavigationStack { TrackerDashboardView(store: store, session: session) }
            }
            capture("21-theme-\(slug)-detail", size: CGSize(width: 402, height: 1500), theme: preset) {
                NavigationStack {
                    TrackerDetailView(tracker: tracker, store: store, session: session)
                }
            }
            capture("22-theme-\(slug)-goals", size: CGSize(width: 402, height: 1400), theme: preset) {
                NavigationStack {
                    ChartGalleryView(store: store, initialSection: .goals)
                }
            }
        }

        // Probe: does `glassEffect` survive an offscreen window render at all?
        // If this comes back blank while the solid control renders, the blank
        // theme shots are a harness limitation, not a bug in the views.
        capture("23-glass-probe", size: CGSize(width: 300, height: 220)) {
            ZStack {
                LinearGradient(
                    colors: [.orange, .blue], startPoint: .topLeading, endPoint: .bottomTrailing
                )
                VStack(spacing: 16) {
                    Text("GLASS")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    Text("SOLID")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.white))
                }
            }
        }

        let directory = try outputDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        print("TRACKERKIT_CATALOG_DIR=\(directory.path)")
        print("TRACKERKIT_CATALOG_COUNT=\(files.count)")
        #expect(files.count >= 20)
    }
}

#endif
