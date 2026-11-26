// ============================================================
// Edge Function: إرسال إيميل فعلي عند إنشاء إشعار جديد بالنظام
// ============================================================
// تُستدعى تلقائيًا من مشغّل قاعدة البيانات trg_notifications_send_email
// (sql/70_email_trigger.sql) عند كل INSERT بجدول notifications.
// الأسرار المطلوبة: RESEND_API_KEY و FROM_EMAIL فقط.
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
const SITE_BASE_URL = (Deno.env.get("SITE_BASE_URL") || "https://seera-hackathon.vercel.app").replace(/\/+$/, "");
// بلا FROM_EMAIL لا يُرسَل شيء (لا عنوان افتراضي وهمي) — يُضبط بعد توثيق النطاق في Resend
const FROM_EMAIL = Deno.env.get("FROM_EMAIL") || "";
// روابط الشعارين المستضافة (لا base64 — Outlook يحجبها). يمكن تغييرها بالسرّين
// QASSIM_LOGO_URL و CHAIR_LOGO_URL.
// افتراضيًا: الشعاران المنشوران مع صفحات المنصة نفسها
const QASSIM_LOGO_URL = Deno.env.get("QASSIM_LOGO_URL") || `${SITE_BASE_URL}/qassim-logo.png`;
const CHAIR_LOGO_URL = Deno.env.get("CHAIR_LOGO_URL") || `${SITE_BASE_URL}/chair-logo.png`;
// السرّ المشترك مع المشغّل: يُقرأ من app_config تلقائيًا، أو من السرّ WEBHOOK_SECRET إن ضُبط.
const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET") || "";

const escapeText = (s: unknown): string =>
  String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");

