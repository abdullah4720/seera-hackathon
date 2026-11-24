// ============================================================
// Edge Function: إرسال إيميل فعلي عند إنشاء إشعار جديد بالنظام
// ============================================================
// تُستدعى تلقائيًا عبر Database Webhook عند INSERT بجدول notifications
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// القيم التالية تُقرأ من أسرار المشروع (secrets) مو مكتوبة بالكود —
// لو تغيّر الدومين أو بريد الإرسال مستقبلًا، تحدّثها بأمر واحد بدون
// إعادة نشر الدالة أو لمس الكود إطلاقًا:
//   supabase secrets set SITE_BASE_URL=https://دومينك-الجديد.com --project-ref <ref>
//   supabase secrets set FROM_EMAIL="هاكثون السيرة النبوية <notifications@دومينك.com>" --project-ref <ref>
const SITE_BASE_URL = Deno.env.get("SITE_BASE_URL") || "https://YOUR-SITE.vercel.app";
const FROM_EMAIL = Deno.env.get("FROM_EMAIL") || "هاكثون السيرة النبوية <notifications@YOUR_VERIFIED_DOMAIN.com>";
// روابط الشعارين المستضافة (مو base64 مضمّن) — أغلب برامج البريد (Outlook خصوصًا)
// تحجب أو تشوّه الصور المضمّنة كـ base64 داخل الإيميل، فالرابط المباشر أوثق بكثير.
// ارفع qassim-logo.png وchair-logo.png (مرفقتين بالحزمة) لحاوية تخزين عامة بمشروعك،
// وحط رابطيهما هنا عبر الأسرار:
//   supabase secrets set QASSIM_LOGO_URL=https://xxx.supabase.co/storage/v1/object/public/brand-assets/qassim-logo.png --project-ref <ref>
//   supabase secrets set CHAIR_LOGO_URL=https://xxx.supabase.co/storage/v1/object/public/brand-assets/chair-logo.png --project-ref <ref>
const QASSIM_LOGO_URL = Deno.env.get("QASSIM_LOGO_URL") || "";
const CHAIR_LOGO_URL = Deno.env.get("CHAIR_LOGO_URL") || "";
// سرّ مشترك اختياري بين Database Webhook والدالة. إن ضُبط، تُرفض أي
// استدعاءات لا تحمل الترويسة x-webhook-secret بنفس القيمة:
//   supabase secrets set WEBHOOK_SECRET=<قيمة عشوائية طويلة> --project-ref <ref>
const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET") || "";

const escapeText = (s: unknown): string =>
  String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");

// نفس منطق التنسيق المستخدم بالتحديثات بلوحة التحكم بالضبط
// (**عريض**، ++كبير++، --صغير--، __تسطير__، "- " لقائمة نقطية)
function formatBodyExtra(str: string): string {
  const escapeHtml = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  let s = escapeHtml(str || "");
  s = s.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/\+\+(.+?)\+\+/g, '<span style="font-size:1.3em;font-weight:700">$1</span>');
  s = s.replace(/--(.+?)--/g, '<span style="font-size:0.85em;color:#6B7480">$1</span>');
  s = s.replace(/__(.+?)__/g, "<u>$1</u>");
  const lines = s.split("\n");
  let html = "", inList = false;
  for (const line of lines) {
    if (line.trim().startsWith("- ")) {
      if (!inList) { html += "<ul style='margin:6px 0;padding-right:18px'>"; inList = true; }
      html += `<li>${line.trim().substring(2)}</li>`;
    } else {
      if (inList) { html += "</ul>"; inList = false; }
      html += line + "<br>";
    }
  }
  if (inList) html += "</ul>";
  return html.replace(/<br>$/, "");
}

