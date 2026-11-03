# CHANGELOG — Weather / POI / Geocoding

### [2026-10-08 19:50 EDT] [weather] Deep treatment DIRECTO: re-validación E2E de las 6 fuentes (data era del 2026-08-15) + medicion LIVE en harness
- **Tipo**: docs + auditoría (hecho directo por Victoria; delegación no usada — provider en 429)
- **Que**: las queries §1 del .md tenían data del **2026-08-15** (~2 meses). Re-validadas HOY verbatim: Open-Meteo 200 (DC), wttr.in 200 (Washington j1), Nominatim 200 (CDMX relation 1376330), Overpass 200 (Miami Brickell **79** restaurantes vs 77 del doc — data viva), weather.gov 200 (points GeoJSON), country.io 200 (names.json). **Las 6 fuentes vivas**. Nota: un query Overpass propio malformado dio 406 (mi sintaxis, no la API) — regla: usar SIEMPRE las queries verbatim del .md §1-3. Harness + `medicion_live` (fecha + resultados) + `limites_vigentes` (10K/día, 100/min, 1 req/s + UA, 1 query/20s, 10/s).
- **Verificado**: harness JSON válido; doc-fresh Weather FRESH.
- **Docs**: yes (este changelog + harness + general)

### [2026-10-08 15:05 EDT] [weather] Restructuring agente Weather (patrón vLLM): docs oficiales + puntero changelog
- **Tipo**: docs + refactor
- **Que**: §Docs oficiales (open-meteo.com/en/docs — el `/docs` pelado da 404 — + wttr.in + Nominatim + Overpass OSM wiki + weather.gov; todas verificadas vivas) + §Upstream check + §Changelog (faltaba) en `weather.md` y `weather.harness.json`.
- **Verificado**: JSON válido, doc-fresh Weather FRESH.
- **Gap profundo pendiente (prioridad BAJA pero real)**: la data de las queries §1 es del **2026-08-15** (~2 meses vieja) — re-validación E2E pendiente.

> Servicio: weather-poi (Open-Meteo, wttr.in, weather.gov, Nominatim, Overpass, country.io)
> Subagente: `Weather` (`~/.config/opencode/agents/weather.md`)
> 100% gratuito, sin API key, sin daemon local (APIs públicas)
> Changelog general: `/home/victoria/CHANGELOG.md` (todas las entradas también se agregan ahí)

---

### [2026-09-18 19:00] Validación post-recreación sandbox — weather sin cambios
- **Tipo**: docs (verificación, sin cambios)
- **Que**: El servicio weather-poi NO tiene daemon local ni estado — usa APIs públicas gratuitas (Open-Meteo, wttr.in, Nominatim, Overpass). No se afecta por la recreación del sandbox.
- **Verificado**: sin cambios necesarios.
- **Docs**: yes (este changelog)
