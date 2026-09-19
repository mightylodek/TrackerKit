// Mail and SMS composers are UIKit view controllers with no watchOS equivalent:
// watchOS has no Mail or Messages app to hand a draft to. The whole file is
// conditionalised rather than stubbed, so a watch target that tries to present a
// composer fails to compile instead of silently doing nothing at runtime.
//
// The watch's export route is an open design question — see docs/WATCH.md.
#if canImport(MessageUI)

import SwiftUI
import UIKit
import MessageUI

// MARK: - MailComposeView

/// `MFMailComposeViewController` as a SwiftUI sheet.
///
/// Check ``MailComposeView/canSendMail`` before presenting — on a device with no
/// mail account configured the controller presents and then immediately fails,
/// which reads to the user as the app being broken.
public struct MailComposeView: UIViewControllerRepresentable {

    public static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    private let recipients: [String]
    private let subject: String
    private let body: String
    private let isBodyHTML: Bool
    private let attachments: [Attachment]
    private let onFinish: (Result) -> Void

    public struct Attachment {
        public let data: Data
        public let mimeType: String
        public let fileName: String

        public init(data: Data, mimeType: String, fileName: String) {
            self.data = data
            self.mimeType = mimeType
            self.fileName = fileName
        }

        /// Builds an attachment from a file the composer wrote.
        public init?(url: URL, mimeType: String) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            self.init(data: data, mimeType: mimeType, fileName: url.lastPathComponent)
        }
    }

    public enum Result: Sendable {
        case sent
        case saved
        case cancelled
        case failed(String)
    }

    public init(
        recipients: [String],
        subject: String,
        body: String,
        isBodyHTML: Bool = false,
        attachments: [Attachment] = [],
        onFinish: @escaping (Result) -> Void
    ) {
        self.recipients = recipients
        self.subject = subject
        self.body = body
        self.isBodyHTML = isBodyHTML
        self.attachments = attachments
        self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients.isEmpty ? nil : recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: isBodyHTML)

        for attachment in attachments {
            controller.addAttachmentData(
                attachment.data,
                mimeType: attachment.mimeType,
                fileName: attachment.fileName
            )
        }
        return controller
    }

    public func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    public final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (Result) -> Void

        init(onFinish: @escaping (Result) -> Void) {
            self.onFinish = onFinish
        }

        public func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)

            if let error {
                onFinish(.failed(error.localizedDescription))
                return
            }
            switch result {
            case .sent: onFinish(.sent)
            case .saved: onFinish(.saved)
            case .cancelled: onFinish(.cancelled)
            case .failed: onFinish(.failed("Mail could not send the message."))
            @unknown default: onFinish(.cancelled)
            }
        }
    }
}

// MARK: - MessageComposeView

/// `MFMessageComposeViewController` as a SwiftUI sheet.
public struct MessageComposeView: UIViewControllerRepresentable {

    public static var canSendText: Bool { MFMessageComposeViewController.canSendText() }
    public static var canSendAttachments: Bool { MFMessageComposeViewController.canSendAttachments() }

    private let recipients: [String]
    private let body: String
    private let attachmentURL: URL?
    private let onFinish: (Result) -> Void

    public enum Result: Sendable {
        case sent
        case cancelled
        case failed
    }

    public init(
        recipients: [String],
        body: String,
        attachmentURL: URL? = nil,
        onFinish: @escaping (Result) -> Void
    ) {
        self.recipients = recipients
        self.body = body
        self.attachmentURL = attachmentURL
        self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = recipients.isEmpty ? nil : recipients
        controller.body = body

        if let attachmentURL, MFMessageComposeViewController.canSendAttachments() {
            controller.addAttachmentURL(attachmentURL, withAlternateFilename: attachmentURL.lastPathComponent)
        }
        return controller
    }

    public func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    public final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onFinish: (Result) -> Void

        init(onFinish: @escaping (Result) -> Void) {
            self.onFinish = onFinish
        }

        public func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            switch result {
            case .sent: onFinish(.sent)
            case .cancelled: onFinish(.cancelled)
            case .failed: onFinish(.failed)
            @unknown default: onFinish(.cancelled)
            }
        }
    }
}

// MARK: - ShareSheet

/// `UIActivityViewController` as a SwiftUI sheet.
public struct ShareSheet: UIViewControllerRepresentable {
    private let items: [Any]
    private let onFinish: ((Bool) -> Void)?

    public init(items: [Any], onFinish: ((Bool) -> Void)? = nil) {
        self.items = items
        self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish?(completed)
        }
        return controller
    }

    public func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - ExportDeliveryView

/// Presents the right composer for an ``ExportRequest`` and reports what happened.
///
/// This is the whole "scheduled export" payoff: a notification fires, the app
/// hands this view a request, and the user sees a composer already filled in with
/// the week's report. One tap to send.
public struct ExportDeliveryView: View {
    @Environment(\.trackerTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let report: ProgressReport
    private let channel: ExportChannel
    private let format: ReportFormat
    private let recipients: [String]
    private let onDelivered: (() -> Void)?

    @State private var fileURL: URL?
    @State private var errorText: String?

    public init(
        report: ProgressReport,
        channel: ExportChannel,
        format: ReportFormat,
        recipients: [String],
        onDelivered: (() -> Void)? = nil
    ) {
        self.report = report
        self.channel = channel
        self.format = format
        self.recipients = recipients
        self.onDelivered = onDelivered
    }

    public var body: some View {
        Group {
            if let errorText {
                unavailable(message: errorText)
            } else if let fileURL {
                composer(for: fileURL)
            } else {
                ProgressView("Building report…")
                    .task { prepare() }
            }
        }
    }

    @MainActor
    private func prepare() {
        let composer = ExportComposer(theme: theme)
        do {
            fileURL = try composer.file(for: report, format: format)
        } catch {
            errorText = "Could not build the report: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func composer(for url: URL) -> some View {
        let composer = ExportComposer(theme: theme)

        switch channel {
        case .email:
            if MailComposeView.canSendMail {
                MailComposeView(
                    recipients: recipients,
                    subject: composer.subject(for: report),
                    body: format == .html
                        ? HTMLReportRenderer().html(report)
                        : composer.messageBody(for: report, format: format),
                    isBodyHTML: format == .html,
                    attachments: MailComposeView.Attachment(url: url, mimeType: format.mimeType)
                        .map { [$0] } ?? []
                ) { result in
                    if case .sent = result { onDelivered?() }
                    dismiss()
                }
                .ignoresSafeArea()
            } else {
                unavailable(
                    message: "No mail account is set up on this device. Use the share sheet instead."
                )
            }

        case .message:
            if MessageComposeView.canSendText {
                MessageComposeView(
                    recipients: recipients,
                    body: composer.messageBody(for: report, format: format),
                    attachmentURL: format.isInlineText ? nil : url
                ) { result in
                    if case .sent = result { onDelivered?() }
                    dismiss()
                }
                .ignoresSafeArea()
            } else {
                unavailable(message: "This device can't send text messages.")
            }

        case .shareSheet:
            ShareSheet(items: [url]) { completed in
                if completed { onDelivered?() }
                dismiss()
            }
            .ignoresSafeArea()
        }
    }

    private func unavailable(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(theme.statusColor(.yellow))
            Text(message)
                .font(theme.typography.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.textSecondary)

            if let fileURL {
                ShareLink(item: fileURL) {
                    Label("Share the file", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Close") { dismiss() }
                .foregroundStyle(theme.textSecondary)
        }
        .padding(32)
    }
}

#endif
