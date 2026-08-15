# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.
Documentación detallada vive en `docs/` y se carga **bajo demanda** — lee solo lo que la tarea actual necesita. Ver `docs/00-indice.md` para el mapa completo.

## Project snapshot

**Nexo** es un tracker de finanzas personales simple, hecho en **Flutter** (Dart SDK ^3.3.0). Un solo usuario, **totalmente local** — sin backend, sin auth, sin login/PIN, sin red. Todo vive en SQLite en el dispositivo. El primer usuario real es el padre del desarrollador (tester informal), así que la simplicidad y la baja fricción importan más que la cantidad de features.

## Reglas siempre relevantes

Lo suficientemente chicas como para mantenerlas siempre cargadas; todo lo demás está a un Read de distancia en `docs/`.

- **Sin backend/auth** — no asumas que existe una API o autenticación en ningún momento.
- **Categorías sin campo de tipo** — una misma categoría sirve para ingreso y gasto; el tipo se elige aparte.
- **Cambios de schema SQLite siempre vía `onUpgrade`**, nunca modificando `_onCreate` directamente — hay datos reales de producción.
- **Paleta oscura "urban" únicamente** — no proponer temas claros sin que el usuario lo pida explícitamente (ya se descartó un rediseño Material 3 claro).
- La app se siente pulida ante todo — priorizar fluidez/UX sobre agregar features nuevas por iniciativa propia (ver subagente `ux-flutter`).

## Documentación modular

| Cuándo | Dónde |
|---|---|
| Stack, estructura, modelo de datos, deployment | `docs/arquitectura.md` |
| Sistema de diseño y convenciones de UX | `docs/diseno-ux.md` |
| Animaciones, transiciones, micro-interacciones | subagente `ux-flutter` (`.claude/agents/`) |
| Legibilidad y buenas prácticas de código | skill `clean-code` (`.claude/skills/`) |
