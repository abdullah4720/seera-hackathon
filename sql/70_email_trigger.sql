-- ============================================================
-- 70: إرسال الإيميل تلقائيًا عند إنشاء أي إشعار (بنفس نهج إنفاذ)
-- مشغّل على جدول notifications يستدعي دالة send-email-notification
-- عبر pg_net. يغني عن إعداد Database Webhook يدويًا.
--  • app_config: جدول إعدادات داخلي، RLS مفعّل بلا سياسات (لا يُقرأ
--    من الواجهة إطلاقًا؛ تقرؤه الدالة بمفتاح الخدمة فقط).
--  • webhook_secret يُولَّد عشوائيًا هنا ولا يغادر قاعدة البيانات.
--  • إن لم تُضبط الإعدادات أو تعطّل الاستدعاء، يُنشأ الإشعار كالمعتاد.
-- قبل التشغيل: استبدل <PROJECT_REF> و<ANON_JWT_KEY> بقيم مشروعك
-- (المفتاح العام legacy anon من Project Settings → API).
-- ============================================================
create extension if not exists pg_net;

create table if not exists public.app_config (
  key text primary key,
  value text
);
alter table public.app_config enable row level security;
revoke all on public.app_config from anon, authenticated;

insert into public.app_config (key, value) values
  ('edge_base_url', 'https://<PROJECT_REF>.supabase.co/functions/v1'),
  ('anon_key', '<ANON_JWT_KEY>'),
  ('webhook_secret', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (key) do nothing;

create or replace function public.trg_notification_email()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_url text; v_key text; v_secret text;
begin
  select value into v_url from public.app_config where key = 'edge_base_url';
  select value into v_key from public.app_config where key = 'anon_key';
  select value into v_secret from public.app_config where key = 'webhook_secret';
  if v_url is null or v_key is null or v_secret is null or v_url like '%<PROJECT_REF>%' then
    return null;
  end if;
  perform net.http_post(
    url := v_url || '/send-email-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_key,
      'x-webhook-secret', v_secret),
    body := jsonb_build_object('type', 'INSERT', 'table', 'notifications', 'record', jsonb_build_object('id', new.id)),
    timeout_milliseconds := 8000
  );
  return null;
exception when others then
  return null;
end;
$$;
revoke execute on function public.trg_notification_email() from public, anon, authenticated;

drop trigger if exists trg_notifications_send_email on public.notifications;
create trigger trg_notifications_send_email
  after insert on public.notifications
  for each row execute function public.trg_notification_email();
