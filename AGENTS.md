# AGENTS.md

Instrucciones para agentes de IA que trabajan en este repo (Claude Code, Codex, Cursor, etc.). Sigue la convención [agents.md](https://agents.md/). `CLAUDE.md` solo importa este archivo: editar acá, no allá.

La documentación detallada vive en `docs/` y se carga **bajo demanda**: lee solo lo que la tarea necesita. El mapa está en `docs/00-indice.md`.

## Qué es Nexo

Tracker de finanzas personales en **Flutter** (Dart `>=3.3.0 <4.0.0`, Flutter 3.44 stable), en español de Chile (montos en pesos, miles con punto). **Local primero**: no hay backend propio, ni login o PIN obligatorio. Todo vive en SQLite en el dispositivo, que es la **única fuente de verdad**. Lo único que sale a la red es el **respaldo opcional en Google Sheets** que el usuario activa desde Ajustes.

No es una app de tienda: se instala a mano en tres teléfonos de la familia, y cada instalación es independiente. Cada persona respalda en **su propio Drive**, sin planillas ni datos compartidos.

| Quién | Plataforma | Qué tener en cuenta |
|---|---|---|
| El desarrollador | iPhone | `.ipa` firmado con Apple ID gratuito: hay que re-firmarlo cada 7 días. |
| Su papá | Android | **Datos reales acumulados.** El APK instalado se firmó con una clave de debug de otra máquina, así que el APK actual no se instala encima. |
| Su cuñado | Android | Instalación nueva, con el keystore de release definitivo. |

La simplicidad y la baja fricción importan más que sumar features.

## Comandos

```bash
flutter pub get
flutter analyze                                  # tiene que quedar limpio
flutter test                                     # tests en test/, sin dispositivo
flutter build apk --release --split-per-abi      # APK en build/app/outputs/flutter-apk/
```

- **iOS no se compila en local** (el equipo es Windows). Se compila en GitHub Actions, con el workflow "iOS IPA sin firmar" (`.github/workflows/ios-ipa.yml`), que se lanza a mano o con un tag `v*`. Esa es la única forma de saber si un cambio en Swift compila.
- **Android usa** `app-arm64-v8a-release.apk`.
- **`keytool` y `apksigner`** no están en el PATH: vienen con Android Studio (`C:\Program Files\Android\Android Studio\jbr\bin`) y el SDK (`build-tools/*/lib/apksigner.jar`). Con la consola en español, `keytool -list -v` se cae por un bug de traducción: hay que agregar `-J-Duser.language=en`.

## Reglas que no se rompen

- **Sin backend propio.** La única red es Google Sheets/Drive para el respaldo, y **es opcional**: nada de la app puede quedar esperando una cuenta, un token o una respuesta de Google.
- **Cambios de schema SQLite solo con un paso nuevo de `onUpgrade`**, nunca tocando `_onCreate`. El schema va por v5. Cada paso nuevo se prueba en `test/db_migration_test.dart`. Hay datos reales sin respaldo: una migración mala no tiene vuelta atrás.
- **Categorías sin campo de tipo**: una misma categoría sirve para ingreso y gasto, y el tipo se elige aparte.
- **Solo la paleta oscura "urban"**: no proponer temas claros sin que el usuario lo pida (ya se descartó un rediseño Material 3 claro).
- **Primero que se sienta pulida**: fluidez y UX antes que features nuevas por iniciativa propia.

### Firma de Android

- `android/key.properties` y `nexo-release.jks` **nunca van al repo** (ya están en `.gitignore`).
- El SHA-1 del keystore está registrado en el cliente OAuth Android de Google Cloud: firmar con otra clave rompe el login de Google.
- Perder el keystore significa no poder actualizar nunca más encima de una instalación existente.
- Nada que obligue a **desinstalar** la app en el teléfono del papá antes de rescatar sus datos: desinstalar borra la base. Un intento de instalación fallido (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) no borra nada.

### Respaldo en Google

Detalle completo en `docs/respaldo-google.md`.

- **La etiqueta de Drive `nexoRespaldo=v1` no cambia nunca.** Con ella la app reencuentra la planilla después de reinstalarse. La versión del formato es otra cosa y se anota en la hoja `info`.
- **Restaurar tiene que seguir leyendo todos los formatos anteriores** (hoy el 1 y el 2). Un cambio de formato sin compatibilidad deja respaldos sin poder restaurarse.
- **La subida reemplaza las tres hojas en un solo `batchUpdate`.** No volver a borrar y reescribir hoja por hoja: si iOS suspende la app entre medio, la hoja de movimientos queda vacía.
- **Restaurar es la única operación destructiva** y no se dispara nunca sola.
- **Scopes:** solo `openid`, `email` y `drive.file`. Sumar uno sensible obliga a una verificación manual de Google.

### iOS nativo

Un archivo `.swift` nuevo hay que agregarlo a mano a `project.pbxproj`, y no hay Mac. Por eso el código nativo va en `ios/Runner/AppDelegate.swift`. Hoy ahí está el canal `nexo/background_task`.

## Flujo de trabajo

- **Commit y merge directo a `master`**, sin ramas ni PRs: hay un solo desarrollador. El push sí se confirma con él.
- **Antes de cada commit**: `flutter analyze` limpio y `flutter test` en verde.
- **Mensajes de commit en español**: el título explica el cambio para el usuario y el cuerpo el porqué.
- **Lo que no se pudo verificar** (Swift sin compilar, algo sin probar en un dispositivo o contra Google real) se dice explícitamente.
- **Comentarios y documentación en español**, explicando el porqué y no el qué, con la densidad de comentarios del código que ya existe.

## Mapa del repo

| Qué | Dónde |
|---|---|
| Stack, estructura de `lib/`, modelo de datos, builds y firma | `docs/arquitectura.md` |
| Login con Google, respaldo en Sheets, setup en Cloud Console | `docs/respaldo-google.md` |
| Sistema de diseño y convenciones de UX | `docs/diseno-ux.md` |
| Página pública (inicio, privacidad, términos), publicada en GitHub Pages | `pagina/` + `.github/workflows/pagina.yml` |
| Animaciones y micro-interacciones (Claude Code) | subagente `ux-flutter` en `.claude/agents/` |
| Legibilidad y buenas prácticas (Claude Code) | skill `clean-code` en `.claude/skills/` |

Proyecto de Google Cloud: `nexo-512100`, con clientes OAuth iOS, Android y Web. El ID del cliente Web está en `lib/services/google_auth_service.dart` y el de iOS en `ios/Runner/Info.plist`. No son secretos.

## Estado (octubre de 2026)

Esta sección envejece: verificar contra `git log` antes de confiar en ella.

- **Hecho:**
  - Respaldo en Sheets en formato 2: en español, con fechas reales y la subida en una sola operación.
  - Login probado en iPhone.
  - Keystore de release y login de Android implementados.
  - APK del cuñado compilado.
- **Pendiente, en orden:**
  1. Publicar la app de Google en Producción: quitar el logo, cargar las URLs de `pagina/` y agregar `beduranr.github.io` a los dominios autorizados.
  2. Probar el login en Android, en el teléfono del cuñado.
  3. Rescatar los datos del teléfono del papá: `adb backup` mientras siga instalada la versión vieja, y después un script que pase `nexo.db` a la planilla en formato 2.
  4. Recién entonces, reinstalarle con el keystore nuevo.
- **Menor:** subir la versión, que sigue en `1.4.0+4`.
