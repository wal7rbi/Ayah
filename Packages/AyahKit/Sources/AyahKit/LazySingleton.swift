/// Lazily creates and reuses a single instance across repeated calls,
/// instead of creating a new one on every call — the "only ever one
/// [child window] open" pattern `StatusItemController` (App target)
/// needs for each of its AppKit window controllers (memorization sets,
/// city picker). Generic over any reference type so the reuse logic
/// itself is plain, AppKit-free, and unit-testable with `swift test`.
/// `App/` does now have a test target (`AyahTests`), but it covers
/// `NotchViewModel`, not the real `NSWindowController` subclasses that
/// use this.
public final class LazySingleton<Value: AnyObject> {
    public private(set) var current: Value?

    public init() {}

    /// Returns the existing instance if one was already created, or
    /// creates one via `makeValue`, stores it, and returns it. `makeValue`
    /// never runs more than once across repeated calls.
    @discardableResult
    public func getOrCreate(_ makeValue: () -> Value) -> Value {
        if let current { return current }
        let created = makeValue()
        current = created
        return created
    }
}
