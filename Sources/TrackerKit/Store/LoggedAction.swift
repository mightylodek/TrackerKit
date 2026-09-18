import Foundation

/// A logging action that can be reversed.
///
/// ## Why this shape
/// The mistake this exists for is a double-tap, and a double-tap is noticed
/// *immediately*. That rules a lot of designs out:
///
/// - **Shake to undo** is the system affordance and nobody discovers it.
/// - **A full undo stack** invites "undo six things" on data where the user's
///   mental model is a list of entries, not a timeline of edits.
/// - **Confirming every log** would tax the common case to protect the rare one,
///   and the whole point of quick logging is that it is quick.
///
/// So this holds exactly **one** action — the last one — surfaced immediately
/// where it happened and expiring on its own. Anything older is corrected in the
/// tracker's entry list, which already supports deletion and is the right place
/// for "I logged something last Tuesday by mistake".
public struct LoggedAction: Identifiable, Sendable, Equatable {

    /// What happened, and what reversing it requires.
    public enum Reversal: Sendable, Equatable {
        /// A new entry was inserted. Undo deletes it.
        case inserted(entryID: UUID)
        /// An existing entry's value was replaced (checkbox and rating log once
        /// per day). Undo restores the previous value.
        case replaced(entryID: UUID, previousValue: Double)
        /// An entry was removed by toggling off. Undo puts it back.
        case removed(entry: Entry)
    }

    public let id = UUID()
    public let trackerID: UUID
    public let trackerTitle: String
    /// Human-readable summary, e.g. "Added 10 min".
    public let summary: String
    public let reversal: Reversal
    public let at: Date

    public init(
        trackerID: UUID,
        trackerTitle: String,
        summary: String,
        reversal: Reversal,
        at: Date = .now
    ) {
        self.trackerID = trackerID
        self.trackerTitle = trackerTitle
        self.summary = summary
        self.reversal = reversal
        self.at = at
    }

    /// How long the undo affordance stays offered.
    ///
    /// Long enough to notice a slip and react, short enough that it isn't
    /// permanent furniture on the screen.
    public static let offerDuration: TimeInterval = 6

    public func hasExpired(asOf now: Date = .now) -> Bool {
        now.timeIntervalSince(at) > Self.offerDuration
    }
}
