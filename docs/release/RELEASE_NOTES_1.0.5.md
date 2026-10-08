# آية 1.0.5

فتح البطاقة بمجرد تمرير المؤشر، وزر «آية» صغير للأجهزة التي لا تحتوي على نتوء، مع إصلاحات تجعل التطبيق يستمر في العمل عند تعذّر قراءة بعض البيانات.

## الجديد

- **الفتح عند تمرير المؤشر:** ضع المؤشر على النتوء فتظهر البطاقة، وأبعده فتُغلق. إذا أغلقتها بالنقر فلن تُفتح مجددًا حتى تُبعد المؤشر ثم تعيده. يمكن إيقاف ذلك من الإعدادات > عام > «الفتح عند تمرير المؤشر».
- **زر «آية» على الشاشات دون نتوء:** زر صغير أسفل شريط القوائم يُفتح منه آخر محتوى في أي وقت. يمكن إيقافه من الإعدادات > عام > «إظهار زر آية أعلى الشاشات بدون نتوء»، فتعود البطاقة العائمة كما كانت.
- لا يفتح التمرير بطاقة فارغة إذا لم يكن هناك محتوى بعد.

## الإصلاحات

- **استمرار عرض الآيات عند تعذّر تحميل بيانات الحفظ.** كان عرض الآيات يتوقف طوال الجلسة؛ أصبحت الآيات تُعرض من القرآن كاملًا، وتوضّح رسالة التنبيه ذلك.
- لم تعد المساحة المحيطة بالنتوء تعترض النقرات حين تكون البطاقة مطوية؛ أصبحت النافذة تتقلص إلى حجم النتوء.
- **الموقع الحالي:** يُرفض الموقع القديم (أكثر من ٥ دقائق) أو غير الدقيق (أكثر من ٥ كم) بدل حفظه، ويُحفظ وقت القياس ودقته. وأصبح لديك دقيقتان للرد على نافذة إذن الموقع بدل ٣٠ ثانية.
- **تنبيهات الصلاة في المناطق القريبة من القطبين:** إذا تعذّر حساب الأوقات في يوم ما، يعيد التطبيق المحاولة في اليوم التالي تلقائيًا دون الحاجة لإعادة تشغيله.
- إذا تلفت الإعدادات المحفوظة، يُحتفظ بنسخة منها قبل استبدالها بدل فقدانها.
- رسالة تعذّر قراءة مجموعات الحفظ لم تعد تختفي بسبب نجاح حفظ آخر غير مرتبط بها.

## المتطلبات والتثبيت

- أجهزة Mac بمعالجات Apple Silicon، ونظام macOS 13 أو أحدث.
- توقيع ad-hoc مع hardened runtime، دون Developer ID أو توثيق Apple.
- بعد محاولة الفتح الأولى، استخدم إعدادات النظام > الخصوصية والأمان > فتح على أي حال.
- تحقق من ملف DMG باستخدام ملف SHA-256 المرفق.

## حدود التحقق

نجحت اختبارات الحزمة (146) واختبارات التطبيق (31) والبناء على CI. جُرّب الفتح عند التمرير وحالة تلف بيانات الحفظ على جهاز فعلي بنتوء. لم يُجرَّب زر «آية» على شاشة فعلية دون نتوء، ولا VoiceOver، ولا الانتقال عند إغلاق غطاء MacBook، ولا تنزيل معزول حديث عبر Gatekeeper، ولم تُراجَع الأسماء العربية المنسّقة يدويًا للمدن من متحدث أصلي.

---

# Ayah 1.0.5

Open-on-hover, a small «آية» tab for Macs without a notch, and fixes that keep the app working when some data can't be read.

## New

- **Open on hover:** rest the pointer on the notch to show the card; move away to close it. After closing it with a click, it won't reopen until the pointer leaves and returns. Toggle in Settings > General.
- **«آية» tab on non-notch displays:** a small tab below the menu bar opens the latest content at any time. Turning it off restores the previous sliding floating card.
- Hover never opens an empty card when there is no content yet.

## Fixes

- **Verses keep showing when memorization data fails to load.** Previously verse display stopped for the whole session; verses now come from the whole Quran, and the warning says so.
- The area around the notch no longer intercepts clicks while the card is collapsed; the window shrinks to the notch.
- **Current location:** stale (>5 min) or inaccurate (>5 km) fixes are rejected rather than saved, and measurement time and accuracy are stored. The permission dialog now allows two minutes instead of 30 seconds.
- **Prayer alerts near the poles:** when a day has no calculable prayer times, the app retries the next day without a restart.
- A corrupted settings blob is preserved in a recovery copy instead of being lost.
- A memorization read-error message is no longer cleared by an unrelated successful save.

## Requirements and installation

- Apple Silicon; macOS 13 or later.
- Ad-hoc signed with hardened runtime; no Apple Developer ID signature or Apple notarization.
- After the first blocked launch, use System Settings > Privacy & Security > Open Anyway.
- Verify the DMG using the accompanying SHA-256 file.

## Verification limits

Package (146) and app (31) tests and the CI build pass. Hover and the corrupted-memorization case were exercised on a physical notched Mac. The «آية» tab on a physical non-notch display, VoiceOver, clamshell transitions, a fresh quarantined Gatekeeper download, and native-speaker review of curated Arabic city names remain unverified.
