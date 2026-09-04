# Arquitectura y datos — Nexo

## Stack

- **State management**: `provider` (`^6.1.2`)
- **Local storage**: `sqflite` (SQLite) vía `lib/db/db_helper.dart` — singleton `DBHelper` que centraliza todas las queries.
- **Charts**: ninguno — las barras de Métricas son `LinearProgressIndicator` (`fl_chart` se sacó, no se usaba).
- **Fonts**: Space Grotesk (display/headings) + Plus Jakarta Sans (body), **empaquetadas** en `assets/fonts/`. Se sigue usando la API de `google_fonts`, pero con `GoogleFonts.config.allowRuntimeFetching = false` en `main()`: el paquete toma los `.ttf` del bundle y nunca sale a la red. Es obligatorio — el release de Android no declara el permiso `INTERNET`, así que la descarga en runtime fallaba y la tipografía caía al tipo del sistema. Los archivos deben llamarse `{Familia}-{Peso}.ttf` (ej. `SpaceGrotesk-Bold.ttf`); si falta un peso, `google_fonts` lo registra en consola y usa el fallback.
- **Formatting**: `intl` (fechas, separador de miles)

Sin backend, sin auth, sin login/PIN, sin llamadas de red. Toda la información vive únicamente en el dispositivo. Usuario único (el padre del desarrollador es el primer tester real).

## Estructura (`lib/`)

- `main.dart` — entry point.
- `db/db_helper.dart` — todo el acceso a SQLite (CRUD de categorías y transacciones, migraciones de schema).
- `models/` — `category_model.dart`, `transaction_model.dart`.
- `providers/` — `category_provider.dart`, `transaction_provider.dart` (`ChangeNotifier`, consumidos vía `provider`).
- `screens/` — `home_screen.dart` (contenedor de tabs), `quick_entry_screen.dart`, `history_screen.dart`, `edit_transaction_screen.dart`, `metrics_screen.dart`.
- `widgets/movement_form.dart` — **formulario de movimiento compartido** por registro y edición (monto, toggle gasto/ingreso, categorías, nota, fecha, barra "Listo"). Antes esas ~250 líneas estaban duplicadas en las dos pantallas. Guarda la categoría como **id** y la resuelve contra `CategoryProvider` en cada build: por eso nunca se guarda un nombre desactualizado, y si la categoría fue eliminada obliga a elegir una en vez de reasignar en silencio.
- `theme/app_theme.dart` — todo el sistema de diseño (ver `docs/diseno-ux.md`).
- `widgets/`, `utils/` — componentes compartidos y helpers.

## Modelo de datos

**`categories`**: `id`, `name`, `icon_key` (mapea a un ícono vectorial, no emoji), `is_default`. **Sin campo de tipo** — una categoría (ej. "Freelance") puede usarse tanto para ingreso como gasto; el tipo se elige aparte, por transacción, con un toggle de píldora. El usuario puede crear, editar y eliminar categorías, incluidas las por defecto.

**`transactions`**: `id`, `amount`, `type` (`income`/`expense`), `category_id` + `category_name`/`category_icon_key` denormalizados (se conservan aunque la categoría se edite o elimine después), `note`, `date` (editable — no forzada a "hoy", y la fecha seleccionada persiste entre registros consecutivos para poder cargar varios movimientos con la misma fecha seguidos).

Schema versionado (actualmente **v4**) con migraciones `onUpgrade` en `db_helper.dart`:

| Paso | Qué hizo |
|---|---|
| v1→v2 | Migró íconos basados en emoji a `icon_key`. |
| v2→v3 | Reconstruyó ambas tablas para eliminar las columnas `emoji`/`category_emoji`, que habían quedado NOT NULL y hacían fallar todo INSERT nuevo. |
| v3→v4 | Índices sobre `transactions(date)` y `transactions(category_id)`, y re-sincronización de los nombres/íconos denormalizados que quedaron viejos. |

**Todo cambio de schema va por un nuevo paso `onUpgrade`, nunca modificando `_onCreate` directamente** — ya existen datos reales (los del padre del usuario) en producción, esto no es un ambiente de pruebas. `test/db_migration_test.dart` corre las migraciones sobre una base v1 sintética con `sqflite_common_ffi`; conviene extenderlo con cada paso nuevo.

### Sincronización de los campos denormalizados

`transactions` guarda una copia de `category_name` y `category_icon_key`. La regla es:

