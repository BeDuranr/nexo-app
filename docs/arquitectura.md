# Arquitectura y datos — Nexo

## Stack

- **State management**: `provider` (`^6.1.2`)
- **Local storage**: `sqflite` (SQLite) vía `lib/db/db_helper.dart` — singleton `DBHelper` que centraliza todas las queries.
- **Charts**: ninguno — las barras de Métricas son `LinearProgressIndicator` (`fl_chart` se sacó, no se usaba).
- **Fonts**: Space Grotesk (display/headings) + Plus Jakarta Sans (body), **empaquetadas** en `assets/fonts/`. Se sigue usando la API de `google_fonts`, pero con `GoogleFonts.config.allowRuntimeFetching = false` en `main()`: el paquete toma los `.ttf` del bundle y nunca sale a la red. Era obligatorio cuando el release de Android no declaraba el permiso `INTERNET`: la descarga en runtime fallaba y la tipografía caía al tipo del sistema. Hoy el permiso está (lo necesita el respaldo), pero se mantiene así para que la app no salga a la red por las fuentes. Los archivos deben llamarse `{Familia}-{Peso}.ttf` (ej. `SpaceGrotesk-Bold.ttf`); si falta un peso, `google_fonts` lo registra en consola y usa el fallback.
- **Formatting**: `intl` (fechas, separador de miles)
- **Cuenta y respaldo**: `google_sign_in` + llamadas REST a Sheets y Drive con `http` — ver `docs/respaldo-google.md`.

Sin backend propio y sin PIN. SQLite en el dispositivo sigue siendo la **única fuente de verdad**: la app funciona completa sin conectar ninguna cuenta. Lo único que sale a la red es el respaldo opcional en Google Sheets, que el usuario activa desde Ajustes. Cada instalación tiene un solo usuario. Hay tres: el iPhone del desarrollador y los Android de su papá (con datos reales) y de su cuñado. Ver la tabla en `AGENTS.md`.

## Estructura (`lib/`)

- `main.dart` — entry point.
- `db/db_helper.dart` — todo el acceso a SQLite (CRUD de categorías y transacciones, migraciones de schema, tabla `settings`).
- `models/` — `category_model.dart`, `transaction_model.dart`, `debt_model.dart` (deuda en cuotas: fechas, montos y avance).
- `providers/` — `category_provider.dart`, `transaction_provider.dart`, `debt_provider.dart`, `backup_provider.dart` (`ChangeNotifier`, consumidos vía `provider`).
- `services/` — `google_auth_service.dart` y `sheets_backup_service.dart`: lo único del proyecto que habla con la red. `background_task.dart` le pide a iOS tiempo extra en segundo plano para el respaldo automático (la otra mitad está en `ios/Runner/AppDelegate.swift`).
- `screens/` — `home_screen.dart` (contenedor de tabs), `quick_entry_screen.dart`, `history_screen.dart`, `edit_transaction_screen.dart`, `metrics_screen.dart`, `debts_screen.dart` + `debt_form_screen.dart` (alta y edición), `settings_screen.dart`.
- `widgets/movement_form.dart` — **formulario de movimiento compartido** por registro y edición (monto, toggle gasto/ingreso, categorías, nota, fecha, barra "Listo"). Antes esas ~250 líneas estaban duplicadas en las dos pantallas. Guarda la categoría como **id** y la resuelve contra `CategoryProvider` en cada build: por eso nunca se guarda un nombre desactualizado, y si la categoría fue eliminada obliga a elegir una en vez de reasignar en silencio.
- `theme/app_theme.dart` — todo el sistema de diseño (ver `docs/diseno-ux.md`).
- `widgets/`, `utils/` — componentes compartidos y helpers.

## Modelo de datos

**`categories`**: `id`, `name`, `icon_key` (mapea a un ícono vectorial, no emoji), `is_default`. **Sin campo de tipo** — una categoría (ej. "Freelance") puede usarse tanto para ingreso como gasto; el tipo se elige aparte, por transacción, con un toggle de píldora. El usuario puede crear, editar y eliminar categorías, incluidas las por defecto.

**`transactions`**: `id`, `amount`, `type` (`income`/`expense`), `category_id` + `category_name`/`category_icon_key` denormalizados (se conservan aunque la categoría se edite o elimine después), `note`, `date` (editable — no forzada a "hoy", y la fecha seleccionada persiste entre registros consecutivos para poder cargar varios movimientos con la misma fecha seguidos).

