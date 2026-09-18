import SwiftUI
import UserNotifications

/// Manage weekly progress exports: when they fire, who they go to, what format.
///
/// The screen is honest about the constraint rather than hiding it — a footer
/// says plainly that iOS will remind you and you tap send. Promising automatic
/// delivery and then silently not delivering is the worse option.
public struct ExportSettingsView: View {
    @Environment(\.trackerTheme) private var theme

    private let store: TrackerStore

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var editingSchedule: ExportSchedule?
    @State private var previewReport: ProgressReport?
    @State private var deliveryRequest: ExportRequest?
    @State private var pendingIdentifiers: [String] = []

    public init(store: TrackerStore) {
        self.store = store
    }

    private var schedules: [ExportSchedule] { store.schedules }

    public var body: some View {
        List {
            statusSection
            schedulesSection
            sendNowSection
            explanationSection
        }
        .navigationTitle("Exports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard let profileID = store.activeProfileID else { return }
                    editingSchedule = ExportSchedule(profileID: profileID)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingSchedule) { schedule in
            ScheduleEditorView(store: store, schedule: schedule)
        }
        .sheet(item: $previewReport) { report in
            NavigationStack {
                ReportPreviewView(report: report)
            }
        }
        .sheet(item: $deliveryRequest) { request in
            if let report = store.buildReport(
                for: request.profileID,
                lookbackDays: request.lookbackDays
            ) {
                ExportDeliveryView(
                    report: report,
                    channel: request.channel,
                    format: request.format,
                    recipients: recipients(for: request)
                ) {
                    if let scheduleID = request.scheduleID {
                        store.markScheduleDelivered(scheduleID)
                    }
                }
            }
        }
        .task { await refreshStatus() }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            switch authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Label("Reminders are on", systemImage: "bell.badge.fill")
                    .foregroundStyle(theme.statusColor(.green))
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Notifications are off", systemImage: "bell.slash.fill")
                        .foregroundStyle(theme.statusColor(.red))
                    Text("Without notifications nothing will remind you to send these. Turn them on in Settings.")
                        .font(theme.typography.label)
                        .foregroundStyle(theme.textSecondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(theme.typography.label.weight(.semibold))
                }
            default:
                Button {
                    Task {
                        await ExportScheduler.requestAuthorization()
                        await refreshStatus()
                    }
                } label: {
                    Label("Allow reminders", systemImage: "bell")
                }
            }
        } header: {
            Text("Notifications")
        }
    }

    private var schedulesSection: some View {
        Section {
            if schedules.isEmpty {
                Text("No scheduled exports yet.")
                    .font(theme.typography.callout)
                    .foregroundStyle(theme.textMuted)
            } else {
                ForEach(schedules) { schedule in
                    Button {
                        editingSchedule = schedule
                    } label: {
                        scheduleRow(schedule)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets {
                        store.deleteSchedule(schedules[index].id)
                    }
                    Task { await refreshPending() }
                }
            }
        } header: {
            Text("Scheduled")
        }
    }

    private func scheduleRow(_ schedule: ExportSchedule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: schedule.channel.symbolName)
                .font(.body)
                .foregroundStyle(schedule.isEnabled ? theme.accent : theme.textMuted)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(
                        (schedule.isEnabled ? theme.accent : theme.textMuted).opacity(0.14)
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.summary)
                    .font(theme.typography.subheadline.weight(.medium))
                    .foregroundStyle(theme.textPrimary)

                Text(subtitle(for: schedule))
                    .font(theme.typography.label)
                    .foregroundStyle(theme.textSecondary)

                if schedule.isEnabled,
                   !pendingIdentifiers.contains(schedule.notificationIdentifier) {
                    Label("Not scheduled with the system yet", systemImage: "exclamationmark.triangle.fill")
                        .font(theme.typography.micro)
                        .foregroundStyle(theme.statusColor(.yellow))
                }
            }

            Spacer()

            if !schedule.isEnabled {
                Text("Off")
                    .font(theme.typography.label.weight(.semibold))
                    .foregroundStyle(theme.textMuted)
            }

            Image(systemName: "chevron.right")
                .font(theme.typography.label.weight(.semibold))
                .foregroundStyle(theme.textMuted)
        }
        .padding(.vertical, 3)
    }

    private func subtitle(for schedule: ExportSchedule) -> String {
        var parts: [String] = [schedule.format.displayName]
        if schedule.recipients.isEmpty {
            parts.append("no recipients yet")
        } else {
            parts.append(schedule.recipients.joined(separator: ", "))
        }
        if let last = schedule.lastDeliveredAt {
            parts.append("last sent \(Formatters.friendlyDay(last).lowercased())")
        }
        return parts.joined(separator: " · ")
    }

    private var sendNowSection: some View {
        Section {
            Button {
                previewReport = store.buildReport(lookbackDays: 7)
            } label: {
                Label("Preview this week's report", systemImage: "doc.text.magnifyingglass")
            }

            Menu {
                ForEach(ReportFormat.allCases, id: \.self) { format in
                    Button(format.displayName) {
                        guard let profileID = store.activeProfileID else { return }
                        deliveryRequest = ExportRequest(
                            profileID: profileID,
                            channel: .shareSheet,
                            format: format,
                            lookbackDays: 7
                        )
                    }
                }
            } label: {
                Label("Send now…", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Right now")
        }
    }

    private var explanationSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("""
            iOS doesn't let any app send email or texts on its own. So on the day and time you pick, this sends you a notification; tapping it opens a message with the report already written and attached, and you hit send.

            That's one tap a week, and nothing can fail quietly in the background.
            """)
        }
    }

    // MARK: Status

    private func refreshStatus() async {
        authorizationStatus = await ExportScheduler.authorizationStatus()
        await refreshPending()
    }

    private func refreshPending() async {
        pendingIdentifiers = await ExportScheduler.pendingExportIdentifiers()
    }

    private func recipients(for request: ExportRequest) -> [String] {
        guard let scheduleID = request.scheduleID else { return [] }
        return schedules.first { $0.id == scheduleID }?.recipients ?? []
    }
}

