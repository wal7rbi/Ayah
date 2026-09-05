# آية 1.0.4

إصلاحات لجدولة عرض الآيات وتنبيهات الصلاة، وحفظ تقدّم مجموعات الحفظ، مع بطاقة سوداء عائمة جديدة للأجهزة التي لا تحتوي على نتوء في الشاشة.

## التغييرات

- تطبيق تغييرات إعدادات تنبيهات الصلاة فورًا، وإلغاء التنبيه المجدول عند إيقافها. تظل التنبيهات بطاقات داخل التطبيق تظهر عند النتوء أو أعلى الشاشة.
- الحفاظ على تقدّم الحفظ عند تفعيل المجموعة أو تعطيلها، والسماح بتعديل نطاق الآيات مع إعادة موضع القراءة عند الحاجة.
- استعادة آخر بطاقة عند بدء التطبيق دون تجاوز آيات لم تُعرض.
- تطبيق الفاصل الزمني الجديد من لحظة تغييره دون عرض آيات إضافية فورًا.
- بطاقة سوداء معتمة بزوايا مستديرة ونص أبيض للأجهزة دون نتوء؛ تنزلق عند الظهور والإغلاق، وتحترم إعداد تقليل الحركة.
- الانتقال بين عرض النتوء والبطاقة العائمة عند تغيّر الشاشات، مع الاحتفاظ بالمحتوى والجدولة.
- تجنّب تكرار عملية البحث عن المدن أثناء تحديث الواجهة.
- توثيق مصدر شكل النتوء وتصميم البطاقة من DynamicNotchKit وإرفاق رخصة MIT وإضافة النسبة إلى نافذة «حول التطبيق».

## المتطلبات والتثبيت

- أجهزة Mac بمعالجات Apple Silicon، ونظام macOS 13 أو أحدث.
- توقيع ad-hoc مع hardened runtime، دون Developer ID أو توثيق Apple.
- بعد محاولة الفتح الأولى، استخدم إعدادات النظام > الخصوصية والأمان > فتح على أي حال.
- تحقق من ملف DMG باستخدام ملف SHA-256 المرفق.

## حدود التحقق

نجحت اختبارات الحزمة والتطبيق والبناء المحلي. اختبارات الانتقال بين الشاشات تستخدم بيانات شاشات اختبارية؛ لا تُعد بديلًا عن التحقق على أجهزة فعلية. تبقى مراجعة الانتقال الفعلي عند إغلاق غطاء MacBook، وتجربة تنزيل معزول حديث عبر Gatekeeper، ومراجعة الأسماء العربية المنسّقة يدويًا أمورًا غير مؤكدة في سجل هذا الإصدار.

---

# Ayah 1.0.4

Fixes verse/prayer-popup scheduling and memorization progress, with a new black floating card for Macs without a notch.

## Changes

- Prayer-popup settings take effect immediately, and disabling them cancels the pending popup. Alerts remain in-app notch/top-edge cards.
- Enabling/disabling memorization sets preserves current progress. Valid range edits reset the cursor only when required.
- Restoring the last card at startup no longer consumes unseen verses.
- Changing the verse interval schedules the next display one full new interval from the change, without immediately selecting another batch.
- Non-notch displays use an opaque black card with rounded corners and white text, sliding in and out as a complete card. Reduce Motion is respected.
- Presentation switches between physical-notch and floating modes as displays change, preserving content and scheduling.
- City filtering runs once per view evaluation.
- Correct DynamicNotchKit attribution and the upstream MIT notice are included in source, bundled acknowledgements, and About.

## Requirements and installation

- Apple Silicon; macOS 13 or later.
- Ad-hoc signed with hardened runtime; no Apple Developer ID signature or Apple notarization.
- After the first blocked launch, use System Settings > Privacy & Security > Open Anyway.
- Verify the DMG using the accompanying SHA-256 file.

## Verification limits

Package/app tests and local builds pass. Automated display-transition tests use injected screen descriptions; they do not certify physical clamshell/display behavior. Physical monitor transitions, a fresh quarantined GitHub-download Gatekeeper exercise, and native-speaker review of manually curated Arabic city names remain unverified in this release's evidence.
