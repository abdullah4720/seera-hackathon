# منصة هاكثون السيرة النبوية — الحزمة الكاملة

نسخة **مستقلة تمامًا** عن أي منصة أخرى: مشروع Supabase خاص بها، ونشر Vercel خاص بها، وهوية البرنامج (ألوان النشرة + شعارا جامعة القصيم والكرسي) ومساراه:
- رحلة السيرة النبوية
- البصمة الرقمية في السيرة النبوية

مواعيد النشرة: الهاكثون 3–5 ديسمبر 2026 (مضبوطة في الإعدادات الأولية). آخر موعد تسجيل في النشرة (21 نوفمبر) يُدار من زر «التسجيل مفتوح» لكل مسار في لوحة الإدارة.

---

## خطوات الإعداد (بالترتيب)

### 1) مشروع Supabase جديد
أنشئ مشروعًا جديدًا (لا تستخدم مشروعًا قائمًا). احتفظ بـ **Project URL** ومفتاح **publishable (anon)**.

### 2) قاعدة البيانات
من **SQL Editor** شغّل ملفات `sql/` **بالترتيب** (ملف في كل مرة، وتأكد من نجاحه قبل التالي):

1. `01_schema.sql`
2. `02_rls_policies.sql`
3. `03_functions.sql`
4. `04_seed.sql`
5. `05_announcements.sql`
6. `06_auth_trigger.sql`
7. `08_fix_policies.sql`
8. `10_team_rpc.sql`
9. `11_leader_permissions.sql`
10. `12_projects_showcase.sql`
11. `13_mentor_booking_trigger.sql`
12. `14_notifications.sql`
13. `15_attendance_scan.sql`
14. `16_engagement_features.sql`
15. `17_fix_platform_settings.sql`
16. `18_mentor_applications.sql`
17. `19_participant_roster.sql`
18. `20_mentor_track_link.sql`
19. `21_judge_applications.sql`
20. `22_fix_application_update.sql`
21. `23_mentorship_mode_setting.sql`
22. `24_fix_booking_reuse.sql`
23. `25_mentorship_notifications.sql`
24. `26_fix_mentor_booking_insert_rls.sql`
25. `27_fix_user_roles_permissions.sql`
26. `28_fix_approval_and_debug_tool.sql`
27. `29_team_codes.sql`
28. `30_mentorship_advanced.sql`
29. `31_program_schedule.sql`
30. `32_track_capacity_and_active_day.sql`
31. `33_complete_registration_phase.sql`
32. `34_participant_extra_fields.sql`
33. `35_project_files_and_deadline.sql`
34. `36_unify_admin_coordinator_permissions.sql`
35. `37_unify_mentorship_judging_permissions.sql`
36. `38_judging_mentorship_reliability.sql`
37. `39_fix_prep_attendance_permissions.sql`
38. `40_unify_certificates_surveys_permissions.sql`
39. `41_certificate_status_matrix.sql`
40. `42_certificate_role_targeting.sql`
41. `45_add_delete_permissions.sql`
42. `46_visibility_and_enhancements.sql`
43. `47_dynamic_submission_fields.sql`
44. `48_report_images_storage.sql`
45. `50_journey_milestones.sql`
46. `51_track_based_team_codes.sql`
47. `52_team_scoped_announcements.sql`
48. `53_track_details.sql`
49. `54_email_template.sql`
50. `55_email_body_content.sql`
51. `56_email_alignment.sql`
52. `57_smart_join_flow.sql`
53. `58_fix_mentor_profile_visibility.sql`
54. `59_resource_files_library.sql`
55. `60_fix_mentor_visibility_root_cause.sql`
56. `61_facilitator_role.sql`
57. `62_merge_events_into_prep.sql`
58. `63_mentor_rating_criteria.sql`
59. `64_certificate_badges.sql`
60. `65_fix_certificate_eligibility_leak.sql`
61. `66_activity_reasons.sql`
62. `70_email_trigger.sql` — إرسال البريد تلقائيًا عند كل إشعار (استبدل <PROJECT_REF> و<ANON_JWT_KEY> قبل التشغيل). راجع EMAIL_SETUP_GUIDE.md
62ب. `69_import_teams.sql`
62ج. `71_formal_messages.sql` — صياغة رسمية موحّدة لجميع الرسائل + التواريخ بتوقيت مكة + إعادة فحص إغلاق التسجيل
62د. `72_certificate_roles.sql` — ربط الشهادات بالأدوار ومنع إصدار شهادة لا تخص الدور (الفوز للإدارة فقط)
62هـ. `73_certificates_insert_admin_only.sql` — منع إدراج الشهادات مباشرة لغير الإدارة (تعديل RLS بموافقة) — استيراد الفرق من Excel وتفعيل الحسابات المستورَدة (طُبّق على seera-hackathon في 25 نوفمبر)
62و. `74_mentor_presence.sql` — تحضير المرشدين يوميًا وربط المواعيد الظاهرة للفرق بالحضور (طُبّق على seera-hackathon في 26 نوفمبر)
62ز. `75_judging_committees.sql` — لجان التحكيم، اعتماد النتائج وقفل الدرجات، أيام البرنامج حسب المرحلة (منقول من إنفاذ)
62ح. `76_judging_operations.sql` — التوزيع الآلي، ترتيب العرض، الترتيب النهائي، إعلان النتائج، دوال صفحتي النتائج والحفل
62ط. `77_mentorship_controls.sql` — تأكيد انعقاد الجلسة، نافذة الحجز، منع تداخل المواعيد، عروض لوحة الإرشاد الحية
62ي. `78_deliverables.sql` — التسليمات المطلوبة من الفرق (رفع مقصور على مجلد الفريق)
62ك. `79_mentor_status_facilitator_tracks.sql` — تعطيل المرشد عبر دالة خادم، وربط الميسّرين بالمسارات
62ل. `81_admin_password_reset.sql` — إعادة تعيين كلمة المرور من لوحة التحكم بلا إيميل (نافذة 48 ساعة ببريد وجوال متطابقين)
62م. `82_certificate_survey_attendance_rules.sql` — شروط الشهادة (بعد نهاية مرحلة، حد أدنى للجلسات)، نافذة الاستبيان والحضور المطلوب، نافذة التحضير والجلسات المحتسبة، جلسة لكل يوم هاكثون
62ن. `83_slot_rules_fixes.sql` — إغلاق الموعد عند إلغاء المرشد، وفحص أيام الإرشاد عند تغيّر الوقت فقط
62س. `84_survey_stats.sql` — إحصاءات الاستبيانات وتصدير الإجابات
62ش. `85_facilitator_applications.sql` — طلبات الانضمام كميسّر (صفحة `facilitator-apply.html`) مع اعتماد يمنح دور الميسّر فقط، ودالتا `facilitator_roster` و`facilitator_mentors` لقوائم صفحة الميسّر
62ص. `86_facilitator_permissions.sql` — صلاحيات الميسّر المجزّأة (حضور الفرق / تحضير المرشدين / تحضير المحكّمين) عبر `fac_can`، وتحضير المحكّمين، وقصر تسجيل حضور الفرق على المدير والميسّر المخوَّل
62ض. `87_mentor_privacy.sql` — خصوصية المرشدين: دالة `mentor_cards` للبيانات العامة وإزالة سياسة كشف صفوف المرشدين
62ط. `88_rename_facilitator_to_organizer_labels.sql` — «الميسّر» صار «المنظّم» في النصوص الظاهرة (المفتاح الداخلي facilitator باقٍ)
62ظ. `89_judging_like_incubator.sql` — تحكيم بنمط حاضنة ابتكار 5: مسودة ثم إرسال نهائي (`save_evaluation`)، قفل الجولة، اعتذار مشروع، `judge_projects` للمحكّم، وإصلاح `reassign_judge`
63. `68_views_security_invoker.sql` — **مطلوب**: يخضع شاشات العرض الإدارية لسياسات RLS (طُبّق على مشروع seera-hackathon في 24 نوفمبر)
64. `67_seera_submission_fields.sql` — **اختياري**: فقط إن شغّلت نسخة قديمة من الملف 47 (حقول السجل التجاري/براءة الاختراع). النسخة الحالية من 47 تتضمن الحقول الصحيحة.