**`debts`**: `id`, `name`, `total_amount`, `installments`, `first_date`. Una deuda en cuotas (ej. "Crédito auto", 12 cuotas desde el 30 de noviembre). **Las cuotas no viven en esta tabla**: al crearla se insertan de una vez como gastos comunes en `transactions`, con fecha futura y `debt_id` apuntando a la deuda. Así cada cuota aparece sola en su mes del Historial y entra al saldo cuando llega su día, sin depender de que la app esté abierta ese día. El avance (`DebtStatus` en `models/debt_model.dart`) se calcula desde esos movimientos, porque una cuota se puede editar o borrar en el Historial. Un día que no existe en el mes (el 30 en febrero) cae en el último día de ese mes. Eliminar una deuda borra sus cuotas futuras y deja las pasadas como gastos sueltos. Editarla nunca toca el monto ni la fecha de las cuotas pasadas: si solo cambia el nombre o la categoría, se actualizan en todas sus cuotas; si cambia el total, la cantidad o la fecha, las pendientes se rehacen con el calendario nuevo y se reparten en partes iguales lo que falta pagar (`DebtModel.rebuildPending`), así la suma sigue dando el total. "Pagar lo que queda" (pago anticipado) borra las cuotas que vencen **después** del día del pago y registra un solo gasto por lo pagado, que puede ser menor al saldo si hubo descuento de intereses. La deuda queda con el total y la cantidad de cuotas reales, así que termina y cuadra.

**`settings`**: `key`, `value`. Clave/valor para lo que no son datos del usuario — la cuenta de Google conectada, el id de la planilla de respaldo, la marca de la última escritura y la del último respaldo. Vive en SQLite y no en `shared_preferences` para no sumar una dependencia ni un segundo lugar donde buscar el estado de la app.

Schema versionado (actualmente **v6**) con migraciones `onUpgrade` en `db_helper.dart`:

| Paso | Qué hizo |
|---|---|
| v1→v2 | Migró íconos basados en emoji a `icon_key`. |
| v2→v3 | Reconstruyó ambas tablas para eliminar las columnas `emoji`/`category_emoji`, que habían quedado NOT NULL y hacían fallar todo INSERT nuevo. |
| v3→v4 | Índices sobre `transactions(date)` y `transactions(category_id)`, y re-sincronización de los nombres/íconos denormalizados que quedaron viejos. |
| v4→v5 | Tabla `settings` para la cuenta de Google y el estado del respaldo. |
| v5→v6 | Tabla `debts` y columna `transactions.debt_id` (null en todo lo que ya existía) para las deudas en cuotas. |

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

### Android: generar e instalar el APK

A diferencia de iOS, se compila local en Windows en ~70 segundos. No hace falta CI ni firma aparte.

```bash
flutter build apk --release --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

`--split-per-abi` separa por arquitectura: ~19 MB en vez de los ~52 MB del APK único. `arm64-v8a` sirve para cualquier teléfono de los últimos años. También se puede copiar el archivo al teléfono y abrirlo ahí, habilitando "instalar apps desconocidas".

> **La firma ata el APK a esta máquina.** Mientras no exista `key.properties`, el release se firma con `~/.android/debug.keystore`, que es propio de cada equipo y se regenera al año. Si la app instalada en el teléfono se compiló en otra máquina (o con un keystore ya vencido), Android rechaza la actualización con `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. La única salida sería desinstalar, **lo que borra la base de datos**. Ante ese error, no desinstalar sin haber rescatado los datos primero.

### Android: respaldo automático del sistema

`allowBackup="false"` más reglas de exclusión en `res/xml/backup_rules.xml` y `res/xml/data_extraction_rules.xml`. Antes el `nexo.db` completo se subía a Google Drive por default, sin que nadie lo decidiera. Eso sigue desactivado **a propósito**: el respaldo de Nexo ahora es explícito y lo activa el usuario desde Ajustes (ver `docs/respaldo-google.md`), en vez de pasar en silencio.

**Consecuencia:** si el usuario nunca conecta una cuenta de Google, perder el teléfono sigue siendo perder los movimientos.

### Android: firma de release

`android/app/build.gradle.kts` lee `android/key.properties` **si existe**:

- **Con** ese archivo (estado actual desde octubre de 2026): se firma con el keystore propio `nexo-release.jks`, alias `nexo`. SHA-1 `F2:FF:5C:20:CF:80:5D:23:CE:A3:06:EC:4C:99:E9:EB:4B:68:85:FB`: es el que está registrado en el cliente OAuth **Android** de Google Cloud, así que firmar con otra clave rompe el login de Google.
- **Sin** ese archivo: se firma con la clave de debug de la máquina, como antes.

**El keystore y su contraseña tienen que estar respaldados fuera del equipo.** Si se pierden, no se puede volver a instalar una actualización encima de una app ya instalada.

**El APK firmado con el keystore propio no se instala encima del que tiene el papá** (firmado con una clave de debug). Para pasarlo a esta firma hay que desinstalar, y eso borra la base de datos. Primero hay que rescatar sus datos.

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
