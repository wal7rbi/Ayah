import AyahKit
import SwiftUI

/// Add/edit sheet for a single `MemorizationSet`. `existing == nil` means
/// "add new"; otherwise the fields are prefilled for editing. This view
/// only assembles the fields — the parent (`MemorizationSetsView`)
/// performs the actual repository write and reload.
struct MemorizationSetEditorView: View {
    let surahs: [Surah]
    let existing: MemorizationSet?
    let onSave: (
        _ surahNumber: Int, _ startAyah: Int, _ endAyah: Int,
        _ repetitionMode: MemorizationSet.RepetitionMode, _ isEnabled: Bool
    ) -> Void
    let onCancel: () -> Void

    @State private var surahNumber: Int
    @State private var startAyah: Int
    @State private var endAyah: Int
    @State private var isEnabled: Bool

    init(
        surahs: [Surah],
        existing: MemorizationSet?,
        onSave: @escaping (
            _ surahNumber: Int, _ startAyah: Int, _ endAyah: Int,
            _ repetitionMode: MemorizationSet.RepetitionMode, _ isEnabled: Bool
        ) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.surahs = surahs
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _surahNumber = State(initialValue: existing?.surahNumber ?? surahs.first?.number ?? 1)
        _startAyah = State(initialValue: existing?.startAyah ?? 1)
        _endAyah = State(initialValue: existing?.endAyah ?? 1)
        _isEnabled = State(initialValue: existing?.isEnabled ?? true)
    }

    private var currentSurah: Surah? {
        surahs.first { $0.number == surahNumber }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "إضافة مجموعة حفظ" : "تعديل مجموعة الحفظ")
                .font(.headline)

            Picker("السورة", selection: $surahNumber) {
                ForEach(surahs, id: \.number) { surah in
                    Text(surah.nameArabic).tag(surah.number)
                }
            }
            .onChange(of: surahNumber) { _ in clampRangeToCurrentSurah() }

            if let currentSurah {
                Stepper("من الآية: \(startAyah)", value: $startAyah, in: 1...currentSurah.ayahCount)
                    .onChange(of: startAyah) { newValue in
                        if endAyah < newValue { endAyah = newValue }
                    }

                Stepper("إلى الآية: \(endAyah)", value: $endAyah, in: startAyah...currentSurah.ayahCount)
            }

            Toggle("مفعّلة", isOn: $isEnabled)

            Spacer(minLength: 0)

            HStack {
                Button("إلغاء", action: onCancel)
                Spacer()
                Button("حفظ") {
                    // Random mode isn't offered here — it would shuffle the
                    // memorization order the user is trying to build.
                    onSave(surahNumber, startAyah, endAyah, .sequential, isEnabled)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 320)
        .environment(\.layoutDirection, .rightToLeft)
        .multilineTextAlignment(.trailing)
    }

    private func clampRangeToCurrentSurah() {
        guard let currentSurah else { return }
        if startAyah > currentSurah.ayahCount { startAyah = currentSurah.ayahCount }
        if endAyah > currentSurah.ayahCount { endAyah = currentSurah.ayahCount }
        if endAyah < startAyah { endAyah = startAyah }
    }
}
