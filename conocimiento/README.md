# 🧠 Conocimiento — la memoria que hace "aprender" al modelo

> **La idea del owner (2026-10-27)**: no podemos enseñarle más al Qwen3.6 (sus
> pesos están congelados), pero SÍ podemos darle **parámetros extra** — este
> directorio ES esa capa: conocimiento estructurado, vivo y verificado que los
> agentes leen antes de actuar. Cada incidente documentado = una sinapsis nueva
> del ecosistema. Con el tiempo, la flota "sabe" lo que el modelo base no.

## Los 4 componentes (y por qué existen)

| Componente | Qué es | Para qué |
|---|---|---|
| **LECCIONES.md** | Errores cometidos → reglas derivadas, indexadas por dominio | NUNCA repetir un error, NUNKA tomar un camino ya descartado |
| **lenguajes/** | Doc viva de cada lenguaje/herramienta en uso (versión real, patrones, gotchas, docs oficiales) | El agente SIEMPRE sabe qué hacer y con qué versión — sin adivinar APIs |
| **harness/** (`~/.victoria-custom/harness/`) | Por servicio: misión, scope, servicios con flags_live, health, recovery, docs_oficiales, upstream, no_touch | El agente sabe QUÉ opera y CÓMO verificarlo |
| **changelogs/** (`~/.victoria-custom/changelogs/`) | Historial cronológico por servicio + general | Qué se hizo, cuándo, por qué — el "por qué" evita deshacer decisiones |

## El ciclo de aprendizaje (cómo crece este conocimiento)

```
1. ACTUAR  → el agente trabaja (con LECCIONES + lenguajes + harness como contexto)
2. VERIFICAR → E2E con herramientas reales (curl/systemctl/ffprobe), nunca "debería"
3. DOCUMENTAR → changelog del servicio + general (qué, por qué, verificado)
4. APRENDER  → si hubo incidente/lección: 1 línea de regla en LECCIONES.md
5. FRESCURA  → armada-sync cada 6h chequea doc-vs-live-vs-upstream; lo que se pudre se cura
```

## Reglas de uso para TODOS los agentes

1. **Antes de actuar en un dominio**: leer sus lecciones en LECCIONES.md.
2. **Antes de programar contra un lenguaje/tool**: leer su doc en `lenguajes/`
   (versión en uso + gotchas) y las `docs_oficiales` del harness del servicio.
3. **Después de cada incidente**: agregar la lección (1 línea de regla + ref
   changelog). Sin lección escrita = el incidente se repetirá.
4. **Docs oficiales versionadas**: programar contra la versión SERVIDA, no la
   latest de internet (el harness de cada servicio lista las fuentes).
5. **Siguientes pasos**: siempre bajo investigación (docs + live + best
   practices), nunca inventados — ver todowrite-discipline.md §Siguientes pasos.

## Estado de frescura

- `lenguajes/*.md` llevan fecha **Verificado** arriba — si >30 días, verificar
  versiones live antes de confiar.
- LECCIONES.md: revisión general mensual; entradas nuevas inmediatas.
- El chequeo automático de drift vive en `armada-sync.sh cycle` (timer 6h) +
  `upstream-sync.py --status`.
