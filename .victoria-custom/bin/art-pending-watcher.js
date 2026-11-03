// art-pending-watcher.js — sensor de pedidos creativos pendientes (modo creativo v3)
// Trigger script headless del job nativo "art-pending-notify" (runtime 2026.9.2,
// patrón docs/automation/cron-jobs.md "Event triggers"): el scheduler evalúa
// este script cada 2m SIN gastar inferencia; solo dispara el agent-turn cuando
// hay pedidos NUEVOS. Read-only por diseño — la acción (avisar al owner) vive
// en el payload del job, no aquí (regla de la doc oficial).
// Deduplicación: trigger.state.notified guarda las claves ya avisadas.
// v3 (2026-10-09): pendientes con clave compuesta scope||feature (UNA por
// scope+feature); el watcher las entiende y muestra el feature. Claves viejas
// (scope solo) siguen funcionando.
const res = await exec({ command: "cat /sandbox/.openclaw/workspace/art-approvals.json" });
let pending = {};
try { pending = (JSON.parse(res?.aggregated ?? "{}") ?? {}).pending ?? {}; }
catch { pending = {}; }
const seen = Array.isArray(trigger.state?.notified) ? trigger.state.notified : [];
// Dedup por clave compuesta + requested_at: un MISMO grupo puede tener
// pedidos sucesivos (y de varios features) y cada uno debe avisar.
const keyOf = (key, p) => key + "@" + String(p?.requested_at ?? p?.ts ?? "");
const splitKey = (key, p) => {
  const i = String(key).indexOf("||");
  if (i >= 0) return { scope: key.slice(0, i), feature: key.slice(i + 2) };
  return { scope: String(p?.scope ?? key), feature: String(p?.feature ?? "imagen") };
};
const fresh = Object.entries(pending).filter(([key, p]) => !seen.includes(keyOf(key, p)));
if (fresh.length === 0) {
  json({ fire: false, state: { notified: seen } });
} else {
  const lines = fresh.map(([key, p]) => {
    const { scope, feature } = splitKey(key, p);
    const who = p?.requested_by ?? p?.requester ?? "un miembro";
    const prompt = String(p?.prompt ?? "").slice(0, 140);
    const when = p?.requested_at ?? p?.ts ?? "?";
    return `- ${scope} [${feature}] — pedido por ${who}: "${prompt}" (recibido: ${when})`;
  }).join("\n");
  json({
    fire: true,
    message: "Pedidos creativos PENDIENTES esperando aprobación del owner:\n" + lines,
    state: { notified: seen.concat(fresh.map(([key, p]) => keyOf(key, p))) }
  });
}
