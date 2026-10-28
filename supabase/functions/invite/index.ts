// Stallboken Eggebyberg – inbjudningar (Supabase Edge Function "invite")
// Bara admin får bjuda in eller ta bort ryttare. Den hemliga nyckeln finns
// bara här på servern och når aldrig webbläsaren.
import { createClient } from "npm:@supabase/supabase-js@2.117.3";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Fel anrop." }, 405);

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    // Vem anropar?
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const { data: who, error: whoErr } = await admin.auth.getUser(token);
    if (whoErr || !who?.user) return json({ error: "Du är inte inloggad. Logga in igen." }, 401);

    const { data: prof } = await admin.from("profiles").select("is_admin").eq("id", who.user.id).maybeSingle();
    if (!prof?.is_admin) return json({ error: "Bara den som sköter stallboken kan bjuda in." }, 403);

    const body = await req.json().catch(() => ({}));

    // ---- Bjud in ----
    if (body.action === "invite") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const name = String(body.name ?? "").trim().slice(0, 40);
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "Det där ser inte ut som en e-postadress." }, 400);

      const { error } = await admin.auth.admin.inviteUserByEmail(email, {
        data: name ? { name } : {},
        redirectTo: typeof body.redirectTo === "string" ? body.redirectTo : undefined,
      });
      if (error) {
        const m = error.message || "";
        if (/already been registered|already registered|exists/i.test(m))
          return json({ error: "Den adressen finns redan i Stallboken. Personen kan använda Glömt lösenord." }, 400);
        if (/rate limit/i.test(m))
          return json({ error: "För många mejl på kort tid. Vänta en stund och försök igen." }, 429);
        return json({ error: "Inbjudan kunde inte skickas: " + m }, 400);
      }
      return json({ ok: true });
    }

    // ---- Ta bort ----
    if (body.action === "remove") {
      const userId = String(body.userId ?? "");
      if (!userId) return json({ error: "Ingen person vald." }, 400);
      if (userId === who.user.id) return json({ error: "Du kan inte ta bort dig själv." }, 400);
      const { data: target } = await admin.from("profiles").select("is_admin").eq("id", userId).maybeSingle();
      if (target?.is_admin) return json({ error: "En admin kan inte tas bort här." }, 400);
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) return json({ error: "Kunde inte ta bort: " + error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "Okänd åtgärd." }, 400);
  } catch (e) {
    return json({ error: "Något gick fel på servern: " + String(e) }, 500);
  }
});
