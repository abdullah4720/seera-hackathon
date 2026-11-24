# دليل ربط البريد الإلكتروني — هاكثون السيرة النبوية

المنصة فيها **نوعان مختلفان** من الإيميلات، كل وحدة تحتاج إعداد منفصل:

---

## النوع 1: إيميلات المصادقة (Auth Emails)
مثال: استعادة كلمة المرور (شغّالة عندك أصلًا كوظيفة، بس تحتاج SMTP حقيقي عشان توصل فعليًا).

**الحالة الحالية:** Supabase تستخدم خدمة بريد داخلية محدودة جدًا (لأغراض الاختبار بس — تُرسل عدد قليل جدًا يوميًا وممكن توصل إلى Spam).

### الإعداد (5 دقائق، من لوحة Supabase مباشرة):
1. **Project Settings → Authentication → SMTP Settings**
2. فعّل **Enable Custom SMTP**
3. عبّي بيانات مزوّد SMTP عندك (أمثلة شائعة: **Resend**, **SendGrid**, **Mailgun**, أو حتى بريد Outlook/Gmail مؤسسي بجامعة القصيم لو متاح)
4. **Sender email**: مثلاً `noreply@seera.qu.edu.sa` أو أي بريد تملكه
5. احفظ واختبر بإرسال "نسيت كلمة المرور" من صفحة التسجيل

---

## النوع 2: إشعارات فعلية بالتحديثات (Transactional Emails)
مثال: "تم نشر تحديث جديد"، "تم تأكيد حجز إرشادك"، "تم اعتماد شهادتك" — نفس أسلوب صيف الابتكار بالضبط.

### المتطلبات:
- حساب مجاني بـ **[Resend](https://resend.com)** (يعطيك 3000 إيميل مجانًا شهريًا)
- نطاق بريد تملكه ومُوثّق بـ Resend (أو استخدم نطاقهم التجريبي للاختبار الأولي)
- **Supabase CLI** مثبّت على جهازك لنشر الدالة

### خطوات النشر:

**1) أضف مفتاح Resend لمشروعك بـ Supabase:**
```bash
supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxx --project-ref <project-ref>
```

**أضف كمان (مهم — خصوصًا لو بتغيّر الدومين قريبًا):**
```bash
supabase secrets set SITE_BASE_URL=https://YOUR-SITE.vercel.app --project-ref <project-ref>
supabase secrets set FROM_EMAIL="هاكثون السيرة النبوية <notifications@دومينك.com>" --project-ref <project-ref>
```
هذي القيم **مو مكتوبة بالكود** — لو غيّرت الدومين لاحقًا، بس تعيد نفس الأمر بالرابط الجديد، بدون أي تعديل على الدالة نفسها ولا إعادة نشر لملفات الكود.

**2) (اختياري لكن موصى فيه) أضف شعاري الجامعة والسيرة النبوية لهيدر الإيميل:**

الملفان `qassim-logo.png` و`chair-logo.png` مرفقان بجذر الحزمة. ارفعهم لحاوية تخزين عامة:

1. Supabase Dashboard → Storage → أنشئ حاوية جديدة اسمها `brand-assets` (فعّل "Public bucket")
2. ارفع الملفين فيها
3. انسخ الرابط العام لكل ملف (زر "Copy URL" بجانب كل ملف)
4. فعّلهم كأسرار:
```bash
supabase secrets set QASSIM_LOGO_URL=https://xxxxx.supabase.co/storage/v1/object/public/brand-assets/qassim-logo.png --project-ref <project-ref>
supabase secrets set CHAIR_LOGO_URL=https://xxxxx.supabase.co/storage/v1/object/public/brand-assets/chair-logo.png --project-ref <project-ref>
```

**ليش رابط مو صورة مضمّنة (base64)؟** أغلب برامج البريد (خصوصًا Outlook) تحجب أو تشوّه الصور المضمّنة داخل نص الإيميل لأسباب أمنية — الرابط المباشر لصورة مستضافة أوثق وأضمن ظهورًا بكل برامج البريد.

لو ما فعّلت هالخطوة، الهيدر يبان بنص "هاكثون السيرة النبوية" بدل الشعارين — كل شي ثاني يشتغل عادي.

**2) اضبط أسرار الدالة (بدون تعديل الكود):**
```bash
supabase secrets set FROM_EMAIL="هاكثون السيرة النبوية <notifications@نطاقك-الموثق.com>" --project-ref <project-ref>
supabase secrets set SITE_BASE_URL=https://رابط-المنصة --project-ref <project-ref>
supabase secrets set WEBHOOK_SECRET=<قيمة عشوائية طويلة> --project-ref <project-ref>
```
`WEBHOOK_SECRET` يمنع أي جهة غير الـ Webhook من استدعاء الدالة. (الدالة أصلًا تقرأ نص الإشعار من قاعدة البيانات ولا تثق بمحتوى الطلب.)

**3) انشر الدالة:**
```bash
supabase functions deploy send-email-notification --project-ref <project-ref>
```

**4) اربطها بجدول الإشعارات (Database Webhook) — من لوحة Supabase:**
1. **Database → Webhooks → Create a new hook**
2. **Table**: `notifications`
3. **Events**: `Insert` فقط
4. **Type**: `Supabase Edge Functions`
5. اختر الدالة `send-email-notification`
6. في **HTTP Headers** أضف ترويسة: `x-webhook-secret` بنفس قيمة `WEBHOOK_SECRET`
7. احفظ وفعّل

**النتيجة:** أي إشعار يُنشأ بالنظام (تحديث جديد، تأكيد إرشاد، اعتماد شهادة، أي شي من الـ triggers الموجودة أصلًا بالمنصة) **يُرسل إيميل فعلي تلقائيًا** لصاحبه، بالتوازي مع ظهوره بجرس الإشعارات داخل المنصة — بدون أي تعديل إضافي على الكود، لأن كل مسارات الإشعارات موجودة أصلًا (حجز إرشاد، إعلانات، اعتماد شهادات، إلخ).

---

## ملاحظة مهمة
لو تبي تبدأ بسيط بدون التعقيد الكامل لـ Resend، **ابدأ بالنوع 1 بس** (SMTP لصفحة استعادة كلمة المرور) — هذا أهم من ناحية عملية فورية، والنوع 2 تقدر تضيفه لاحقًا بأي وقت بدون ما يأثر على أي شي شغّال حاليًا.
