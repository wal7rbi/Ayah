import AppKit
import SwiftUI

struct AboutView: View {
    @State private var isShowingAcknowledgements = false

    private struct ExternalLink: Identifiable {
        let id: String
        let label: String
        let destination: String

        var url: URL? {
            guard let url = URL(string: destination),
                  url.scheme == "https",
                  url.host != nil else { return nil }
            return url
        }
    }

    private static let externalLinks = [
        ExternalLink(
            id: "kfgqpc",
            label: "منصة مطوري القرآن — مجمع الملك فهد",
            destination: "https://qurancomplex.gov.sa/quran-dev/"
        ),
        ExternalLink(
            id: "adhan",
            label: "Adhan Swift — المصدر ورخصة MIT",
            destination: "https://github.com/batoulapps/adhan-swift"
        ),
        ExternalLink(
            id: "dynamicnotchkit",
            label: "DynamicNotchKit — المصدر ورخصة MIT",
            destination: "https://github.com/MrKai77/DynamicNotchKit"
        ),
        ExternalLink(
            id: "geonames",
            label: "GeoNames — مصدر بيانات المدن",
            destination: "https://www.geonames.org/"
        ),
        ExternalLink(
            id: "geonames-license",
            label: "GeoNames — رخصة CC BY 4.0",
            destination: "https://creativecommons.org/licenses/by/4.0/"
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                arabicSummary
                credits
                independenceNotice
                links
                englishSummary
                acknowledgementsButton
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, minHeight: 520)
        .environment(\.layoutDirection, .rightToLeft)
        .multilineTextAlignment(.trailing)
        .sheet(isPresented: $isShowingAcknowledgements) {
            AcknowledgementsView()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityLabel("أيقونة تطبيق آية")

            VStack(alignment: .leading, spacing: 4) {
                Text("آية")
                    .font(.largeTitle.bold())
                Text(versionDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var arabicSummary: some View {
        Text("آية تطبيق مستقل ومفتوح المصدر لعرض آيات القرآن الكريم والمساعدة على الحفظ وحساب أوقات الصلاة محليًا. لا يتصل التطبيق بالإنترنت ولا يرسل بياناتك إلى أي جهة.")
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 14) {
            creditSection(
                title: "القرآن الكريم والخط",
                text: "يستخدم آية نص القرآن الكريم برواية حفص بالرسم العثماني، وخط حفص العثماني، من منصة مطوري مجمع الملك فهد لطباعة المصحف الشريف."
            )
            creditSection(
                title: "أوقات الصلاة",
                text: "تُحسب أوقات الصلاة محليًا باستخدام مكتبة Adhan Swift من Batoul Apps، المرخصة برخصة MIT."
            )
            creditSection(
                title: "واجهة النوتش والعرض العائم",
                text: "شكل النوتش والعرض العائم وحركة الانزلاق مقتبسة من DynamicNotchKit للمطور Kai Azim، المرخص برخصة MIT، مع تعديلات تناسب آية."
            )
            creditSection(
                title: "بيانات المدن",
                text: "يستخدم آية مجموعة مصفاة من بيانات GeoNames للمدن والإحداثيات والمناطق الزمنية، بترخيص CC BY 4.0."
            )
        }
    }

    private var independenceNotice: some View {
        Text("آية مشروع مستقل وغير تابع لمجمع الملك فهد لطباعة المصحف الشريف أو Batoul Apps أو GeoNames. ذكر المصادر لا يعني وجود شراكة أو رعاية أو اعتماد منها.")
            .font(.callout.weight(.medium))
            .padding(12)
            .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("تنبيه الاستقلالية: آية مشروع مستقل، وذكر المصادر لا يعني الشراكة أو الرعاية أو الاعتماد")
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("المصادر الخارجية")
                .font(.headline)

            ForEach(Self.externalLinks) { link in
                if let url = link.url {
                    Link(destination: url) {
                        Label(link.label, systemImage: "arrow.up.right.square")
                    }
                } else {
                    Label("\(link.label) — الرابط غير متوفر", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }

            Text("تُفتح هذه الروابط في متصفحك. لا يجري تطبيق آية اتصالًا شبكيًا بنفسه.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var englishSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("About Ayah")
                .font(.headline)
            Text("Ayah is an independent, open-source, fully offline macOS app. Quran text and the Uthmanic Hafs font come from the King Fahd Glorious Quran Printing Complex developer platform. Prayer times use Adhan Swift, and filtered city data comes from GeoNames. The notch shape and floating popup presentation adapt DynamicNotchKit by Kai Azim (MIT). Source attribution does not imply affiliation, sponsorship, certification, or endorsement.")
                .font(.callout)
        }
        .environment(\.layoutDirection, .leftToRight)
        .multilineTextAlignment(.leading)
    }

    private var acknowledgementsButton: some View {
        Button("التراخيص والمصادر") {
            isShowingAcknowledgements = true
        }
        .keyboardShortcut("l", modifiers: [.command])
        .accessibilityHint("يعرض بيان المصادر والتراخيص الكامل المرفق مع التطبيق")
    }

    private func creditSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var versionDescription: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "الإصدار \(version) (\(build))"
    }
}

private struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("التراخيص والمصادر")
                    .font(.title2.bold())
                Spacer()
                Button("إغلاق") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                Text(acknowledgements)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(minWidth: 560, minHeight: 440)
        .environment(\.layoutDirection, .rightToLeft)
        .multilineTextAlignment(.trailing)
    }

    private var acknowledgements: String {
        guard let url = Bundle.main.url(forResource: "ACKNOWLEDGEMENTS", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8),
              !contents.isEmpty else {
            return "تعذر تحميل بيان التراخيص والمصادر المرفق مع التطبيق.\n\nThe bundled acknowledgements document could not be loaded."
        }
        return contents
    }
}