// تنسيق نص الإشعار: أسطر، نقاط، روابط قابلة للنقر، وتنسيقات لوحة التحكم.
// (منقول من منصة إنفاذ) — يهرّب النص أولًا ثم يضيف الوسوم.
function formatNotificationBody(str: string): string {
  const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  const styleMarks = (t: string) => t
    .replace(/\*\*(.+?)\*\*/g, '<strong style="font-weight:700">$1</strong>')
    .replace(/\+\+(.+?)\+\+/g, '<span style="font-size:16px;font-weight:700;color:#28323C">$1</span>')
    .replace(/--(.+?)--/g, '<span style="font-size:12.5px;color:#6B7480">$1</span>')
    .replace(/__(.+?)__/g, "<u>$1</u>");
  const fmt = (t: string) => {
    const urls: string[] = [];
    const held = esc(t).replace(/(https?:\/\/[^\s<]+)/g, (u) => { urls.push(u); return `\u0000${urls.length - 1}\u0000`; });
    return styleMarks(held).replace(/\u0000(\d+)\u0000/g, (_, i) =>
      `<a href="${urls[+i]}" style="color:#B8860B;text-decoration:underline;word-break:break-all">${urls[+i]}</a>`);
  };
  let html = "", inList = false;
  for (const raw of (str || "").split("\n")) {
    const line = raw.trim();
    if (line.startsWith("•") || line.startsWith("- ")) {
      if (!inList) { html += '<ul style="margin:8px 0;padding:0 20px 0 0">'; inList = true; }
      html += `<li style="margin:5px 0;line-height:1.8">${fmt(line.replace(/^[•\-]\s*/, ""))}</li>`;
      continue;
    }
    if (inList) { html += "</ul>"; inList = false; }
    if (!line) { html += '<div style="height:10px;line-height:10px;font-size:0">&nbsp;</div>'; continue; }
    html += `<div style="margin:4px 0;line-height:1.85">${fmt(line)}</div>`;
  }
  if (inList) html += "</ul>";
  return html;
}

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
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // السرّ المشترك: من أسرار الدالة إن ضُبط، وإلا من جدول app_config
    // (يضعه مشغّل قاعدة البيانات نفسه، فلا يلزم ضبطه يدويًا)
    let secret = WEBHOOK_SECRET;
    if (!secret) {
      const { data: cfg } = await supabase.from("app_config").select("value").eq("key", "webhook_secret").maybeSingle();
      secret = cfg?.value || "";
    }
    if (!secret || req.headers.get("x-webhook-secret") !== secret) {
      return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
    }
    if (!FROM_EMAIL || !RESEND_API_KEY) {
      return new Response(JSON.stringify({ skipped: "email not configured" }), { status: 200 });
    }

    const payload = await req.json();
    const notificationId = payload?.record?.id;

    if (!notificationId) {
      return new Response(JSON.stringify({ skipped: true }), { status: 200 });
    }

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
      body: dbNotification.body || "",
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
    // جداول لا flexbox — Outlook لا يدعم flexbox
    const logosHtml = (QASSIM_LOGO_URL && CHAIR_LOGO_URL)
      ? `<table role="presentation" cellpadding="0" cellspacing="0" border="0" align="center" style="margin:0 auto 8px;">
           <tr>
             <td style="padding:0 12px;"><img src="${CHAIR_LOGO_URL}" alt="كرسي الشيخ عبدالله بن صالح الراشد الحميد" height="40" style="height:40px; display:block; border:0;"></td>
             <td style="width:1px; background:#E4E6EF;" height="30"></td>
             <td style="padding:0 12px;"><img src="${QASSIM_LOGO_URL}" alt="جامعة القصيم" height="36" style="height:36px; display:block; border:0;"></td>
           </tr>
         </table>
         <span style="color:#6B7480; font-size:11px;">${footerOrgText}</span>`
      : `<span style="color:#28323C; font-size:16px; font-weight:bold;">${footerOrgText}</span>`;

    // توقيع الإيميل الرسمي — جداول فقط ليتوافق مع Outlook
    const siteHost = SITE_BASE_URL.replace(/^https?:\/\//, "").replace(/\/$/, "");
    const signatureHtml = `
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:26px; border-top:1px solid #E4E6EF;">
        <tr><td dir="rtl" style="padding-top:18px; text-align:right; font-family:'IBM Plex Sans Arabic', Tahoma, Arial, sans-serif;">
          <p style="margin:0 0 12px; font-size:13px; color:#3A4450;">مع خالص التحية والتقدير،</p>
          <table role="presentation" cellpadding="0" cellspacing="0" border="0" dir="rtl">
            <tr>
              <td style="width:4px; background:#F7C30D; border-radius:2px;"></td>
              <td dir="rtl" style="padding:2px 14px 2px 0; text-align:right; font-family:'IBM Plex Sans Arabic', Tahoma, Arial, sans-serif;">
                <div style="font-size:11.5px; color:#6B7480; margin-bottom:2px;">اللجنة المنظمة</div>
                <div style="font-size:16px; font-weight:bold; color:#28323C; margin-bottom:6px;">هاكثون السيرة النبوية</div>
                <div style="font-size:12px; color:#3A4450; line-height:1.7;">كرسي الشيخ عبدالله بن صالح الراشد الحميد لخدمة السيرة النبوية</div>
                <div style="font-size:12px; color:#3A4450; line-height:1.7;">جامعة القصيم</div>
                <div style="font-size:11.5px; margin-top:6px;"><a href="${SITE_BASE_URL}" style="color:#B58900; text-decoration:none;" dir="ltr">${siteHost}</a></div>
              </td>
            </tr>
          </table>
        </td></tr>
      </table>`;

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
                <div style="font-size:14px; color:#3A4450; margin:0; font-family:inherit; text-align:right; direction:rtl;">${formatNotificationBody(notification.body)}</div>
                ${bodyExtraHtml}
                <div style="text-align:center; margin-top:20px;">
                  <a href="${SITE_BASE_URL}${escapeText(notification.link || "/registration.html")}"
                     style="display:inline-block; background:#D9A400; color:#1B232B; font-family:inherit;
                            padding:10px 26px; border-radius:8px; text-decoration:none; font-weight:bold;">
                    ${buttonText}
                  </a>
                </div>
                ${signatureHtml}
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
