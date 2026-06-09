import Foundation

/// Represents the visual state of the menu bar icon.
public enum MenuBarIconState: Sendable {
    /// Default state — brain outline icon.
    case idle

    /// Idea is being processed — animated spinner.
    case processing

    /// Idea successfully filed — lightbulb icon, auto-reverts to `.idle` after 3 seconds.
    case done

    /// An error occurred — warning icon stays until the user clicks the menu icon.
    /// - Parameter message: A human-readable description of the error.
    case error(String)
}
