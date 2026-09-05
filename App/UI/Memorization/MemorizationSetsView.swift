import AyahKit
import SwiftUI

/// Shared with the retained window controller so every opening refreshes
/// the list, even when SwiftUI does not run onAppear again.
@MainActor
final class MemorizationSetsModel: ObservableObject {
    @Published private(set) var sets: [MemorizationSet] = []
    @Published private(set) var loadErrorMessage: String?
    private let repository: MemorizationRepository

    init(repository: MemorizationRepository) {
        self.repository = repository
        reload()
    }

    func reload() {
        sets = repository.fetchAll()
        loadErrorMessage = repository.lastFetchError != nil
            ? "تعذر تحميل مجموعات الحفظ. حاول مرة أخرى." : nil
    }
}

/// Lists, creates, edits, enables/disables, and deletes memorization
/// sets. `VerseScheduler` re-queries `memorizationRepository` fresh on
/// every timer fire rather than caching (see
/// `VerseScheduler.selectNextVerses()`), so edits made here take effect
/// on the next scheduled display with no extra plumbing — this view just
/// needs to write through the same repository instance the scheduler
/// was built with.
struct MemorizationSetsView: View {
    let quranRepository: QuranRepository
    let memorizationRepository: MemorizationRepository
    /// `QuranRepository.surahs()` is a cheap in-memory cached read (see
    /// its implementation), not a query worth re-running per render —
    /// loaded once here rather than via `.onAppear`, since `.onAppear`
    /// timing on a view hosted directly as an `NSWindow`'s
    /// `contentViewController` (no SwiftUI `App`/`Scene` driving it, see
    /// `MemorizationSetsWindowController`) isn't guaranteed to run before
    /// the user can interact with the window.
    private let surahs: [Surah]

    @ObservedObject private var model: MemorizationSetsModel
    @State private var editorTarget: EditorTarget?
    @State private var writeErrorMessage: String?

    init(
        quranRepository: QuranRepository,
        memorizationRepository: MemorizationRepository,
        model: MemorizationSetsModel
    ) {
        self.quranRepository = quranRepository
        self.memorizationRepository = memorizationRepository
        self.surahs = quranRepository.surahs()
        self.model = model
    }

    private var surahsByNumber: [Int: Surah] {
        Dictionary(uniqueKeysWithValues: surahs.map { ($0.number, $0) })
    }

    private enum EditorTarget: Identifiable {
        case add
        case edit(MemorizationSet)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let set): return set.id
            }
        }

        var existingSet: MemorizationSet? {
            if case .edit(let set) = self { return set }
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let loadErrorMessage = model.loadErrorMessage {
                Text(loadErrorMessage)
                    .foregroundStyle(.red)
                    .padding(8)
            }
            if let writeErrorMessage {
                Text(writeErrorMessage)
                    .foregroundStyle(.red)
                    .padding(8)
                    .accessibilityLabel("تعذر حفظ تغييرات مجموعة الحفظ")
            }
            if model.sets.isEmpty {
                Spacer()
                Text("لا توجد مجموعات حفظ بعد")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(model.sets) { set in
                        row(for: set)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("إضافة مجموعة") {
                    editorTarget = .add
                }
                .padding(12)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(item: $editorTarget) { target in
            MemorizationSetEditorView(
                surahs: surahs,
                existing: target.existingSet,
                onSave: { surahNumber, startAyah, endAyah, mode, isEnabled in
                    save(target: target, surahNumber: surahNumber, startAyah: startAyah, endAyah: endAyah, mode: mode, isEnabled: isEnabled)
                },
                onCancel: { editorTarget = nil }
            )
        }
    }

    private func row(for set: MemorizationSet) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { set.isEnabled },
                set: { setEnabled(set, to: $0) }
            ))
            .labelsHidden()

            // A plain `.onTapGesture` here doesn't reliably fire on macOS:
            // `List` rows are backed by `NSTableView`, whose own
            // click-to-select handling competes with a tap gesture on the
            // row's content (confirmed in `CityPickerView`, where the
            // gesture silently never fired). A `Button` per row goes
            // through AppKit's normal action mechanism instead and is the
            // reliable idiom for "tap a List row" on macOS.
            Button {
                editorTarget = .edit(set)
            } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(rangeLabel(for: set))
                    Text(set.repetitionMode == .sequential ? "متسلسل" : "عشوائي")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                delete(set)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func rangeLabel(for set: MemorizationSet) -> String {
        let name = surahsByNumber[set.surahNumber]?.nameArabic ?? "\(set.surahNumber)"
        return set.startAyah == set.endAyah
            ? "\(name) \(set.startAyah)"
            : "\(name) \(set.startAyah)-\(set.endAyah)"
    }

    private func save(
        target: EditorTarget,
        surahNumber: Int, startAyah: Int, endAyah: Int,
        mode: MemorizationSet.RepetitionMode, isEnabled: Bool
    ) {
        do {
            switch target {
            case .add:
                try memorizationRepository.create(
                    surahNumber: surahNumber, startAyah: startAyah, endAyah: endAyah,
                    repetitionMode: mode, isEnabled: isEnabled
                )
            case .edit(let set):
                try memorizationRepository.updateDetails(
                    id: set.id, surahNumber: surahNumber, startAyah: startAyah,
                    endAyah: endAyah, repetitionMode: mode, isEnabled: isEnabled
                )
            }
            writeErrorMessage = nil
            editorTarget = nil
            model.reload()
        } catch {
            writeErrorMessage = "تعذر حفظ مجموعة الحفظ. تحقق من القيم وحاول مرة أخرى."
        }
    }

    private func setEnabled(_ set: MemorizationSet, to isEnabled: Bool) {
        do {
            try memorizationRepository.setEnabled(id: set.id, isEnabled: isEnabled)
            writeErrorMessage = nil
            model.reload()
        } catch {
            writeErrorMessage = "تعذر تحديث مجموعة الحفظ. حاول مرة أخرى."
        }
    }

    private func delete(_ set: MemorizationSet) {
        do {
            try memorizationRepository.delete(id: set.id)
            writeErrorMessage = nil
            model.reload()
        } catch {
            writeErrorMessage = "تعذر حذف مجموعة الحفظ. حاول مرة أخرى."
        }
    }
}
