import Foundation
@testable import AyahKit

@MainActor
final class ManualOneShotTimer: OneShotTimerScheduling {
    final class Entry: OneShotTimerToken {
        let interval: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false
        init(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.interval = interval
            self.action = action
        }
        func cancel() { isCancelled = true }
        // Deliberately permit a queued callback after cancellation.
        func fire() { action() }
    }
    var entries: [Entry] = []
    func schedule(after interval: TimeInterval, leeway: TimeInterval,
                  action: @escaping @MainActor () -> Void) -> any OneShotTimerToken {
        let entry = Entry(interval: interval, action: action)
        entries.append(entry)
        return entry
    }
}
