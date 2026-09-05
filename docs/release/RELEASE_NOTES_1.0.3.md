# آية 1.0.3

تحديث تصحيحي يعالج بقاء البطاقة معروضة على الشاشة بلا نهاية عند فتحها
بالنقر على النتوء.

## التغييرات

- **عند النقر على النتوء لإعادة عرض آخر آية أو آخر تنبيه صلاة، كانت
  البطاقة تبقى مفتوحة إلى ما لا نهاية**، ولا تُغلق إلا بنقرة ثانية من
  المستخدم. أصبحت الآن تُغلق نفسها بعد ١٢ ثانية، تمامًا كما تفعل حين تظهر
  تلقائيًا. النقر على البطاقة وهي مفتوحة ما زال يغلقها فورًا.
- إذا أُغلقت البطاقة ثم أُعيد فتحها بالنقر، فإنها تبدأ مهلة ١٢ ثانية كاملة
  من جديد بدل أن تكمل ما تبقى من المهلة السابقة.
- على أجهزة Mac التي لا نتوء فيها: أصبح الشريط العائم يُغلق بحركة انسيابية
  بدل أن يختفي فجأة، ولم يعد يومض بحجم مصغّر قبل أن يتمدد إلى حجمه الكامل.

## ملاحظة

الأسماء العربية المضافة يدويًا للمدن لم تُراجَع بعد من متحدث أصلي. إن لاحظت
اسمًا غير صحيح، من فضلك افتح بلاغًا.

## المتطلبات والتثبيت

- أجهزة Mac بمعالجات Apple Silicon فقط.
- macOS 13 أو أحدث.
- هذا الإصدار موقع بتوقيع ad-hoc، ولا يحمل توقيع Apple Developer ID، وغير
  موثق لدى Apple.
- بعد محاولة الفتح الأولى، استخدم إعدادات النظام > الخصوصية والأمان >
  فتح على أي حال.

---

Ayah 1.0.3 is a bug-fix release for a card that could stay on screen
indefinitely once opened by hand.

## Changes

- **Tapping the notch to re-read the last verse or prayer alert left the card
  open forever.** Every other way a card appeared — a verse becoming due, a
  prayer alert firing, or the menu bar's «إعادة العرض» button — dismissed
  itself after 12 seconds, but a tap on the notch armed no dismissal at all,
  so the card sat over the top of the screen until it was clicked a second
  time. A tap now starts the same 12-second window. Tapping an open card still
  closes it immediately.
- **Closing and re-opening the card by tapping now starts a full fresh 12
  seconds**, rather than inheriting whatever was left of the previous window
  and closing early on someone who has just opened it to read.
- **On Macs without a notch**, the floating bar now animates closed instead of
  vanishing abruptly, and no longer flashes at a small collapsed size before
  growing to full width.

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
