---
name: Weather
description: Weather, geocoding and POIs for the Americas (LatAm + USA/Canada). 100% free, no API key required. Open-Meteo, wttr.in, weather.gov, Nominatim, Overpass API, country.io, Wikipedia.
mode: subagent
hidden: false
temperature: 0.1
---
> **Frescura**: lo LIVE manda (`systemctl`/`curl`/`docker`/`nvidia-smi`/logs primero); este doc trae receta y topología. Si discrepan: actúa sobre lo live, actualiza doc + changelog y reporta (protocolo en `agents/victoria.md` §Frescura).

# AGENTS.md · Weather & POI Service (OpenClaw Victoria)

> Clima, geocodificación y POIs para América (LatAm + USA/Canada). Todo 100% gratuito, sin API key, sin registro.

## 1. E2E Validation — América (LatAm/USA/Canada)

Actualizado 2026-08-15, todas las queries validadas desde el sandbox `victoria-armada`.

### Clima (Open-Meteo)

| Ciudad | País | Temp | Viento |
|---|---|---|---|
| Ciudad de México | MX | 19.9 °C | 1.5 km/h |
| Miami | USA | 89.8 °F | 14.7 km/h |
| Toronto | Canada | 21.7 °C | 24.7 km/h |
| Buenos Aires | AR | 15.2 °C | 11.6 km/h |

### Restaurantes (Overpass QL — `amenity=restaurant`)

| Ciudad | Count | Ejemplos |
|---|---|---|
| CDMX zona centro | **951** | La Biela, Barracuda Diner |
| Toronto downtown | **580** | Red Lobster, Drom Taberna |
| Miami brickell | **77** | El Cartel (colombiana), Wok Town |

### Gasolineras (Overpass QL — `nwr[amenity=fuel]`)

| Ciudad | Count | Marcas principales | Ejemplo notable |
|---|---|---|---|
| CDMX zona centro | **262** | Pemex(155), G500(29), BP(15), Shell(11), Repsol(6), Oxxo(3) | Pemex en 5ta de Febrero |
| NYC Battery Park | **9** | Mobil(3), BP(2), Citgo(2), Sunoco(1), Emporium(1) | Mobil al sur de Manhattan |
| Toronto downtown | **17** | Esso(6), Petro-Canada(4), Shell(3), Canadian-Tire(1) | Canadian Tire + 24/7 |

### Geocoding (Nominatim OSM)

| Query | Lat | Lon | Type |
|---|---|---|---|
| Mexico City, MX | 19.3207722 | -99.1514678 | city |
| Toronto, ON, Canada | 43.6534817 | -79.3839347 | city |
| Miami, FL, USA | 25.7741566 | -80.1935973 | city |
| Buenos Aires, AR | -34.6095579 | -58.3887904 | city |

### NWS Weather.gov (USA only)

| Ciudad | Respuesta |
|---|---|
| New York (40.71, -74.00) | "New York, NY" grid points + forecast OK |

## 2. APIs Públicas — Free, No-Registration, No-API-Key

| API | Free | Rate | Cobertura |
|---|---|---|---|
| Open-Meteo | ✅ | 10K/día | Global (C/F/hourly/daily/16d) |
| wttr.in | ✅ | 100/min | Global (texto/JSON) |
| Weather.gov/NWS | ✅ | 500/día | USA only (alerts/forecasts) |
| Nominatim OSM | ✅ | 1/s, 15K/día | Global (address↔coords) |
| Open-Meteo Geo | ✅ | 10K/día | Global (name→coords) |
| Overpass API | ✅ | 1 cada 20s | Global (POIs, maps, business) |
| country.io | ✅ | 10/s | Global (ISO codes) |
| Wikipedia API | ✅ | 1/s | Global (info general) |

## 3. Queries Overpass — LatAm/USA/Canada

### Restaurantes
```bash
# CDMX centro histórico
curl -s -X POST 'https://overpass-api.de/api/interpreter' \
  -H 'User-Agent: Victoria-Armada/1.0' \
  --data-urlencode 'data=[out:json];node[amenity=restaurant](19.40,-99.18,19.44,-99.13);out;'
→ 951 restaurantes

# Toronto downtown
curl -s -X POST 'https://overpass-api.de/api/interpreter' \
  -H 'User-Agent: Victoria-Armada/1.0' \
  --data-urlencode 'data=[out:json];node[amenity=restaurant](43.63,-79.40,43.66,-79.35);out;'
→ 580 restaurantes

# Miami brickell
curl -s -X POST 'https://overpass-api.de/api/interpreter' \
  -H 'User-Agent: Victoria-Armada/1.0' \
  --data-urlencode 'data=[out:json];node[amenity=restaurant](25.75,-80.20,25.78,-80.18);out;'
→ 77 restaurantes
```

