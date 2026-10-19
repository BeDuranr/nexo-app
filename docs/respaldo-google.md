# Respaldo en Google Sheets

Nexo guarda una copia de los movimientos y categorías en una hoja de
cálculo del Drive del usuario. **Es opcional**: sin cuenta conectada la
app funciona igual que siempre, y SQLite sigue siendo la única fuente de
verdad. Google nunca manda — solo recibe copias, o las devuelve cuando se
pide restaurar.

## Cómo funciona

| Pieza | Archivo |
|---|---|
| Login con Google | `lib/services/google_auth_service.dart` |
| Llamadas a Sheets y Drive | `lib/services/sheets_backup_service.dart` |
| Estado (cuenta, último respaldo, pendientes) | `lib/providers/backup_provider.dart` |
| Pantalla | `lib/screens/settings_screen.dart` (4ª tab, "Ajustes") |
| Cuenta e id de planilla persistidos | tabla `settings` de SQLite (schema v5) |

La planilla se llama **"Nexo — Respaldo"** y tiene tres hojas:

- `movimientos`: `id, fecha, tipo, monto, categoria_id, categoria, icono, nota`
- `categorias`: `id, nombre, icono, por_defecto`
- `info`: cuándo se actualizó y cuántas filas tiene cada hoja

Cada respaldo **reescribe la planilla completa** (limpia y vuelve a
escribir). No es incremental a propósito: con este volumen de datos un
dump entero no puede quedar desincronizado, y es mucho más fácil de
razonar.

### Cuándo se respalda

- Al apretar "Respaldar ahora" en Ajustes.
- Al conectar la cuenta por primera vez.
- Al mandar la app a segundo plano, **si hay cambios sin subir**.
- Al abrir la app, **si hay cambios sin subir**.

"Hay cambios sin subir" se calcula comparando dos marcas de tiempo de la
tabla `settings`: `data_modificada` (que `DBHelper` actualiza en cada
escritura a categorías o movimientos) contra `ultimo_respaldo`. Por eso
sobrevive a que se cierre la app, y por eso las pantallas no tienen que
avisarle nada al respaldo.

### Restaurar

`BackupProvider.restoreFromBackup()` **reemplaza** todo lo local por lo
que haya en la planilla, dentro de una sola transacción SQL. Es la única
operación destructiva de la función, así que la pantalla pide
confirmación explícita antes y nunca se dispara sola.

Dos defensas que importan porque la planilla es editable a mano:

- Si los encabezados no son exactamente los esperados, se aborta sin
  tocar la base: restaurar con las columnas corridas escribiría basura.
- Si una fecha o un monto quedaron ilegibles, se aborta nombrando la
  fila.

Las categorías se reinsertan **con su id original**, porque
`transactions.category_id` apunta a ellas. Dejar que SQLite reasigne los
ids colgaría cada movimiento de la categoría equivocada.

## Setup en Google Cloud Console

Hay que hacerlo una sola vez. El `.ipa` no sirve hasta que esto esté.

1. Crear un proyecto (ej. "Nexo").
2. Habilitar **dos** APIs: **Google Sheets API** y **Google Drive API**
   (Drive se usa para encontrar y etiquetar el archivo).
3. Consent screen: tipo **External**, nombre de la app, email de soporte
   y contacto del desarrollador.
4. En "Data access", agregar exactamente estos scopes:
   - `openid`
   - `https://www.googleapis.com/auth/userinfo.email`
   - `https://www.googleapis.com/auth/drive.file`
5. Credenciales → Crear cliente OAuth → tipo **iOS** → bundle id
   `com.familia.nexo.nexo`. No hace falta Firebase ni
   `GoogleService-Info.plist`, y los clientes de iOS no tienen client
   secret.
6. **Publicar en Producción.**
7. Copiar los dos valores al `ios/Runner/Info.plist`:
   - `GIDClientID` → el client ID completo.
   - `CFBundleURLSchemes` → el "iOS URL scheme" que muestra la consola
     (el client ID dado vuelta, `com.googleusercontent.apps.…`).

**Estado actual:** hecho. El proyecto es `nexo-512100` y el cliente de
iOS ya está en el plist. Si alguna vez falta o queda mal, Ajustes muestra
"falta configurar el client ID" en vez de un error suelto.

El client ID **no es un secreto**: los clientes de OAuth para iOS no
tienen client secret, y el valor viaja dentro del binario de la app de
todos modos. Por eso está versionado sin problema.

### Por qué `drive.file` y no `spreadsheets`

`drive.file` está clasificado **no sensible**, y la API de Sheets lo
acepta para los archivos que la app creó. Eso trae tres cosas:

- **Sin proceso de verificación de Google** y **sin la pantalla "Google
  no ha verificado esta app"** — esa advertencia es solo para scopes
  sensibles o restringidos.
- La app solo ve la planilla que ella misma creó, nada más del Drive.
- Se puede publicar en Producción apretando un botón.

### Por qué hay que publicar en Producción

Un proyecto en estado **"Testing" emite refresh tokens que caducan a los
7 días** (y está limitado a 100 usuarios de prueba). En Testing habría
que volver a iniciar sesión cada semana, lo cual es inaceptable para el
usuario final. En Producción con scopes no sensibles no hay verificación.

El costo: la consola pide URL de homepage, política de privacidad y
términos para una app externa en producción. Alcanza una página estática.

## Android

El permiso `INTERNET` ya está declarado en el manifest (antes no estaba, y
eso rompía cualquier llamada de red **solo en release**). Pero el login
en Android necesita además:

- Un cliente OAuth **Web** pasado como `serverClientId` en
  `GoogleSignIn.initialize()` — hoy no se pasa, porque la app se usa por
  iOS.
- El **SHA-1 del certificado de firma** registrado en la consola. Sale
  del `~/.android/debug.keystore`, que es propio de cada máquina.

> **Antes de instalar un APK nuevo en el teléfono con datos reales:**
> correr `adb backup -f nexo-backup.ab com.familia.nexo.nexo` primero. La
> instalación puede fallar con `INSTALL_FAILED_UPDATE_INCOMPATIBLE` si el
> APK instalado se firmó en otra máquina, y la única salida sería
> desinstalar — lo que borra la base. Ver `docs/arquitectura.md`.

## Qué queda por verificar en el teléfono

El callback del login vuelve por el URL scheme, y esta app usa la
plantilla nueva de Flutter con `FlutterSceneDelegate`
(`ios/Runner/SceneDelegate.swift`). El SDK de Google usa
`ASWebAuthenticationSession`, que entrega el callback sin pasar por el
`AppDelegate`, así que debería funcionar — pero es lo primero que hay que
probar en el dispositivo.

También es el primer plugin del proyecto con una dependencia nativa
pesada (`GoogleSignIn ~> 9.0`, `ios.deployment_target 13.0`, que coincide
con el target del proyecto): el workflow de Actions va a correr
`pod install` por primera vez.
