# حذف حساب مستخدم نهائيًا من نظام المصادقة

## ليش ما يصير هذا مباشرة من المتصفح؟
حذف حساب من `auth.users` عملية حسّاسة تحتاج **صلاحية Service Role** — لا يمكن تفعيلها من كود يعمل بمتصفح المستخدم (المفتاح لو انكشف يعطي وصول كامل لكل قاعدة البيانات). لهذا Supabase تفرض إن هذا النوع من العمليات يصير فقط من بيئة خادم آمنة (Edge Function).

## الحل: Edge Function جاهزة (انشرها مرة وحدة، تشتغل دائمًا)

### الخطوة 1: أنشئ ملف الدالة
```bash
supabase functions new delete-user
```
واستبدل محتوى `index.ts` بهذا:

```ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  try {
    const { user_id, requester_token } = await req.json();

    // تحقق إن طالب الحذف admin فعليًا
    const supabaseAuth = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data: { user } } = await supabaseAuth.auth.getUser(requester_token);
    if (!user) return new Response(JSON.stringify({ error: "غير مصرّح" }), { status: 401 });

    const { data: roles } = await supabaseAuth
      .from("user_roles")
      .select("roles(key)")
      .eq("user_id", user.id);
    const isAdmin = roles?.some((r: any) => ["admin", "coordinator"].includes(r.roles?.key));
    if (!isAdmin) return new Response(JSON.stringify({ error: "صلاحيات غير كافية" }), { status: 403 });

    // الحذف الفعلي
    const { error } = await supabaseAuth.auth.admin.deleteUser(user_id);
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 400 });

    return new Response(JSON.stringify({ success: true }), { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
```

### الخطوة 2: انشرها
```bash
supabase functions deploy delete-user --project-ref <project-ref>
```

### الخطوة 3: استدعها من admin.html (أضف هذا الكود لاحقًا لو حبيت)
```js
async function fullyDeleteUser(userId){
  const { data: { session } } = await sb.auth.getSession();
  const res = await fetch("https://<project-ref>.supabase.co/functions/v1/delete-user", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ user_id: userId, requester_token: session.access_token })
  });
  const result = await res.json();
  if(!result.success){ showToast("خطأ: " + result.error, true); return; }
  showToast("تم حذف الحساب نهائيًا");
  renderParticipants();
}
```

## بديل أسرع بدون نشر أي دالة
لو تبي تحذف حساب أو حسابين بس (مو ميزة متكررة)، أسهل طريقة:
**Supabase Dashboard → Authentication → Users → دور على المستخدم → Delete User**
