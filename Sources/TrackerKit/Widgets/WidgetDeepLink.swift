import Foundation

/// Deep links from a widget into the app.
///
/// A display-only widget still has one job beyond showing numbers: getting you to
/// the right place in one tap. Opening the app to its dashboard when you tapped a
/// specific tracker makes the person do the navigation twice.
///
/// WidgetKit delivers these to the owning app through `onOpenURL` without the
/// scheme needing to be registered in `Info.plist` — the system already knows
/// which app owns the widget. Registering it anyway is harmless and makes the
/// same links work from elsewhere.
public enum WidgetDeepLink: Equatable, Sendable {
    /// Open a specific tracker's detail screen.
    case tracker(UUID)
    /// Open a specific tracker with the logging sheet already up — the shortest
    /// path from "I did the thing" to it being recorded.
    case log(UUID)
    /// Open the dashboard for a profile.
    case profile(UUID)

    public static let scheme = "trackerdash"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .tracker(let id):
            components.host = "tracker"
            components.path = "/\(id.uuidString)"
        case .log(let id):
            components.host = "log"
            components.path = "/\(id.uuidString)"
        case .profile(let id):
            components.host = "profile"
            components.path = "/\(id.uuidString)"
        }
        // The components above are always well formed, so this cannot fail; the
        // fallback exists only so callers never deal with an optional.
        return components.url ?? URL(string: "\(Self.scheme)://")!
    }

    /// Parses a link the app received. Returns `nil` for anything not ours.
    public init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let identifier = url.pathComponents
            .first { UUID(uuidString: $0) != nil }
            .flatMap(UUID.init(uuidString:))

        switch url.host {
        case "tracker":
            guard let identifier else { return nil }
            self = .tracker(identifier)
        case "log":
            guard let identifier else { return nil }
            self = .log(identifier)
        case "profile":
            guard let identifier else { return nil }
            self = .profile(identifier)
        default:
            return nil
        }
    }

    /// The tracker this link refers to, if any.
    public var trackerID: UUID? {
        switch self {
        case .tracker(let id), .log(let id): id
        case .profile: nil
        }
    }
}