> الأرقام الناقصة (07، 09، 43، 44، 49) محذوفة عمدًا: ملفات تشخيصية أو خاصة ببيانات منصة سابقة.
> الملف 30 يحتاج تفعيل إضافة **pg_cron** من Database → Extensions قبل تشغيله.

### 3) ربط الموقع بمشروعك
افتح `site/config.js` وضع القيمتين:
```js
SUPABASE_URL: "https://<project-ref>.supabase.co",
SUPABASE_ANON_KEY: "<publishable key>"
```
هذا الملف الوحيد المطلوب تعديله. **لا تضع مفتاح service_role في أي ملف من الموقع.**

### 4) أول حساب إداري
أنشئ مستخدمًا من Authentication → Add user، ثم:
```sql
insert into public.user_roles (user_id, role_id)
select 'USER_ID_من_Authentication', id from public.roles where key = 'admin';
```

### 5) المصادقة
Authentication → Providers → Email: عطّل **Confirm email** إن أردت تسجيلًا فوريًا (راجع `EMAIL_SETUP_GUIDE.md` لإرسال الإيميلات).

### 6) البريد (اختياري)
انشر دالة `supabase/functions/send-email-notification` واتبع `EMAIL_SETUP_GUIDE.md`. أسرار الدالة: `RESEND_API_KEY` و`SITE_BASE_URL` و`FROM_EMAIL` و`QASSIM_LOGO_URL` و`CHAIR_LOGO_URL` و`WEBHOOK_SECRET` (وأضف الترويسة `x-webhook-secret` بنفس القيمة في الـ Webhook) (الشعاران في جذر الحزمة: `qassim-logo.png` و`chair-logo.png`).

