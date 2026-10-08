import Combine
import Foundation

/// Shared availability for scheduling and management. Retry opens the same file;
/// a storage failure never requires deleting user progress or stopping Quran reminders.
public final class MemorizationAccess: ObservableObject {
    @Published public private(set) var repository: MemorizationRepository?
    @Published public private(set) var errorMessage: String?
    private let reopen: (() throws -> MemorizationRepository)?
    private static let cursorSaveFailedMessage = "تعذر حفظ تقدم الحفظ. قد يتكرر المقطع حتى تنجح إعادة المحاولة."

    public init(repository: MemorizationRepository?, reopen: (() throws -> MemorizationRepository)? = nil) {
        self.repository = repository
        self.reopen = reopen
        if repository == nil { errorMessage = "بيانات الحفظ غير متاحة. يستمر عرض الآيات من القرآن كاملاً." }
    }

    /// No UI calls this yet: the Retry control was rolled back. Kept, with
    /// its tests, for when it returns.
    public func retry() {
        guard let reopen else { return }
        do {
            if repository == nil { repository = try reopen() }
            _ = fetchEnabled()
            if repository?.lastFetchError == nil { errorMessage = nil }
        } catch {
            errorMessage = "تعذر فتح بيانات الحفظ. لم يتم حذف تقدمك؛ حاول مرة أخرى."
        }
    }

    public func fetchEnabled() -> [MemorizationSet] {
        guard let repository else { return [] }
        let sets = repository.fetchEnabled()
        if repository.lastFetchError != nil {
            errorMessage = "تعذر قراءة مجموعات الحفظ. تُعرض آيات من القرآن كاملاً حتى استعادة البيانات."
        }
        return sets
    }

    public func updateCursor(id: String, cursorAyah: Int) throws {
        guard let repository else { return }
        do {
            try repository.updateCursor(id: id, cursorAyah: cursorAyah)
            // A successful save clears only its own earlier failure, not a load error.
            if errorMessage == Self.cursorSaveFailedMessage { errorMessage = nil }
        } catch {
            errorMessage = Self.cursorSaveFailedMessage
            throw error
        }
    }
}
