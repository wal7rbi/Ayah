import Dispatch
import Foundation

/// A cancellable one-shot deadline, delivered synchronously on the main actor.
/// Injecting this boundary lets tests exercise cancellation and rescheduling
/// without sleeping or depending on wall-clock time.
@MainActor
public protocol OneShotTimerToken: AnyObject {
    func cancel()
}

@MainActor
public protocol OneShotTimerScheduling {
    func schedule(after interval: TimeInterval, leeway: TimeInterval,
                  action: @escaping @MainActor () -> Void) -> any OneShotTimerToken
}

@MainActor
final class DispatchOneShotTimer: OneShotTimerScheduling {
    func schedule(after interval: TimeInterval, leeway: TimeInterval,
                  action: @escaping @MainActor () -> Void) -> any OneShotTimerToken {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + interval,
                        leeway: .milliseconds(Int(leeway * 1000)))
        source.setEventHandler { action() }
        source.resume()
        return Token(source: source)
    }

    private final class Token: OneShotTimerToken {
        let source: DispatchSourceTimer
        init(source: DispatchSourceTimer) { self.source = source }
        func cancel() { source.cancel() }
        deinit { source.cancel() }
    }
}
