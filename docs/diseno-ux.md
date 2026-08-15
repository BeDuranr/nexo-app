# Diseño y UX — Nexo

## Sistema de diseño (`theme/app_theme.dart`)

**Paleta oscura "urban" únicamente** (sin tema claro) — decisión deliberada, después de probar y descartar un rediseño Material 3 claro:
- `urban950` `#0B0C0D` (fondo) → `urban100` `#F0F2F5` (texto), rampa de grises completa entre medio.
- `income` `#10B981` (verde), `expense` `#F43F5E` (rojo), `urbanBlue` `#3B82F6` (primario/acento).
- Tipografía: `GoogleFonts.spaceGrotesk()` para display/títulos, `GoogleFonts.plusJakartaSans()` para cuerpo.
- Íconos de categoría son **vectoriales**, no emoji (se migró de emoji a propósito).

## Convenciones de UX a preservar

- Ingreso de monto con el **teclado numérico nativo** (al tocar el campo), no un teclado personalizado dentro de la app — pero necesita una barra "Listo" arriba del teclado para poder cerrarlo (ya implementado en el campo de nota; el de monto lo necesita también en Registrar y Editar).
- El campo de monto muestra el separador de miles mientras se escribe (ej. `10.000`).
- Historial: **un mismo swipe revela tanto editar como borrar** — no un tap aparte para editar.
- Historial filtrable por mes.
- El saldo mostrado es el **acumulado hasta la fecha seleccionada dentro de ese mes**, no un mes calendario fijo — distinto al total histórico, que es el total absoluto de todos los tiempos.
- Al eliminar una transacción se ofrece **"Deshacer"** (vía `restoreTransaction`).
- Vibración sutil (haptic feedback) al agregar o eliminar un movimiento, como confirmación.
- Preferencia general por **animaciones fluidas** por sobre cortes duros entre pantallas/estados — ej. el toggle de ingreso/gasto usa un efecto de píldora deslizante, no solo cambio de color. Priorizar este estilo para UI nueva, no asumir cambios de estado instantáneos por defecto.
- El botón de guardar cambia de color según el tipo seleccionado (verde para ingreso, rojo para gasto).

## Dónde profundizar

- Para cualquier tarea de animaciones, transiciones o micro-interacciones: subagente `ux-flutter` (`.claude/agents/ux-flutter.md`).
- Para revisión de calidad de código al escribir o refactorizar: skill `clean-code` (`.claude/skills/clean-code/SKILL.md`).
