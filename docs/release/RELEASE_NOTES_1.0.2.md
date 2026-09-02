# Ayah 1.0.2

تحديث تصحيحي يركّز على دقة أوقات الصلاة وعرض أسماء المدن بالعربية. تمت
إضافة أسماء عربية لأكثر من ٣٦٠ مدينة كانت تظهر بالحروف اللاتينية، وأصبحت
رسائل الأخطاء عند بدء التشغيل بالعربية.

## التغييرات

- عرض ٣٦٤ مدينة إضافية باسمها العربي بدلًا من الحرف اللاتيني، في دول
  عربية من بينها السعودية والإمارات ومصر والمغرب وتونس والسودان.
- إذا تعذّر التعرّف على المنطقة الزمنية للمدينة المختارة، لن تُعرض أوقات
  الصلاة إطلاقًا بدلًا من حسابها بتوقيت الجهاز — وهو ما كان يعطي أوقاتًا
  خاطئة بصمت.
- توحيد طريقة تحديد الموقع بين ما يُعرض في القائمة وما تُطلق عليه
  التنبيهات، حتى لا يختلفا.
- تعريب رسائل التنبيه التي تظهر عند تعذّر تحميل بيانات القرآن أو الحفظ.
- تحديث قاعدة بيانات المدن من مصدرها (٤٬٦٥٩ مدينة بدل ٤٬٦٥٤).

## ملاحظة

الأسماء العربية المضافة يدويًا لم تُراجَع بعد من متحدث أصلي. إن لاحظت اسمًا
غير صحيح، من فضلك افتح بلاغًا.

## المتطلبات والتثبيت

- أجهزة Mac بمعالجات Apple Silicon فقط.
- macOS 13 أو أحدث.
- هذا الإصدار موقع بتوقيع ad-hoc، ولا يحمل توقيع Apple Developer ID، وغير
  موثق لدى Apple.
- بعد محاولة الفتح الأولى، استخدم إعدادات النظام > الخصوصية والأمان >
  فتح على أي حال.

---

Ayah 1.0.2 is a correctness and polish release, focused on prayer-time
accuracy and on showing city names in Arabic. Over 360 cities that previously
appeared in Latin transliteration now display their Arabic names, and the
app's launch error messages are now in Arabic.

## Changes

- **364 more cities display in Arabic** instead of Latin transliteration,
  across Arabic-speaking countries including Saudi Arabia, the UAE, Egypt,
  Morocco, Tunisia and Sudan. Cities with no Arabic name continue to display
  in Latin, which is correct rather than a gap.
- **A selected city whose stored time zone can no longer be read now shows no
  prayer times at all**, instead of times silently calculated in the Mac's own
  time zone. Showing nothing is a visible prompt to re-pick a city; showing
  wrong times is indistinguishable from correct output.
- **Prayer-time display and prayer alerts now resolve location through one
  shared path**, so the times shown in the popover and the times alerts fire
  at cannot drift apart.
- **Launch failure alerts are in Arabic**, matching the rest of the app —
  previously the three alerts for missing or corrupt Quran and memorization
  data were in English.
- The bundled city database was refreshed from GeoNames (4,659 cities, up
  from 4,654).

## Known limitation

The manually curated Arabic city names have not yet been reviewed by a native
speaker. If you spot an incorrect name, please open an issue.

## Requirements and installation

- Apple Silicon Macs only.
- macOS 13 or later.
- This build uses an ad-hoc signature. It has no Apple Developer ID signature
  and is not notarized by Apple.
- After the first blocked launch, use System Settings > Privacy & Security >
  Open Anyway.
- Verify the DMG against the accompanying SHA-256 file before opening it.
