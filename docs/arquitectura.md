# Arquitectura y datos — Nexo

## Stack

- **State management**: `provider` (`^6.1.2`)
- **Local storage**: `sqflite` (SQLite) vía `lib/db/db_helper.dart` — singleton `DBHelper` que centraliza todas las queries.
- **Charts**: `fl_chart`
- **Fonts**: `google_fonts` — Space Grotesk (display/headings) + Plus Jakarta Sans (body)
- **Formatting**: `intl` (fechas, separador de miles)

Sin backend, sin auth, sin login/PIN, sin llamadas de red. Toda la información vive únicamente en el dispositivo. Usuario único (el padre del desarrollador es el primer tester real).

## Estructura (`lib/`)

- `main.dart` — entry point.
- `db/db_helper.dart` — todo el acceso a SQLite (CRUD de categorías y transacciones, migraciones de schema).
- `models/` — `category_model.dart`, `transaction_model.dart`.
- `providers/` — `category_provider.dart`, `transaction_provider.dart` (`ChangeNotifier`, consumidos vía `provider`).
- `screens/` — `home_screen.dart` (registro), `quick_entry_screen.dart`, `history_screen.dart`, `edit_transaction_screen.dart`, `metrics_screen.dart`.
- `theme/app_theme.dart` — todo el sistema de diseño (ver `docs/diseno-ux.md`).
- `widgets/`, `utils/` — componentes compartidos y helpers.

## Modelo de datos

**`categories`**: `id`, `name`, `icon_key` (mapea a un ícono vectorial, no emoji), `is_default`. **Sin campo de tipo** — una categoría (ej. "Freelance") puede usarse tanto para ingreso como gasto; el tipo se elige aparte, por transacción, con un toggle de píldora. El usuario puede crear, editar y eliminar categorías, incluidas las por defecto.

**`transactions`**: `id`, `amount`, `type` (`income`/`expense`), `category_id` + `category_name`/`category_icon_key` denormalizados (se conservan aunque la categoría se edite o elimine después), `note`, `date` (editable — no forzada a "hoy", y la fecha seleccionada persiste entre registros consecutivos para poder cargar varios movimientos con la misma fecha seguidos).

Schema versionado (actualmente v2) con migraciones `onUpgrade` en `db_helper.dart` — ej. v1→v2 migró íconos basados en emoji a `icon_key`. **Todo cambio de schema va por un nuevo paso `onUpgrade`, nunca modificando `_onCreate` directamente** — ya existen datos reales (los del padre del usuario) en producción, esto no es un ambiente de pruebas.

## Deployment

Sin cuenta de Apple Developer — los builds de iOS se **sideloadean** vía iLoader (Windows) + una Mac prestada para compilar, con re-firma manual aproximadamente cada 7 días (la auto-renovación con AltStore/SideStore no resultó confiable). Tenerlo presente antes de sugerir features específicas de iOS o pasos de build — no hay distribución vía App Store actualmente.

## Pitfall conocido

Existió una copia duplicada y desincronizada de este proyecto en `C:\Users\BenjaminD\Desktop\App\nexo\nexo_build`, de una sesión anterior. **Este repo** (`Proyectos\nexo\nexo_build`, con git) es el real. Si algo se ve desincronizado, confirmar sobre qué copia se está trabajando.