serve(async (req) => {
  try {
    if (WEBHOOK_SECRET && req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
      return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
    }

    const payload = await req.json();
    const notificationId = payload?.record?.id;

    if (!notificationId) {
      return new Response(JSON.stringify({ skipped: true }), { status: 200 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // لا نثق بمحتوى الطلب: نقرأ الإشعار الفعلي من قاعدة البيانات بمعرّفه،
    // فلا يمكن لأي جهة خارجية إرسال إيميل بعنوان أو نص من اختيارها.
    const { data: dbNotification } = await supabase
      .from("notifications")
      .select("id, user_id, title, body, link")
      .eq("id", notificationId)
      .maybeSingle();

    if (!dbNotification?.user_id) {
      return new Response(JSON.stringify({ skipped: true }), { status: 200 });
    }
    const notification = {
      ...dbNotification,
      title: escapeText(dbNotification.title),
      body: escapeText(dbNotification.body),
    };

    // جلب بريد المستلم
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("email, full_name")
      .eq("id", notification.user_id)
      .single();

    if (profileError || !profile?.email) {
      return new Response(JSON.stringify({ error: "تعذّر جلب بريد المستلم" }), { status: 200 });
    }

    // جلب قالب الإيميل القابل للتخصيص من لوحة التحكم (صف واحد)
    const { data: template } = await supabase
      .from("email_templates")
      .select("greeting_text, body_extra_text, body_alignment, footer_org_text, button_text")
      .limit(1)
      .maybeSingle();

    const greetingText = (template?.greeting_text || "مرحبًا {{name}}،").replace("{{name}}", escapeText(profile.full_name || ""));
    const footerOrgText = template?.footer_org_text || "هاكثون السيرة النبوية — جامعة القصيم";
    const buttonText = template?.button_text || "فتح المنصة";
    const bodyAlignment = template?.body_alignment === "center" ? "center" : "right";
    const bodyExtraHtml = template?.body_extra_text
      ? `<div style="font-size:13px; color:#1B232B; line-height:1.8; margin-top:14px; padding:12px 14px; background:#FEF6DC; border-radius:10px; text-align:${bodyAlignment};">${formatBodyExtra(template.body_extra_text)}</div>`
      : "";
    const logosHtml = (QASSIM_LOGO_URL && CHAIR_LOGO_URL)
      ? `<div style="display:flex; align-items:center; justify-content:center; gap:14px; margin-bottom:6px;">
           <img src="${QASSIM_LOGO_URL}" height="26" style="height:26px;">
           <div style="width:1px;height:20px;background:#E4E6EF;"></div>
           <img src="${CHAIR_LOGO_URL}" height="26" style="height:26px;">
         </div>
         <span style="color:#6B7480; font-size:11px;">${footerOrgText}</span>`
      : `<span style="color:#28323C; font-size:16px; font-weight:bold;">${footerOrgText}</span>`;

    // إرسال الإيميل عبر Resend
    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: profile.email,
        subject: String(dbNotification.title || ""),
        html: `
          <div dir="rtl" style="font-family: 'IBM Plex Sans Arabic', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px; background:#FEFAEC;">
            <!--[if !mso]><!-->
            <style>
              @import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&display=swap');
            </style>
            <!--<![endif]-->
            <div style="border-radius:14px; overflow:hidden; box-shadow:0 2px 10px rgba(27,35,43,.08); border:1px solid #E4E6EF;">
              <div style="background:#ffffff; padding:22px 24px; text-align:center;">
                ${logosHtml}
              </div>
              <div style="height:3px; background:linear-gradient(90deg,#D9A400,#F7C30D,#D9A400);"></div>
              <div style="background:#ffffff; padding:26px 24px; font-family:'IBM Plex Sans Arabic', Tahoma, Arial, sans-serif;">
                <p style="font-size:15px; color:#1B232B; margin:0 0 8px; font-family:inherit;">${greetingText}</p>
                <h2 style="font-size:17px; color:#28323C; margin:0 0 10px; font-family:inherit;">${notification.title}</h2>
                <p style="font-size:14px; color:#6B7480; line-height:1.7; margin:0; font-family:inherit;">${notification.body || ""}</p>
                ${bodyExtraHtml}
                <div style="text-align:center; margin-top:20px;">
                  <a href="${SITE_BASE_URL}${escapeText(notification.link || "/registration.html")}"
                     style="display:inline-block; background:#D9A400; color:#1B232B; font-family:inherit;
                            padding:10px 26px; border-radius:8px; text-decoration:none; font-weight:bold;">
                    ${buttonText}
                  </a>
                </div>
              </div>
              <div style="background:#FEF6DC; padding:14px 24px; text-align:center; font-family:'IBM Plex Sans Arabic', Tahoma, Arial, sans-serif;">
                <span style="font-size:10.5px; color:#6B7480;">© 2026 ${footerOrgText} — جميع الحقوق محفوظة</span>
              </div>
            </div>
          </div>
        `,
      }),
    });

    const result = await emailRes.json();
    return new Response(JSON.stringify({ success: emailRes.ok, result }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 200 });
  }
});