### Gasolineras (usar `nwr` para incluir ways/relaciones)
```bash
# CDMX zona centro → 262 gasolineras (Pemex 155, G500 29, BP 15, Shell 11)
curl -s -X POST 'https://overpass-api.de/api/interpreter' \
  -H 'User-Agent: Victoria-Armada/1.0' \
  --data-urlencode 'data=[out:json];nwr[amenity=fuel](19.35,-99.20,19.48,-99.05);out;'

# Battery Park/WTC area NYC → 9 gasolineras (Mobil 3, BP 2, Citgo 2, Sunoco 1)
curl -s -X POST 'https://overpass-api.de/api/interpreter' \
  -H 'User-Agent: Victoria-Armada/1.0' \
  --data-urlencode 'data=[out:json];nwr[amenity=fuel](40.69,-74.02,40.76,-73.96);out;'

# Toronto downtown → 17 gasolineras (Esso 6, Petro-Canada 4, Shell 3, Canadian-Tire 1)
curl -s -X POST 'https://overpass-api.de/api/interpreter' \
  -H 'User-Agent: Victoria-Armada/1.0' \
  --data-urlencode 'data=[out:json];nwr[amenity=fuel](43.62,-79.42,43.68,-79.33);out;'
```

### Geocoding NA
```bash
# CDMX
curl -s 'https://nominatim.openstreetmap.org/search?q=Mexico+City,+Mexico&format=json&limit=1' \
  -H 'User-Agent: Victoria-Armada/1.0'
→ lat:19.32077 lon:-99.15147

# Toronto
curl -s 'https://nominatim.openstreetmap.org/search?q=Toronto,+Ontario,+Canada&format=json&limit=1' \
  -H 'User-Agent: Victoria-Armada/1.0'
→ lat:43.65348 lon:-79.38393

# Miami
curl -s 'https://nominatim.openstreetmap.org/search?q=Miami,+FL,+USA&format=json&limit=1' \
  -H 'User-Agent: Victoria-Armada/1.0'
→ lat:25.77416 lon:-80.19360

# Buenos Aires
curl -s 'https://nominatim.openstreetmap.org/search?q=Buenos+Aires,+Argentina&format=json&limit=1' \
  -H 'User-Agent: Victoria-Armada/1.0'
→ lat:-34.60956 lon:-58.38879
```

## 4. Limitaciones

- **Weather.gov**: USA only. Para internacional usar Open-Meteo.
- **Overpass**: 1 query cada 20s en servidor público (necesario respetar).
- **Nominatim**: 1 req/s. Usar `User-Agent` válido.

> ⚠️ **Data safety: Todo dentro de Docker es efímero.** El sandbox `openshell-victoria-armada` puede ser
> eliminado/reconstruido en cualquier momento. No almacenar datos permanentes dentro del container.
> Si necesitas guardar data: usar el host (`/home/victoria/`) o el persist backup (`openclaw-persist.sh`).

## Docs oficiales (APIs públicas — consultar ANTES de cambiar queries)

| Fuente | Qué cubre | URL | Verificada |
|---|---|---|---|
| Open-Meteo docs | forecast API, parámetros, límites 10K/día | https://open-meteo.com/en/docs | 2026-10-08 VIVA |
| wttr.in | clima console-oriented (texto/JSON, 100/min) | https://wttr.in/ | 2026-10-08 VIVA |
| Nominatim API docs | geocoding Search/reverse, política 1 req/s + User-Agent obligatorio | https://nominatim.org/release-docs/latest/api/Search/ | 2026-10-08 VIVA |
| Overpass API (OSM wiki) | QL queries (`nwr`, amenity), límite 1 query/20s | https://wiki.openstreetmap.org/wiki/Overpass_API | 2026-10-08 VIVA |
| weather.gov / NWS API | alerts/forecast USA only (500/día) | https://www.weather.gov/documentation/services-web-api | 2026-10-08 VIVA |

## Upstream check (disciplina)

- APIs públicas gratuitas SIN contrato: si una query deja de responder, verificar contra la doc oficial (cambios de schema) y re-validar E2E con las queries de §1.
- Respetar rate limits (Nominatim 1/s, Overpass 1/20s) + `User-Agent: Victoria-Armada/1.0` — el abuso mata el acceso gratis.
- **Cómo reportar**: entrada en `~/.victoria-custom/changelogs/CHANGELOG-weather.md` (sección upstream) + aviso a Victoria en el Task.

## Changelog
`~/.victoria-custom/changelogs/CHANGELOG-weather.md` + `/home/victoria/CHANGELOG.md` (general).
