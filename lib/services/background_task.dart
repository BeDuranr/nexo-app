import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Le pide a iOS que no suspenda la app mientras corre [work].
///
/// Al pasar a segundo plano iOS deja correr la app apenas unos segundos,
/// y el respaldo automático corre justo en ese momento. Con esto iOS da
/// más margen (unos 30 segundos) para que alcance a terminar. La otra
/// mitad vive en `ios/Runner/AppDelegate.swift`.
///
/// En Android no hace falta: el proceso sigue vivo un buen rato después
/// de salir de la app. Si el canal falla, [work] corre igual: perder el
/// margen extra solo deja el respaldo pendiente para la próxima vez.
Future<T> runAsBackgroundTask<T>(Future<T> Function() work) async {
  if (!Platform.isIOS) return work();

  const channel = MethodChannel('nexo/background_task');
  try {
    await channel.invokeMethod<void>('begin');
  } catch (_) {
    // Ver el comentario de arriba: sin margen extra, el trabajo sigue.
  }
  try {
    return await work();
  } finally {
    try {
      await channel.invokeMethod<void>('end');
    } catch (_) {
      // iOS igual cierra la tarea solo cuando se le acaba el tiempo.
    }
  }
}
