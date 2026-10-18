import CoreGraphics

/// The session's input idle time from Core Graphics. Needs no permission or entitlement. A
/// locked screen or the screen saver produces no input events, so they count as idle too.
public struct SystemIdleSource: Sendable {
    public init() {}

    /// Seconds since the user last touched the keyboard, mouse or trackpad.
    public func secondsSinceLastInput() -> Double {
        // ~0 is kCGAnyInputEventType.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
