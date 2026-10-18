import CoreGraphics

/// Seconds since the user last touched the keyboard, mouse or trackpad.
public protocol IdleSource: Sendable {
    func secondsSinceLastInput() -> Double
}

/// The session's input idle time from Core Graphics. Needs no permission or entitlement. A
/// locked screen or the screen saver produces no input events, so they count as idle too.
public struct SystemIdleSource: IdleSource {
    public init() {}

    public func secondsSinceLastInput() -> Double {
        // ~0 is kCGAnyInputEventType.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
