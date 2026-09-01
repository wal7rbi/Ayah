# Ayah 1.0.1

يضيف هذا التحديث قسم **آخر ما ظهر** في قائمة آية، مع إمكانية إعادة
عرض آخر آية أو تنبيه صلاة. يبقى السجل محفوظًا محليًا بعد إعادة تشغيل
التطبيق، ولا يحتاج إلى الإنترنت.

## التغييرات

- عرض آخر محتوى ظهر في قائمة شريط macOS.
- زر **إعادة العرض** لإظهار المحتوى مرة أخرى.
- حفظ معرفات الآيات وبيانات تنبيه الصلاة فقط، من دون تكرار تخزين نص
  القرآن.
- اختبارات جديدة للحفظ، الاستعادة، التحقق من البيانات، واستبدال السجل
  السابق.

## المتطلبات والتثبيت

- أجهزة Mac بمعالجات Apple Silicon فقط.
- macOS 13 أو أحدث.
- هذا الإصدار موقع بتوقيع ad-hoc، ولا يحمل توقيع Apple Developer ID، وغير
  موثق لدى Apple.
- بعد محاولة الفتح الأولى، استخدم إعدادات النظام > الخصوصية والأمان >
  فتح على أي حال.

---

Ayah 1.0.1 adds a persistent **Last Shown** section to the menu-bar popover,
with replay for the most recent verse or prayer alert. The record remains
available after relaunch and is stored entirely on the Mac.

## Changes

- Display the most recently shown content in the menu-bar popover.
- Replay the last verse or prayer alert through the existing presentation.
- Persist identifiers and prayer-alert metadata without duplicating Quran text.
- Add tests for saving, restoration, validation, replacement, and malformed data.

## Requirements and installation

- Apple Silicon Macs only.
- macOS 13 or later.
- This build uses an ad-hoc signature. It has no Apple Developer ID signature
  and is not notarized by Apple.
- After the first blocked launch, use System Settings > Privacy & Security >
  Open Anyway.
- Verify the DMG against the accompanying SHA-256 file before opening it.
