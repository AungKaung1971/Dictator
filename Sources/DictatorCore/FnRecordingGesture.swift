import Foundation

/// Fn tap timing uses a monotonic clock. Normal holds stop immediately on release;
/// only a short first tap waits briefly for a second press before finalising.
public struct FnRecordingGesture {
    public enum Action: Equatable { case start, stop, handsFree }
    private enum State {
        case idle
        case held(since: TimeInterval)
        case awaitingSecondPress(deadline: TimeInterval)
        case handsFree(keyDown: Bool)
        case stoppedAwaitingRelease
    }
    public static let maximumTapDuration: TimeInterval = 0.35
    public static let doubleTapInterval: TimeInterval = 0.50
    private var state: State = .idle
    public init() {}
    public var pendingDeadline: TimeInterval? {
        if case let .awaitingSecondPress(deadline) = state { return deadline }
        return nil
    }
    public mutating func press(at time: TimeInterval) -> Action? {
        switch state {
        case .idle:
            state = .held(since: time); return .start
        case let .awaitingSecondPress(deadline):
            if time <= deadline {
                state = .handsFree(keyDown: true); return .handsFree
            }
            // A delayed timer must not turn a slow second tap into hands-free mode.
            state = .stoppedAwaitingRelease; return .stop
        case .handsFree(keyDown: false):
            state = .stoppedAwaitingRelease; return .stop
        case .held, .handsFree(keyDown: true), .stoppedAwaitingRelease:
            return nil
        }
    }
    public mutating func release(at time: TimeInterval) -> Action? {
        switch state {
        case let .held(since):
            if time - since <= Self.maximumTapDuration {
                state = .awaitingSecondPress(deadline: time + Self.doubleTapInterval)
                return nil
            }
            state = .idle; return .stop
        case .handsFree(keyDown: true):
            state = .handsFree(keyDown: false); return nil
        case .stoppedAwaitingRelease:
            state = .idle; return nil
        case .idle, .awaitingSecondPress, .handsFree(keyDown: false):
            return nil
        }
    }
    public mutating func expire(at time: TimeInterval) -> Action? {
        guard let deadline = pendingDeadline, time >= deadline else { return nil }
        state = .idle; return .stop
    }
    public mutating func reset() { state = .idle }
}