### 7) نشر الموقع (Vercel)
ارفع محتويات `site/` كاملة (بما فيها `config.js` و`vercel.json`) كمشروع **جديد** باسم مستقل. ملف `vercel.json` يضيف ترويسات أمان أساسية ويمنع تخزين `config.js` مؤقتًا، ولا يغيّر أي شيء في التصميم.

### 8) ضبط البرنامج من لوحة الإدارة
المسارات والسعة وفتح/إغلاق التسجيل، التواريخ (التسجيل، الإرشاد، التحكيم، التسليم)، معايير التحكيم (1–5)، نصوص الشهادات، قالب الإيميل.

### 9) اختبار قبل الفتح
حساب تجريبي لكل دور (مشارك، مرشد، محكّم، إدارة)، ثم مرّ على: تسجيل ← فريق ← حجز إرشاد ← تسليم ← تحكيم ← شهادة. جرّب `scan.html` من جوال حقيقي قبل الفعالية.

---

## ما تغيّر عن المنصة الأصلية
- هوية النشرة (خلفية رمادية داكنة #28323C، ذهبي #F7C30D، كريمي #FFFAE7) وشعارا جامعة القصيم وكرسي الشيخ عبدالله بن صالح الراشد الحميد.
- إعدادات Supabase في ملف واحد `config.js` بدل تكرارها في كل صفحة، وهي **فارغة** عمدًا حتى لا ترتبط الصفحات بأي قاعدة بيانات أخرى.
- مفاتيح التخزين المحلي ورمز QR بمسمّى خاص (`seera-` / `SEERA-USER:`) فلا تتداخل مع أي منصة أخرى على المتصفح نفسه.
- بيانات أولية جديدة: مساران، ومعايير تحكيم من 5 درجات، وتخصصات المرشدين/المحكّمين، والاستبيان.
- تقرير النتائج النهائي (PPTX) مُعاد صياغته بمحتوى البرنامج.

## ملاحظات
- الشعاران مقصوصان من النشرة (دقة محدودة). للحصول على أفضل جودة استبدلهما بملفات SVG/PNG الأصلية: `chair-logo.png` و`qassim-logo.png` وأعد تضمينها في الصفحات.
- خط النشرة غير متوفر كخط ويب، والمنصة تستخدم IBM Plex Sans Arabic.

## سجل المراجعة (24 نوفمبر 2026)
- **أمان (XSS):** أسماء المشاركين والفرق داخل أزرار `onclick` في لوحات الإدارة والإرشاد والتحكيم والمشارك صارت تُمرَّر عبر `jsArg()` بدل `JSON.stringify` وحده، فلا يمكن لاسم يحوي `'` تنفيذ كود في متصفح الإدارة. اسم المستخدم في الشريط الجانبي للوحة الإدارة صار مُهرَّبًا.
- **أمان (دالة البريد):** الدالة تقرأ الإشعار من قاعدة البيانات بمعرّفه ولا تثق بمحتوى الطلب، وتهرّب العنوان والنص واسم المستلم، وتدعم سرًّا مشتركًا `WEBHOOK_SECRET`.
- **المحتوى:** حقول نموذج التسليم (الملف 47) استُبدلت بحقول تناسب الهاكثون (نوع المنتج الرقمي، محطة السيرة، الفئة المستهدفة، المصادر، الأثر، النموذج الأولي) بدل حقول السجل التجاري وبراءة الاختراع، مع ملف 67 لتطبيق ذلك على قاعدة قائمة.
- **النشر:** إضافة `site/vercel.json`.
- لم تُمسّ سياسات RLS ولا التصميم.
- **أمان (Views):** الملف 68 يمنع قراءة شاشات العرض الإدارية (أسماء وإيميلات المشاركين ودرجات التحكيم) بالمفتاح العام.
- **استيراد الفرق (الملف 69 + لوحة الإدارة ← «استيراد الفرق» + تبويب «تفعيل أول مرة» في التسجيل):** منقول من منصة إنفاذ (كود فقط) ومكيَّف للسيرة. حالة «بانتظار التفعيل» تُعطى فقط للحسابات التي أنشأها الاستيراد، فلا يمكن تفعيل حساب سجّل صاحبه بنفسه.
- **البريد (الملف 70 + الدالة):** مشغّل قاعدة بيانات يستدعي الدالة بسرّ مولّد داخليًا، بنفس نهج إنفاذ، مع تنسيق الأسطر والروابط وشعارين بجداول متوافقة مع Outlook. يتبقى فقط RESEND_API_KEY وFROM_EMAIL.
- **الرسائل (71):** فصحى رسمية موحّدة، مواعيد الإرشاد بالتاريخ والوقت بتوقيت مكة (كان التذكير متأخرًا 3 ساعات)، وإعادة فحصي إغلاق التسجيل وسعة المسار.
- **الشهادات (72، 73):** كل نوع مرتبط بدوره؛ «شهادة الفوز» للإدارة فقط؛ ولا يمكن إدراج شهادة مباشرة دون المرور بشروط الإصدار.
