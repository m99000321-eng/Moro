import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const allowedOrigins = new Set([
  "https://noir-cinematic-studio.vercel.app",
  "https://noir-cinematic-studio-amrs-projects-9962a17d.vercel.app",
  "https://noir-cinematic-studio-git-main-amrs-projects-9962a17d.vercel.app",
  "http://localhost:3000",
  "http://127.0.0.1:3000"
]);
type Json = Record<string, unknown>;
function corsHeaders(origin: string | null): Record<string,string> {
  return {
    "Access-Control-Allow-Origin": origin && allowedOrigins.has(origin) ? origin : "https://noir-cinematic-studio.vercel.app",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin"
  };
}
function respond(status: number, body: Json, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" }
  });
}
function text(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}
function validPhone(phone: string): boolean {
  return /^[+()\d][+()\d .-]{5,24}$/.test(phone);
}
function validEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) && email.length <= 254;
}
async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((v) => v.toString(16).padStart(2, "0")).join("");
}
async function api(path: string, init: RequestInit = {}): Promise<unknown> {
  if (!SUPABASE_URL || !SERVICE_KEY) throw new Error("BACKEND_NOT_CONFIGURED");
  const response = await fetch(SUPABASE_URL + "/rest/v1/" + path, {
    ...init,
    headers: {
      "apikey": SERVICE_KEY,
      "Authorization": "Bearer " + SERVICE_KEY,
      "Content-Type": "application/json",
      "Accept": "application/json",
      ...(init.headers ?? {})
    }
  });
  const raw = await response.text();
  let data: unknown = null;
  try { data = raw ? JSON.parse(raw) : null; } catch { data = raw; }
  if (!response.ok) {
    console.error("database operation failed", response.status, data);
    throw new Error("DATABASE_OPERATION_FAILED");
  }
  return data;
}
async function rateAllowed(req: Request, action: string, limit: number, windowSeconds: number): Promise<boolean> {
  const ip = req.headers.get("cf-connecting-ip")
    ?? req.headers.get("x-real-ip")
    ?? req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    ?? "unknown";
  const key = await sha256(ip + "|saffron-table");
  const result = await api("rpc/consume_restaurant_rate_limit", {
    method: "POST",
    body: JSON.stringify({ p_rate_key: key, p_action: action, p_limit: limit, p_window_seconds: windowSeconds })
  });
  return result === true;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(origin) });
  if (req.method !== "POST") return respond(405, { ok: false, error: "METHOD_NOT_ALLOWED" }, origin);
  if (origin && !allowedOrigins.has(origin)) return respond(403, { ok: false, error: "ORIGIN_NOT_ALLOWED" }, origin);
  if (!SUPABASE_URL || !SERVICE_KEY) return respond(503, { ok: false, error: "BACKEND_NOT_CONFIGURED" }, origin);
  const requestLength = Number(req.headers.get("content-length") ?? "0");
  if (requestLength > 32768) return respond(413, { ok: false, error: "REQUEST_TOO_LARGE" }, origin);

  let body: Json;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return respond(400, { ok: false, error: "INVALID_JSON" }, origin);
    body = parsed as Json;
  } catch {
    return respond(400, { ok: false, error: "INVALID_JSON" }, origin);
  }

  const action = text(body.action, 40);
  const config: Record<string, { limit: number; window: number }> = {
    create_order: { limit: 6, window: 600 },
    create_reservation: { limit: 5, window: 1800 },
    track_order: { limit: 20, window: 600 },
    subscribe_newsletter: { limit: 4, window: 3600 }
  };
  if (!config[action]) return respond(400, { ok: false, error: "UNKNOWN_ACTION" }, origin);

  try {
    if (!await rateAllowed(req, action, config[action].limit, config[action].window)) {
      return respond(429, { ok: false, error: "TOO_MANY_REQUESTS" }, origin);
    }

    if (action === "create_order") {
      const name = text(body.name, 80);
      const phone = text(body.phone, 25);
      const fulfillmentType = text(body.fulfillmentType, 20);
      const address = text(body.address, 400);
      const notes = text(body.notes, 300);
      const language = body.language === "ar" ? "ar" : "en";
      const incoming = Array.isArray(body.items) ? body.items : [];
      if (name.length < 2) return respond(400, { ok: false, error: "INVALID_CUSTOMER_NAME" }, origin);
      if (!validPhone(phone)) return respond(400, { ok: false, error: "INVALID_PHONE" }, origin);
      if (!["delivery", "pickup"].includes(fulfillmentType)) return respond(400, { ok: false, error: "INVALID_FULFILLMENT_TYPE" }, origin);
      if (fulfillmentType === "delivery" && address.length < 5) return respond(400, { ok: false, error: "INVALID_DELIVERY_ADDRESS" }, origin);
      if (!incoming.length || incoming.length > 30) return respond(400, { ok: false, error: "INVALID_ORDER_ITEMS" }, origin);
      const items: Array<{product_id:number;quantity:number}> = [];
      for (const raw of incoming) {
        if (!raw || typeof raw !== "object") return respond(400, { ok: false, error: "INVALID_ORDER_ITEMS" }, origin);
        const item = raw as Record<string, unknown>;
        const productId = Number(item.product_id ?? item.id);
        const quantity = Number(item.quantity ?? 1);
        if (!Number.isInteger(productId) || productId < 1 || productId > 9999 ||
            !Number.isInteger(quantity) || quantity < 1 || quantity > 20) {
          return respond(400, { ok: false, error: "INVALID_ORDER_ITEMS" }, origin);
        }
        items.push({ product_id: productId, quantity });
      }
      const expectedPayment = fulfillmentType === "delivery" ? "cash_on_delivery" : "pay_at_pickup";
      const result = await api("rpc/create_restaurant_order", {
        method: "POST",
        body: JSON.stringify({
          p_customer_name: name, p_phone: phone, p_fulfillment_type: fulfillmentType,
          p_delivery_address: address, p_notes: notes, p_language: language,
          p_items: items, p_payment_method: expectedPayment
        })
      });
      return respond(201, { ok: true, order: result }, origin);
    }

    if (action === "create_reservation") {
      const name = text(body.name, 80);
      const phone = text(body.phone, 25);
      const date = text(body.date, 10);
      const time = text(body.time, 40);
      const guests = Number(body.guests);
      const occasion = text(body.occasion, 80);
      const notes = text(body.notes, 400);
      const language = body.language === "ar" ? "ar" : "en";
      if (name.length < 2) return respond(400, { ok: false, error: "INVALID_CUSTOMER_NAME" }, origin);
      if (!validPhone(phone)) return respond(400, { ok: false, error: "INVALID_PHONE" }, origin);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(Date.parse(date + "T12:00:00"))) return respond(400, { ok: false, error: "INVALID_RESERVATION_DATE" }, origin);
      if (!time || time.length > 40 || !Number.isInteger(guests) || guests < 1 || guests > 20) return respond(400, { ok: false, error: "INVALID_RESERVATION_DETAILS" }, origin);
      const result = await api("rpc/create_restaurant_reservation", {
        method: "POST",
        body: JSON.stringify({
          p_customer_name: name, p_phone: phone, p_reservation_date: date,
          p_reservation_time: time, p_guest_count: guests, p_occasion: occasion,
          p_notes: notes, p_language: language
        })
      });
      return respond(201, { ok: true, reservation: result }, origin);
    }

    if (action === "track_order") {
      const reference = text(body.reference, 24).toUpperCase();
      const phone = text(body.phone, 25);
      if (!reference || !validPhone(phone)) return respond(400, { ok: false, error: "INVALID_TRACKING_DETAILS" }, origin);
      const result = await api("rpc/lookup_restaurant_order", {
        method: "POST",
        body: JSON.stringify({ p_reference: reference, p_phone: phone })
      });
      if (!result) return respond(404, { ok: false, error: "ORDER_NOT_FOUND" }, origin);
      return respond(200, { ok: true, order: result }, origin);
    }

    const email = text(body.email, 254).toLowerCase();
    if (!validEmail(email)) return respond(400, { ok: false, error: "INVALID_EMAIL" }, origin);
    await api("restaurant_newsletter_subscribers?on_conflict=email", {
      method: "POST",
      headers: { "Prefer": "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({ email, status: "pending_confirmation", consented_at: new Date().toISOString() })
    });
    return respond(200, { ok: true, message: "EMAIL_RECORDED_PENDING_CONFIRMATION" }, origin);
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
    console.error("restaurant-api error", message);
    if (message === "BACKEND_NOT_CONFIGURED") return respond(503, { ok: false, error: message }, origin);
    return respond(500, { ok: false, error: "SERVER_ERROR" }, origin);
  }
});
