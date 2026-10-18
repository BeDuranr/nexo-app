import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/backup_provider.dart';
import '../providers/category_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/google_auth_service.dart';
import '../theme/app_theme.dart';

/// Ajustes: hoy solo la cuenta de Google y el respaldo en Sheets.
///
/// Todo lo de esta pantalla es opcional. Sin conectar nada, Nexo
/// funciona exactamente como antes.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _connect() async {
    final backup = context.read<BackupProvider>();
    final result = await backup.connect();
    if (!mounted) return;

    switch (result.outcome) {
      case GoogleAuthOutcome.connected:
        _toast('Cuenta conectada');
        // Primer respaldo al toque: conectar sin que pase nada visible
        // deja la duda de si realmente quedó algo guardado.
        await backup.backupNow();
        if (!mounted) return;
        _toast(backup.errorMessage == null
            ? 'Respaldo creado en tu Drive'
            : 'Cuenta conectada, pero el respaldo falló');
      case GoogleAuthOutcome.canceled:
        break;
      case GoogleAuthOutcome.notConfigured:
      case GoogleAuthOutcome.failed:
        break;
    }
  }

  Future<void> _backupNow() async {
    final backup = context.read<BackupProvider>();
    final ok = await backup.backupNow();
    if (!mounted) return;
    if (ok) {
      HapticFeedback.lightImpact();
      _toast('Respaldo actualizado');
    }
  }

  Future<void> _restore() async {
    final confirmed = await _confirmRestore();
    if (!confirmed || !mounted) return;

    final backup = context.read<BackupProvider>();
    final ok = await backup.restoreFromBackup();
    if (!mounted) return;

    if (ok) {
      // La base cambió por debajo: sin esto las tres pantallas siguen
      // mostrando los movimientos viejos hasta reabrir la app.
      await context.read<CategoryProvider>().load();
      if (!mounted) return;
      await context.read<TransactionProvider>().load();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _toast('Datos restaurados desde el respaldo');
    }
  }

  Future<bool> _confirmRestore() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Restaurar el respaldo?',
            style: AppTheme.display(size: 17)),
        content: const Text(
          'Los movimientos y categorías que tenés en este teléfono se '
          'reemplazan por los de la planilla. Lo que esté acá y no en el '
          'respaldo se pierde.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.urban300)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar',
                style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _disconnect() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Desconectar la cuenta?',
            style: AppTheme.display(size: 17)),
        content: const Text(
          'Dejan de subirse respaldos nuevos. La planilla que ya está en '
          'tu Drive no se borra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.urban300)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar',
                style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    await context.read<BackupProvider>().disconnect();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final backup = context.watch<BackupProvider>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ajustes', style: AppTheme.display(size: 16)),
            const SizedBox(height: 16),
            _BackupCard(
              backup: backup,
              onConnect: _connect,
              onBackupNow: _backupNow,
              onRestore: _restore,
              onDisconnect: _disconnect,
            ),
            const SizedBox(height: 16),
            const Text(
              'Tus movimientos siguen viviendo en el teléfono. El respaldo '
              'es una copia en una planilla de tu Drive, que podés abrir y '
              'leer cuando quieras.',
              style: TextStyle(color: AppColors.urban500, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  const _BackupCard({
    required this.backup,
    required this.onConnect,
    required this.onBackupNow,
    required this.onRestore,
    required this.onDisconnect,
  });

  final BackupProvider backup;
  final VoidCallback onConnect;
  final VoidCallback onBackupNow;
  final VoidCallback onRestore;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.urban900,
        border: Border.all(color: AppColors.urban700),
        borderRadius: BorderRadius.circular(16),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  backup.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: backup.isConnected
                      ? AppColors.income
                      : AppColors.urban500,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Respaldo en Google',
                      style: AppTheme.display(size: 15)),
                ),
                if (backup.busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (backup.isMissingConfiguration)
              const _Notice(
                icon: Icons.build_circle_outlined,
                color: AppColors.urban300,
                message: 'Falta configurar el client ID de Google en la app. '
                    'Ver docs/respaldo-google.md.',
              )
            else if (!backup.isConnected)
              _Disconnected(onConnect: onConnect, busy: backup.busy)
            else
              _Connected(
                backup: backup,
                onBackupNow: onBackupNow,
                onRestore: onRestore,
                onDisconnect: onDisconnect,
              ),
            if (backup.errorMessage != null) ...[
              const SizedBox(height: 14),
              _Notice(
                icon: Icons.error_outline,
                color: AppColors.expense,
                message: backup.errorMessage!,
                detail: backup.errorDetail,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Disconnected extends StatelessWidget {
  const _Disconnected({required this.onConnect, required this.busy});

  final VoidCallback onConnect;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Conectá una cuenta de Google y Nexo guarda una copia de tus '
          'movimientos en una planilla de tu Drive. Solo ve esa planilla, '
          'nada más de tu Drive.',
          style: TextStyle(color: AppColors.urban300, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : onConnect,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.urbanBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.login, size: 18),
            label: const Text('Conectar con Google'),
          ),
        ),
      ],
    );
  }
}

class _Connected extends StatelessWidget {
  const _Connected({
    required this.backup,
    required this.onBackupNow,
    required this.onRestore,
    required this.onDisconnect,
  });

  final BackupProvider backup;
  final VoidCallback onBackupNow;
  final VoidCallback onRestore;
  final VoidCallback onDisconnect;

  String get _lastBackupLabel {
    final last = backup.lastBackup;
    if (last == null) return 'Todavía no se subió ningún respaldo';
    final formatted = DateFormat("d 'de' MMMM, HH:mm", 'es_CL').format(last);
    return 'Último respaldo: $formatted';
  }

  @override
  Widget build(BuildContext context) {
    final busy = backup.busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          backup.accountEmail ?? '',
          style: const TextStyle(color: AppColors.urban100, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          _lastBackupLabel,
          style: const TextStyle(color: AppColors.urban500, fontSize: 12),
        ),
        if (backup.hasPendingChanges) ...[
          const SizedBox(height: 12),
          const _Notice(
            icon: Icons.sync_problem,
            color: AppColors.urban300,
            message: 'Hay cambios sin respaldar.',
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : onBackupNow,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.urbanBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: const Text('Respaldar ahora'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : onRestore,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.urban300,
              side: const BorderSide(color: AppColors.urban600),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            label: const Text('Restaurar desde el respaldo'),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: busy ? null : onDisconnect,
            child: const Text(
              'Desconectar cuenta',
              style: TextStyle(color: AppColors.urban500, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.message,
    this.detail,
  });

  final IconData icon;
  final Color color;
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(color: color, fontSize: 12, height: 1.4),
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: const TextStyle(
                    color: AppColors.urban500,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