// MARK: - ScheduleEditorView

/// Edit one export schedule.
public struct ScheduleEditorView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let store: TrackerStore
    private let original: ExportSchedule
    private let isNew: Bool

    @State private var isEnabled: Bool
    @State private var weekday: Int
    @State private var time: Date
    @State private var channel: ExportChannel
    @State private var format: ReportFormat
    @State private var recipientText: String
    @State private var lookbackDays: Int

    public init(store: TrackerStore, schedule: ExportSchedule) {
        self.store = store
        self.original = schedule
        self.isNew = !store.schedules.contains { $0.id == schedule.id }

        _isEnabled = State(initialValue: schedule.isEnabled)
        _weekday = State(initialValue: schedule.weekday)
        _channel = State(initialValue: schedule.channel)
        _format = State(initialValue: schedule.format)
        _recipientText = State(initialValue: schedule.recipients.joined(separator: ", "))
        _lookbackDays = State(initialValue: schedule.lookbackDays)

        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute
        _time = State(initialValue: Calendar.current.date(from: components) ?? .now)
    }

    private var recipients: [String] {
        recipientText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                }

                Section("When") {
                    Picker("Day", selection: $weekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)

                    Picker("Covers", selection: $lookbackDays) {
                        Text("Last 7 days").tag(7)
                        Text("Last 14 days").tag(14)
                        Text("Last 30 days").tag(30)
                    }
                }

                Section("How") {
                    Picker("Channel", selection: $channel) {
                        ForEach(ExportChannel.allCases, id: \.self) { option in
                            Label(option.displayName, systemImage: option.symbolName).tag(option)
                        }
                    }

                    Picker("Format", selection: $format) {
                        ForEach(ReportFormat.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }

                if channel != .shareSheet {
                    Section {
                        TextField(
                            channel == .email ? "name@example.com, coach@example.com" : "555-0100, 555-0142",
                            text: $recipientText,
                            axis: .vertical
                        )
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(channel == .email ? .emailAddress : .phonePad)
                    } header: {
                        Text(channel == .email ? "Send to" : "Text to")
                    } footer: {
                        Text("Separate several with commas. You can also leave this blank and pick recipients when the composer opens.")
                    }
                }

                if let next = ExportScheduler.nextFireDate(
                    for: buildSchedule(),
                    calendar: Calendar.current
                ) {
                    Section {
                        LabeledContent("Next reminder") {
                            Text(next.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New export" : "Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func buildSchedule() -> ExportSchedule {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        var schedule = original
        schedule.isEnabled = isEnabled
        schedule.weekday = weekday
        schedule.hour = components.hour ?? 18
        schedule.minute = components.minute ?? 0
        schedule.channel = channel
        schedule.format = format
        schedule.recipients = recipients
        schedule.lookbackDays = lookbackDays
        return schedule
    }

    private func save() {
        let schedule = buildSchedule()

        if isNew {
            store.addSchedule(schedule)
        } else {
            store.update(schedule)
        }

        let profileName = store.profiles.first { $0.id == schedule.profileID }?.name ?? "Progress"
        Task {
            await ExportScheduler.requestAuthorization()
            try? await ExportScheduler.schedule(schedule, profileName: profileName)
        }
        dismiss()
    }
}

// MARK: - ReportPreviewView

/// Shows the report exactly as it will be delivered, with a share button.
public struct ReportPreviewView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let report: ProgressReport
    @State private var format: ReportFormat = .pdf
    @State private var shareURL: URL?

    public init(report: ProgressReport) {
        self.report = report
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Format", selection: $format) {
                    ForEach(ReportFormat.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch format {
                case .pdf, .html:
                    ForEach(0..<ReportDocumentView.pageCount(for: report), id: \.self) { page in
                        ReportDocumentView(
                            report: report,
                            pageIndex: page,
                            pageCount: ReportDocumentView.pageCount(for: report)
                        )
                        .scaleEffect(0.52, anchor: .top)
                        .frame(
                            width: ReportDocumentView.pageSize.width * 0.52,
                            height: ReportDocumentView.pageSize.height * 0.52
                        )
                        .overlay {
                            Rectangle().strokeBorder(theme.border, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                    }

                case .markdown, .csv:
                    Text(textPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(theme.surface, in: .rect(cornerRadius: 12))
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(theme.plane)
        .navigationTitle("Report preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    shareURL = try? ExportComposer(theme: theme).file(for: report, format: format)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: Binding(
            get: { shareURL.map { IdentifiableURL(url: $0) } },
            set: { shareURL = $0?.url }
        )) { wrapper in
            ShareSheet(items: [wrapper.url])
        }
    }

    private var textPreview: String {
        let data = format == .csv
            ? CSVReportRenderer().render(report)
            : MarkdownReportRenderer().render(report)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Wrapper so a `URL` can drive a `sheet(item:)`.
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Identifiable conformances for sheet(item:)

extension ProgressReport: Identifiable {
    public var id: String { "\(profileID.uuidString)-\(interval.start.timeIntervalSince1970)" }
}

// `Tracker` and `ExportSchedule` already declare `Identifiable` on their own
// definitions; only `ProgressReport` needs one here, since its identity is
// derived rather than stored.
