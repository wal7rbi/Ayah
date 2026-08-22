import AyahKit
import SwiftUI

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

    @State private var sets: [MemorizationSet]
    @State private var editorTarget: EditorTarget?

    init(quranRepository: QuranRepository, memorizationRepository: MemorizationRepository) {
        self.quranRepository = quranRepository
        self.memorizationRepository = memorizationRepository
        self.surahs = quranRepository.surahs()
        _sets = State(initialValue: memorizationRepository.fetchAll())
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
            if sets.isEmpty {
                Spacer()
                Text("لا توجد مجموعات حفظ بعد")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(sets) { set in
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

    private func reload() {
        sets = memorizationRepository.fetchAll()
    }

    private func save(
        target: EditorTarget,
        surahNumber: Int, startAyah: Int, endAyah: Int,
        mode: MemorizationSet.RepetitionMode, isEnabled: Bool
    ) {
        switch target {
        case .add:
            try? memorizationRepository.create(
                surahNumber: surahNumber, startAyah: startAyah, endAyah: endAyah,
                repetitionMode: mode, isEnabled: isEnabled
            )
        case .edit(var set):
            set.surahNumber = surahNumber
            set.startAyah = startAyah
            set.endAyah = endAyah
            set.repetitionMode = mode
            set.isEnabled = isEnabled
            try? memorizationRepository.update(set)
        }
        editorTarget = nil
        reload()
    }

    private func setEnabled(_ set: MemorizationSet, to isEnabled: Bool) {
        var updated = set
        updated.isEnabled = isEnabled
        try? memorizationRepository.update(updated)
        reload()
    }

    private func delete(_ set: MemorizationSet) {
        try? memorizationRepository.delete(id: set.id)
        reload()
    }
}
