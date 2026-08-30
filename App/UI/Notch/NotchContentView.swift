import AyahKit
import SwiftUI

/// Renders the verse batch `NotchViewModel` is currently displaying, in
/// the bundled KFGQPC Uthmanic Hafs font. `versesPerDisplay` (see
/// ARCHITECTURE.md's "Verses per display" section) means this is
/// sometimes more than one ayah, laid out as continuous text rather than
/// separate blocks, since consecutive ayahs read as one passage.
/// Previous/Repeat/Next controls and theming are still deliberately
/// omitted — not this stage's scope, not left as non-functional
/// placeholders.
///
/// A single shape resizes between the collapsed and expanded dimensions
/// (rather than swapping between two separate views) so the bar visibly
/// grows into the card instead of cross-fading between two disconnected
/// shapes.
struct NotchContentView: View {
    @ObservedObject var viewModel: NotchViewModel
    let isPhysicalNotch: Bool

    private static let arabicFontName = "kfgqpchafsuthmanicscript-Reg"
    private static let expandedSize = CGSize(width: 480, height: 220)

    var body: some View {
        let shape = self.shape
        return shape
            .fill(.black)
            .frame(
                width: viewModel.isExpanded ? Self.expandedSize.width : viewModel.collapsedSize.width,
                height: viewModel.isExpanded ? Self.expandedSize.height : viewModel.collapsedSize.height
            )
            .overlay {
                if viewModel.isExpanded {
                    cardContent.transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
                }
            }
            .clipShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.toggleExpanded()
            }
            .accessibilityElement(children: viewModel.isExpanded ? .contain : .ignore)
            .accessibilityLabel("لوحة آية")
            .accessibilityValue(viewModel.isExpanded ? "مفتوحة" : "مطوية")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                viewModel.toggleExpanded()
            }
    }

    /// A concave notch flare on real notch hardware; a plain flat-topped,
    /// rounded-bottom bar on the non-notch fallback, where the panel sits
    /// flush against the menu bar rather than flaring out of a camera
    /// housing above it. Type-erased since both branches back the same
    /// `shape` value used for both `.fill` and `.clipShape` below.
    private var shape: AnyShape {
        let topRadius: CGFloat = viewModel.isExpanded ? 14 : 6
        let bottomRadius: CGFloat = viewModel.isExpanded ? 26 : 10
        guard isPhysicalNotch else {
            return AnyShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: bottomRadius,
                    bottomTrailingRadius: bottomRadius,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
        }
        return AnyShape(Self.notchShape(topRadius: topRadius, bottomRadius: bottomRadius))
    }

    private var cardContent: some View {
        VStack(spacing: 12) {
            switch viewModel.content {
            case .none:
                if viewModel.isDisplayEnabled {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Text("عرض الآيات متوقف")
                        .font(.system(size: 13))
                        .environment(\.layoutDirection, .rightToLeft)
                        .foregroundStyle(.white.opacity(0.7))
                }
            case .verses(let ayahs, let surah):
                Text(combinedText(for: ayahs))
                    .font(.custom(Self.arabicFontName, size: 22))
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.center)
                    .lineLimit(3 + ayahs.count)
                    .minimumScaleFactor(0.35)
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)

                Text(reference(for: ayahs, surah: surah))
                    .font(.system(size: 13))
                    .environment(\.layoutDirection, .rightToLeft)
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.opacity)
            case .prayerAlert(let event, let ayah, let surah):
                prayerAlertCard(event: event, ayah: ayah, surah: surah)
            }
        }
        // The top inset must clear the physical camera housing, not just
        // look padded — `collapsedSize.height` is the live notch height
        // computed from this Mac's actual `safeAreaInsets.top`
        // (`NotchController.notchFrame`), so card text (including tall
        // Arabic diacritics) never renders in the area the housing itself
        // occludes, whatever a given device's notch height is.
        .padding(.top, isPhysicalNotch ? max(20, viewModel.collapsedSize.height + 12) : 20)
        .padding([.horizontal, .bottom], 20)
        .frame(width: Self.expandedSize.width, height: Self.expandedSize.height)
        .animation(.easeInOut(duration: 0.35), value: viewModel.content)
    }

    private func prayerAlertCard(event: PrayerAlertEvent, ayah: QuranAyah?, surah: Surah?) -> some View {
        VStack(spacing: 10) {
            Text("صلاة \(event.prayerNameArabic)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text(prayerAlertMessage(for: event))
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))

            if let ayah {
                Text(ayah.uthmanicText)
                    .font(.custom(Self.arabicFontName, size: 18))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)

                Text(reference(for: [ayah], surah: surah))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.opacity)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    /// At-time wording mirrors the deleted OS-notification's tone;
    /// reminder wording follows the product's own example. Both use
    /// Western digits, matching `PopoverContentView.reminderMinutesPresets`'s
    /// own labels — this app already writes Arabic UI text with Western
    /// numerals throughout.
    private func prayerAlertMessage(for event: PrayerAlertEvent) -> String {
        event.isReminder
            ? "توضأ واستعد.. باقي \(event.offsetMinutes) دقائق على الأذان"
            : "حان الآن وقت صلاة \(event.prayerNameArabic)"
    }

    /// A concave top flare (ported from boring.notch's `NotchShape`, see
    /// `NotchShape.swift`) plus a larger, convex bottom radius — reads as
    /// the panel growing organically out of the physical notch cutout
    /// rather than sitting below it as a plain rounded rectangle. An
    /// earlier attempt at this same silhouette (custom Path with
    /// overshooting Bézier control points) measurably failed to render as
    /// intended — verified by scanning rendered pixel rows, the top
    /// corners came out sharp, not curved; boring.notch's simpler
    /// quad-curve construction doesn't share that failure mode and was
    /// re-verified by screenshot before shipping here.
    private static func notchShape(topRadius: CGFloat, bottomRadius: CGFloat) -> NotchShape {
        NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
    }

    private func combinedText(for ayahs: [QuranAyah]) -> String {
        ayahs.map(\.uthmanicText).joined(separator: " ")
    }

    private func reference(for ayahs: [QuranAyah], surah: Surah?) -> String {
        guard let first = ayahs.first, let last = ayahs.last else { return "" }
        let range = first.ayahNumber == last.ayahNumber
            ? "\(first.ayahNumber)"
            : "\(first.ayahNumber)-\(last.ayahNumber)"
        guard let surah else {
            return "\(first.surahNumber):\(range)"
        }
        return "\(surah.nameArabic) \(range)"
    }
}
