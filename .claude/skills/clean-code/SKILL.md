---
name: clean-code
description: Checklist de código limpio y buenas prácticas para Dart/Flutter, aplicado al codebase de Nexo. Úsala al escribir código nuevo o al revisar/refactorizar código existente, para mantenerlo legible, simple y consistente con el resto del proyecto.
---

# Clean code — Nexo (Dart/Flutter)

Nexo es una app simple, de un solo desarrollador, sin equipo detrás. La prioridad de esta skill no es imponer reglas de "código enterprise", sino mantener el código **fácil de leer y de retomar meses después** — que es el escenario real de este proyecto.

## Legibilidad ante todo

- **Nombres descriptivos, no abreviados**: `transactionProvider` mejor que `txProv`. Excepción: abreviaciones ya establecidas en el proyecto (`tx` para transaction ya se usa en `db_helper.dart` — mantener consistencia con lo existente antes que imponer un estilo nuevo).
- **Funciones cortas, con un solo propósito.** Si un método de un widget o provider supera ~30-40 líneas o mezcla más de una responsabilidad (ej. validar + guardar + notificar), es candidato a dividirse.
- **Evita el anidamiento profundo** de widgets o condicionales (más de 3-4 niveles). Extrae a un método privado (`_buildXyz`) o a un widget separado cuando el árbol se vuelve difícil de seguir.
- **Comentarios solo cuando explican el "por qué", no el "qué"** — el código ya dice qué hace. Los comentarios existentes en `db_helper.dart` (ej. por qué las categorías no tienen campo de tipo) son el estándar a seguir: explican una decisión de diseño no obvia, no narran el código línea por línea.

## Simplicidad sobre abstracción prematura

- No introduzcas patrones (Repository, use cases, DI containers, etc.) que el tamaño actual del proyecto no justifica. `provider` + `DBHelper` como singleton ya es la arquitectura elegida — trabaja dentro de ella en vez de proponer una reestructuración grande sin que el usuario lo pida.
- Prefiere composición de widgets pequeños y reutilizables por sobre un widget gigante con muchos parámetros booleanos para controlar variantes.
- No agregues dependencias nuevas para resolver algo que Flutter/Dart ya resuelve de forma nativa (ver también el subagente `ux-flutter` sobre esto para animaciones específicamente).

## Buenas prácticas específicas de Flutter/Dart

- **`const` constructors** en todo widget que no dependa de estado — mejora performance y es una señal de que el widget es realmente inmutable.
- **Null safety real, no `!` como parche**: si un valor puede ser null, maneja el caso explícitamente (`if (value == null) return;` / `?.` / `??`) en vez de forzar con `!` para silenciar el analyzer.
- **`ChangeNotifier` (providers) no deben tener lógica de UI** — mantener `category_provider.dart` y `transaction_provider.dart` enfocados en estado y llamadas a `DBHelper`; la lógica de presentación (formato, colores, textos) vive en los widgets o en `utils/`.
- **Toda escritura a SQLite pasa por `DBHelper`** — no abrir conexiones ni ejecutar queries sueltas desde un widget o provider directamente.
- **Cambios de schema van siempre por `_onUpgrade`**, nunca modificando `_onCreate` directamente (ver la nota ya existente en `CLAUDE.md` sobre esto — hay datos reales del padre del usuario en producción, no es un ambiente de pruebas).
- Usa `flutter_lints` (ya está como dev dependency) como piso mínimo — si el analyzer marca algo, no lo ignores con `// ignore:` sin una razón concreta.

## Al revisar código (propio o pedido por el usuario)

Cuando te pidan revisar o refactorizar algo, entrega hallazgos agrupados así, sin reescribir archivos completos a menos que se te pida explícitamente:

- 🔴 **Bugs o riesgos reales** (null-safety mal manejada, escritura fuera de `DBHelper`, migración de schema hecha mal)
- 🟡 **Legibilidad/estructura** (función muy larga, anidamiento profundo, nombre poco claro)
- 🟢 **Sugerencias opcionales** (const faltante, oportunidad de extraer un widget)

No reportes estilo puramente subjetivo si no rompe ninguna convención ya establecida en el proyecto — el objetivo es mantener el código simple y legible, no imponer preferencias personales.
