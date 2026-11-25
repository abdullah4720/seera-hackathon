/* ============================================================
   شهادات هاكثون السيرة النبوية — تصميم موحّد لكل الصفحات
   (المشارك، المرشد، المحكّم). مبني على تخطيط شهادات ابتكار إنفاذ
   بهوية السيرة: رمادي داكن #28323C، ذهبي #F7C30D، كريمي #FFFAE7.
   يتطلب: html2canvas و jsPDF محمّلين، ومتغيّر sb (عميل Supabase).
   النصوص العامة قابلة للتعديل من platform_settings:
     cert_brand_ar, cert_brand_en, cert_intro,
     cert_signature_label, cert_signature_name, cert_body_scale
   ============================================================ */
(function(){
  const C = { dark: "#28323C", gold: "#F7C30D", goldDeep: "#B8860B", cream: "#FFFAE7", ink: "#3A4450", muted: "#6B7480" };

  const esc = (s) => String(s ?? "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;").replace(/'/g,"&#39;");

  // الأرقام داخل جملة عربية قد يختلط ترتيبها؛ نعزل كل تتابع رقمي بـ<bdi>
  const isolateNums = (escaped) => String(escaped).replace(/(\d+(?:[\-\/:.]\d+)*)/g, "<bdi>$1</bdi>");

  // تنسيق آمن: رموز تُحوَّل بعد الهروب (لا وسوم HTML مباشرة)
  const RICH = [
    { re: /\*\*([\s\S]+?)\*\*/g, wrap: '<b style="font-weight:800">$1</b>' },
    { re: /__([\s\S]+?)__/g,     wrap: "<u>$1</u>" },
    { re: /\+\+([\s\S]+?)\+\+/g, wrap: '<span style="font-size:1.28em">$1</span>' },
    { re: /~~([\s\S]+?)~~/g,     wrap: '<span style="font-size:.82em">$1</span>' },
    { re: /%%([\s\S]+?)%%/g,     wrap: `<span style="color:${C.goldDeep}">$1</span>` },
  ];
  const line = (raw) => { let o = isolateNums(esc(raw)); RICH.forEach(r => { o = o.replace(r.re, r.wrap); }); return o; };

  const certDate = (d) => {
    if(!d) return "";
    try{ return new Date(d).toLocaleDateString("ar-SA-u-ca-gregory-nu-latn", { year:"numeric", month:"long", day:"numeric" }); }
    catch(e){ return new Date(d).toLocaleDateString("ar"); }
  };

  // نص افتراضي لكل نوع إن لم يُكتب نص في لوحة الإدارة
  const DEFAULT_TEXT = {
    participant: "قد شارك في هاكثون السيرة النبوية، المنعقد خلال الفترة من 3 إلى 5 ديسمبر 2026م، واستوفى متطلبات المشاركة بنجاح.\nمتمنّين له دوام التوفيق والسداد.",
    mentor: "وذلك تقديرًا لإسهامه المتميّز في إرشاد الفرق المشاركة في هاكثون السيرة النبوية، المنعقد خلال الفترة من 3 إلى 5 ديسمبر 2026م.\nشاكرين له جهوده المباركة وعطاءه.",
    judge: "وذلك تقديرًا لإسهامه القيّم في تحكيم مشاريع هاكثون السيرة النبوية، المنعقد خلال الفترة من 3 إلى 5 ديسمبر 2026م.\nشاكرين له جهوده المباركة وعطاءه.",
    admin: "وذلك لتحقيقه مركزًا متقدّمًا في هاكثون السيرة النبوية، المنعقد خلال الفترة من 3 إلى 5 ديسمبر 2026م.\nمتمنّين له دوام التميّز والتوفيق.",
  };

  let shared = null;
  async function loadShared(){
    if(shared) return shared;
    const keys = ["cert_brand_ar","cert_brand_en","cert_intro","cert_signature_label","cert_signature_name","cert_body_scale"];
    shared = {};
    try{
      const { data } = await sb.from("platform_settings").select("key,value").in("key", keys);
      (data||[]).forEach(r => { if(r.value) shared[r.key] = r.value; });
    }catch(e){}
    return shared;
  }

  function markup({ name, typeName, text, roleKey, code, date }){
    const S = shared || {};
    const brandAr  = S.cert_brand_ar  || "هاكثون السيرة النبوية";
    const brandEn  = S.cert_brand_en  || "Prophetic Seerah Hackathon";
    const intro    = S.cert_intro     || "يشهد كرسي الشيخ عبدالله بن صالح الراشد الحميد لخدمة السيرة النبوية بجامعة القصيم بأنّ";
    const sigLabel = S.cert_signature_label || "مع خالص الشكر والتقدير،";
    const sigName  = S.cert_signature_name  || "اللجنة المنظمة لهاكثون السيرة النبوية";
    const scale    = parseFloat(S.cert_body_scale) || 1;
    const fill = (t) => String(t || "")
      .replace(/\{\{name\}\}/g, name).replace(/\{\{type\}\}/g, typeName)
      .replace(/\{\{date\}\}/g, certDate(date)).replace(/\{\{code\}\}/g, code || "");
    const bodyLines = fill(text || DEFAULT_TEXT[roleKey] || "قد أتمّ متطلبات {{type}} في هاكثون السيرة النبوية بنجاح.")
      .split(/\r?\n/).map(s => s.trim()).filter(Boolean);
    const fz = (em) => (em * scale).toFixed(3) + "em";
    const base = location.origin + location.pathname.replace(/[^/]*$/, "");

    return `
    <div id="cert-canvas" style="font-size:11px; width:87.5em; min-height:54.7em; background:#fff; border:0.375em solid ${C.gold}; display:flex; flex-direction:column; font-family:'IBM Plex Sans Arabic',sans-serif; direction:rtl; box-sizing:border-box;">

      <div style="height:7.6em; display:flex; align-items:center; justify-content:center; flex-shrink:0;">
        <img src="${base}qassim-logo.png" alt="" style="height:3.875em; width:auto; max-width:20em; object-fit:contain; margin:0 2em;">
        <div style="width:1px; height:3.25em; background:#E4E6EF; flex-shrink:0;"></div>
        <img src="${base}chair-logo.png" alt="" style="height:4.2em; width:auto; max-width:22em; object-fit:contain; margin:0 2em;">
      </div>

      <div style="height:8.9em; background:${C.dark}; position:relative; overflow:hidden; display:flex; align-items:center; justify-content:flex-start; padding:0 4.375em; flex-shrink:0;">
        <div style="position:absolute; top:-120%; height:340%; width:0.4375em; left:4.625em;  background:${C.gold}; opacity:.3;  transform:rotate(24deg);"></div>
        <div style="position:absolute; top:-120%; height:340%; width:1.625em;  left:8.125em;  background:${C.gold}; opacity:.95; transform:rotate(24deg);"></div>
        <div style="position:absolute; top:-120%; height:340%; width:0.8125em; left:11.625em; background:${C.gold}; opacity:.45; transform:rotate(24deg);"></div>
        <div style="position:relative; z-index:2; text-align:right; max-width:60%;">
          <div style="font-size:3.125em; font-weight:800; color:${C.gold}; line-height:1.15;">${line(brandAr)}</div>
          <div style="font-size:1.45em; font-weight:600; color:${C.cream}; letter-spacing:.03em; margin-top:.2em; direction:ltr; text-align:right;">${esc(brandEn)}</div>
        </div>
      </div>

      <div style="flex:1; display:flex; flex-direction:column; align-items:center; text-align:center; padding:1.9em 6.875em 1em;">
        <div style="font-size:2.7em; font-weight:800; color:${C.dark}; margin-bottom:.75em; line-height:1.25;">${line(typeName)}</div>
        <div style="width:7.375em; height:0.3125em; background:${C.gold}; border-radius:3px; margin-bottom:1.6em;"></div>
        <div style="font-size:${fz(1.34)}; color:${C.ink}; line-height:1.9; margin-bottom:.3em;">${line(fill(intro))}</div>
        <div style="font-size:${fz(1.95)}; font-weight:800; color:${C.dark}; margin:.6em 0 .8em;">${line(name)}</div>
        ${bodyLines.map(l => `<div style="font-size:${fz(1.34)}; color:${C.ink}; line-height:1.9; margin-bottom:.5em;">${line(l)}</div>`).join("")}
        <div style="width:100%; height:2px; background:${C.gold}; opacity:.6; margin:1.6em 0 0;"></div>
      </div>

      <div style="display:flex; justify-content:space-between; align-items:flex-end; flex-shrink:0; padding:1.2em 6.875em 1.5em; font-size:1em; color:${C.muted};">
        <div style="min-width:15.625em;">رمز التحقق: <bdi>${esc(code || "—")}</bdi></div>
        <div style="text-align:center; line-height:1.85;">${line(sigLabel)}<b style="display:block; font-size:1.25em; color:${C.dark}; font-weight:700; margin-top:.25em;">${line(sigName)}</b></div>
        <div style="min-width:15.625em; text-align:left;">${isolateNums(esc(certDate(date)))}</div>
      </div>
    </div>`;
  }

  // البطاقة بعرض ثابت بالـem؛ نصغّر font-size لتتّسع للشاشة عرضًا وارتفاعًا
  function fit(){
    const el = document.getElementById("cert-canvas");
    if(!el) return;
    const availW = Math.min(window.innerWidth - 60, 1180);
    const availH = window.innerHeight - 150;
    el.style.fontSize = Math.max(4, Math.min(11, availW / 87.5, availH / 61.875)) + "px";
  }

  async function download(personName){
    const btn = document.getElementById("cert-download-btn");
    const el = document.getElementById("cert-canvas");
    const original = btn.textContent, prevFs = el.style.fontSize;
    btn.textContent = "جارٍ التحضير..."; btn.disabled = true;
    try{
      if(typeof html2canvas === "undefined" || !window.jspdf) throw new Error("لم تُحمَّل مكتبة التحويل — تحقق من الاتصال وأعد المحاولة");
      el.style.fontSize = "11px";                       // الحجم الكامل لأعلى دقة
      if(document.fonts && document.fonts.ready) await document.fonts.ready;
      const canvas = await html2canvas(el, { scale: 3, backgroundColor: "#ffffff", useCORS: true });
      const { jsPDF } = window.jspdf;
      const pdf = new jsPDF({ orientation: "landscape", unit: "px", format: [canvas.width, canvas.height] });
      pdf.addImage(canvas.toDataURL("image/png"), "PNG", 0, 0, canvas.width, canvas.height);
      pdf.save(`شهادة-${personName || "هاكثون-السيرة"}.pdf`);
    }catch(err){
      alert("تعذّر توليد ملف PDF: " + err.message);
    }finally{
      el.style.fontSize = prevFs; fit();
      btn.textContent = original; btn.disabled = false;
    }
  }

  async function open(data){
    await loadShared();
    document.getElementById("cert-overlay")?.remove();
    const overlay = document.createElement("div");
    overlay.id = "cert-overlay";
    overlay.style.cssText = "position:fixed;inset:0;background:rgba(27,35,43,.85);z-index:500;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:20px;overflow:auto";
    overlay.innerHTML = `
      <div>${markup(data)}</div>
      <div style="display:flex; gap:10px; justify-content:center; margin-top:20px">
        <button class="btn btn-primary" id="cert-download-btn" style="width:auto">⬇ تحميل PDF</button>
        <button class="btn btn-outline" style="width:auto;background:#fff" id="cert-close-btn">إغلاق</button>
      </div>`;
    document.body.appendChild(overlay);
    overlay.querySelector("#cert-download-btn").addEventListener("click", () => download(data.name));
    overlay.querySelector("#cert-close-btn").addEventListener("click", () => overlay.remove());
    fit();
  }

  window.addEventListener("resize", fit);
  window.SeeraCert = { open, markup, loadShared };
})();
