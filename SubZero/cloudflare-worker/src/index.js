const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const PAIRING_TTL_SECONDS = 10 * 60;
const DEVICE_TTL_SECONDS = 60 * 60 * 24 * 365;

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json", "cache-control": "no-store" },
});

function randomString(length) {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return [...bytes].map((byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
}

function randomSecret() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function safeText(value, max = 128) {
  return typeof value === "string" ? value.slice(0, max) : "";
}

async function readJSON(request) {
  try { return await request.json(); } catch { return null; }
}

function normalizedCode(value) {
  return safeText(value, 32).toUpperCase().replace(/[^A-Z2-9]/g, "");
}

async function firebaseUser(request, env) {
  const authorization = request.headers.get("authorization") || "";
  if (!authorization.startsWith("Bearer ")) return null;
  const token = authorization.slice(7);
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const payload = JSON.parse(atob(parts[1].replaceAll("-", "+").replaceAll("_", "/")));
  if (payload.aud !== env.FIREBASE_PROJECT_ID ||
      payload.iss !== `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}` ||
      payload.exp * 1000 < Date.now() || !payload.sub) return null;
  // The Android Firebase SDK obtains this token. The Worker still verifies its
  // signature before trusting it.
  const keySet = await fetch("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com").then(r => r.json());
  const header = JSON.parse(atob(parts[0].replaceAll("-", "+").replaceAll("_", "/")));
  const jwk = keySet.keys?.find(key => key.kid === header.kid);
  if (!jwk) return null;
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const signature = Uint8Array.from(atob(parts[2].replaceAll("-", "+").replaceAll("_", "/")), c => c.charCodeAt(0));
  const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  return valid ? { uid: payload.sub, email: payload.email || null } : null;
}

function base64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes))).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function googleAccessToken(env) {
  const serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON);
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = base64url(new TextEncoder().encode(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));
  const keyData = serviceAccount.private_key.replace(/-----(BEGIN|END) PRIVATE KEY-----|\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(keyData), c => c.charCodeAt(0)), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const assertion = `${header}.${claims}.${base64url(signature)}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) throw new Error("Unable to obtain FCM access token");
  return (await response.json()).access_token;
}

async function sendFcm(env, token, title, body, data) {
  const accessToken = await googleAccessToken(env);
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`, {
    method: "POST",
    headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
    body: JSON.stringify({ message: { token, notification: { title, body }, data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])), android: { priority: "high" } } }),
  });
  if (!response.ok) throw new Error(`FCM send failed: ${await response.text()}`);
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type", "access-control-allow-methods": "GET, POST, OPTIONS" } });
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "POST" && path === "/v1/pairings") {
      const body = await readJSON(request);
      const deviceId = safeText(body?.deviceId, 160);
      if (!deviceId) return json({ error: "deviceId is required" }, 400);
      const code = randomString(12);
      const secret = randomSecret();
      await env.PAIRINGS.put(`pair:${code}`, JSON.stringify({ code, secret, deviceId, deviceName: safeText(body?.deviceName, 128) || "Mac", status: "pending", createdAt: Date.now() }), { expirationTtl: PAIRING_TTL_SECONDS });
      return json({ code, expiresInSeconds: PAIRING_TTL_SECONDS, secret });
    }

    if (request.method === "POST" && path === "/v1/pairings/claim") {
      const user = await firebaseUser(request, env);
      if (!user) return json({ error: "Android sign-in is required" }, 401);
      const body = await readJSON(request);
      const code = normalizedCode(body?.code);
      const token = safeText(body?.fcmToken, 4096);
      const raw = code && await env.PAIRINGS.get(`pair:${code}`);
      if (!raw) return json({ error: "Pairing code is invalid or expired" }, 404);
      const pairing = JSON.parse(raw);
      if (pairing.status !== "pending") return json({ error: "Pairing code has already been used" }, 409);
      pairing.status = "paired";
      pairing.userId = user.uid;
      pairing.userEmail = user.email;
      pairing.fcmToken = token;
      pairing.pairedAt = Date.now();
      await env.PAIRINGS.put(`pair:${code}`, JSON.stringify(pairing), { expirationTtl: DEVICE_TTL_SECONDS });
      return json({ deviceId: pairing.deviceId, deviceName: pairing.deviceName });
    }

    if (request.method === "GET" && path.startsWith("/v1/pairings/")) {
      const code = normalizedCode(path.split("/").pop());
      const secret = request.headers.get("x-subzero-pairing-secret") || "";
      const raw = code && await env.PAIRINGS.get(`pair:${code}`);
      if (!raw) return json({ error: "Pairing code is invalid or expired" }, 404);
      const pairing = JSON.parse(raw);
      if (secret !== pairing.secret) return json({ error: "Unauthorized" }, 401);
      return json({ status: pairing.status, deviceName: pairing.deviceName, userEmail: pairing.userEmail || null });
    }

    if (request.method === "POST" && path === "/v1/telemetry") {
      const body = await readJSON(request);
      const code = normalizedCode(body?.pairingCode);
      const secret = safeText(request.headers.get("x-subzero-pairing-secret"), 128);
      const raw = code && await env.PAIRINGS.get(`pair:${code}`);
      if (!raw) return json({ error: "Pairing not found" }, 404);
      const pairing = JSON.parse(raw);
      if (pairing.status !== "paired" || secret !== pairing.secret) return json({ error: "Mac is not paired" }, 401);
      pairing.telemetry = {
        maxTemp: Number(body?.maxTemp) || 0,
        cpuTemp: Number(body?.cpuTemp) || 0,
        gpuTemp: Number(body?.gpuTemp) || 0,
        cpuLoad: Number(body?.cpuLoad) || 0,
        batteryPct: Number(body?.batteryPct) || 0,
        isCharging: Boolean(body?.isCharging),
        packageWatts: Number(body?.packageWatts) || 0,
        thermalState: safeText(body?.thermalState, 64) || "Nominal",
        alertThreshold: Number(body?.alertThreshold) || 85,
        alertTriggered: Boolean(body?.alertTriggered),
        alertMessage: safeText(body?.alertMessage, 180),
        updatedAt: Date.now(),
      };
      if (body?.alertTriggered && !pairing.alertActive && pairing.fcmToken) {
        await sendFcm(env, pairing.fcmToken, `🔥 High temperature: ${pairing.deviceName}`, safeText(body?.alertMessage, 180) || "Your Mac is running hot.", { type: "thermal_alert", deviceId: pairing.deviceId, maxTemp: body?.maxTemp ?? "" });
        pairing.alertActive = true;
      } else if (!body?.alertTriggered) {
        pairing.alertActive = false;
      }
      await env.PAIRINGS.put(`pair:${code}`, JSON.stringify(pairing), { expirationTtl: DEVICE_TTL_SECONDS });
      return json({ accepted: true });
    }

    if (request.method === "GET" && path === "/v1/telemetry") {
      const user = await firebaseUser(request, env);
      if (!user) return json({ error: "Android sign-in is required" }, 401);
      const listed = await env.PAIRINGS.list({ prefix: "pair:", limit: 100 });
      const devices = [];
      for (const key of listed.keys) {
        const raw = await env.PAIRINGS.get(key.name);
        if (!raw) continue;
        const pairing = JSON.parse(raw);
        if (pairing.status !== "paired" || pairing.userId !== user.uid || !pairing.telemetry) continue;
        devices.push({ deviceId: pairing.deviceId, deviceName: pairing.deviceName, ...pairing.telemetry });
      }
      return json({ devices });
    }

    return json({ error: "Not found" }, 404);
  },
};
