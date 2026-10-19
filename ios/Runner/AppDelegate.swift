import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NexoBackgroundTask") {
      BackgroundTaskChannel.register(with: registrar.messenger())
    }
  }
}

/// Tiempo extra en segundo plano para que el respaldo automático alcance a
/// terminar antes de que iOS suspenda la app. Lo usa
/// `lib/services/background_task.dart`.
///
/// Vive en este archivo y no en uno propio porque un .swift nuevo hay que
/// agregarlo a mano al proyecto de Xcode, y acá no hay Mac para hacerlo.
final class BackgroundTaskChannel {
  private static var taskId: UIBackgroundTaskIdentifier = .invalid

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "nexo/background_task", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "begin":
        begin()
        result(nil)
      case "end":
        end()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func begin() {
    end()
    // Si se acaba el tiempo antes de que Dart avise que terminó, hay que
    // cerrar la tarea igual: si no, iOS mata la app en vez de suspenderla.
    taskId = UIApplication.shared.beginBackgroundTask(withName: "nexo-respaldo") {
      end()
    }
  }

  private static func end() {
    guard taskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(taskId)
    taskId = .invalid
  }
}