- **Editar** una categoría propaga el nombre y el ícono nuevos a sus movimientos, dentro de la misma transacción SQL (`DBHelper.updateCategory`). Quien la llama debe además recargar `TransactionProvider` — hoy eso ocurre en `_editCategory` de `widgets/movement_form.dart`.
- **Eliminar** una categoría **no** toca los movimientos: ahí la copia guardada es lo único que los mantiene legibles, y es lo que promete el diálogo de confirmación.

Sin esa propagación, las Métricas mostraban el ícono y el nombre viejos, y la búsqueda del Historial no encontraba un movimiento por el nombre nuevo de su categoría.

## Deployment

Sin cuenta de Apple Developer y sin distribución vía App Store. Tenerlo presente antes de sugerir features específicas de iOS.

### iOS: generar el `.ipa` (ya no hace falta una Mac)

La compilación se separó de la firma, así que **no se usa más la Mac prestada**:

1. **Compilar** — GitHub Actions, workflow `.github/workflows/ios-ipa.yml` ("iOS IPA sin firmar"), en un runner macOS. Se dispara a mano desde la pestaña Actions o empujando un tag `v*`. Corre `analyze` y los tests antes de compilar. Tarda ~4 minutos.
2. **Descargar** — el artifact `nexo-ipa`. GitHub lo entrega comprimido: hay que descomprimirlo y usar el `.ipa` de adentro, no el zip.
3. **Firmar e instalar** — iLoader en Windows, con el Apple ID gratuito.

El binario sale **sin firmar** a propósito (`flutter build ios --release --no-codesign`, empaquetado en una carpeta `Payload/`): no hay credenciales de Apple en el CI. La firma sigue caducando cada 7 días — eso viene del Apple ID gratuito, no del método de build, y se resuelve re-firmando el mismo `.ipa` sin recompilar. La auto-renovación con AltStore/SideStore no resultó confiable.

Como el bundle id (`com.familia.nexo.nexo`) no cambia, el `.ipa` se instala **encima** de la app existente y conserva la base de datos. No desinstalar.

> Si iOS sigue mostrando el ícono viejo después de reinstalar, suele ser caché del sistema: se actualiza reiniciando el teléfono.

### Android: respaldo automático

`allowBackup="false"` más reglas de exclusión en `res/xml/backup_rules.xml` y `res/xml/data_extraction_rules.xml`. Antes el `nexo.db` completo se subía a Google Drive por default, lo que contradecía el "todo vive solo en el dispositivo". **Consecuencia:** si se pierde el teléfono, se pierden los movimientos — no hay respaldo automático en ningún lado.

### Android: firma de release (pendiente, a propósito)

`android/app/build.gradle.kts` lee `android/key.properties` **si existe**:

- **Sin** ese archivo (estado actual): se sigue firmando con la clave de debug, igual que siempre. La app instalada se actualiza in-place sin problemas.
- **Con** ese archivo: se firma con el keystore propio.

La clave de debug es pública y conocida, así que a futuro conviene el keystore propio. Pero **cambiar la firma obliga a desinstalar la app en el Android del papá, y eso borra la base de datos** — y con `allowBackup="false"` ya no hay `adb restore` que valga. Hacer el corte solo cuando se acepte perder esos datos o exista una exportación manual.

```bash
keytool -genkey -v -keystore ~/nexo-release.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias nexo
```

Después, `android/key.properties` (ya está en `.gitignore`, nunca versionarlo):

```properties
storePassword=...
keyPassword=...
keyAlias=nexo
storeFile=C:/Users/<usuario>/nexo-release.jks
```

### Íconos de la app

`flutter_launcher_icons` los genera desde Windows (`dart run flutter_launcher_icons`), sin Mac. Hay **dos fuentes distintas a propósito**:

- `assets/icon/icon.png` → Android. Trae dibujado su propio cuadrado redondeado, que el ícono adaptativo de Android resuelve bien.
- `assets/icon/icon_ios.png` → iOS, vía `image_path_ios`. Es una versión **a sangre** (recorte del interior del tile, logo al 60%, de borde a borde). Hace falta porque iOS aplica su propia máscara encima: con el original se veía un borde redondeado dentro de otro.

`ios: true` y `remove_alpha_ios: true` son necesarios — `ios` estuvo en `false` mucho tiempo, y por eso los `.ipa` salían con el logo de Flutter por defecto.

## Pitfall conocido

Existió una copia duplicada y desincronizada de este proyecto en `C:\Users\BenjaminD\Desktop\App\nexo\nexo_build`, de una sesión anterior. **Este repo** (`Proyectos\nexo\nexo_build`, con git) es el real. Si algo se ve desincronizado, confirmar sobre qué copia se está trabajando.
