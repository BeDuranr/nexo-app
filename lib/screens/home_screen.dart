import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/backup_provider.dart';
import '../providers/category_provider.dart';
import '../providers/transaction_provider.dart';
import 'history_screen.dart';
import 'metrics_screen.dart';
import 'quick_entry_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const int _settingsTab = 3;

  int _index = 0;

  final _screens = const [
    QuickEntryScreen(),
    HistoryScreen(),
    MetricsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Carga inicial de datos desde SQLite.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().load();
      context.read<TransactionProvider>().load();
      // Recupera la sesión de Google sin mostrar nada y sube lo que
      // haya quedado pendiente. Si falla, no se avisa acá: la app no
      // depende de esto para funcionar.
      context.read<BackupProvider>().init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al salir de la app es el momento menos intrusivo para subir: no
    // interrumpe el registro de un movimiento ni compite con la UI.
    if (state == AppLifecycleState.paused) {
      context.read<BackupProvider>().backupIfPending();
    }
  }

  void _onTabTapped(int i) {
    // Sin esto el teclado del campo de monto sigue abierto sobre el
    // historial: IgnorePointer bloquea el puntero, pero no el foco.
    FocusScope.of(context).unfocus();
    // Las cuatro pantallas viven a la vez en el Stack, así que el
    // initState de Ajustes corre una sola vez al arrancar la app: sin
    // esto, "hay cambios sin respaldar" quedaba congelado en lo que era
    // cierto en ese momento.
    if (i == _settingsTab) {
      context.read<BackupProvider>().refresh();
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: List.generate(_screens.length, (i) {
          final isActive = _index == i;
          return Positioned.fill(
            child: AnimatedOpacity(
              key: ValueKey(i),
              opacity: isActive ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              // Las tres pantallas viven a la vez en el Stack; sin esto
              // los lectores de pantalla leen también las ocultas.
              child: ExcludeSemantics(
                excluding: !isActive,
                child: IgnorePointer(
                  ignoring: !isActive,
                  child: _screens[i],
                ),
              ),
            ),
          );
        }),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle),
            label: 'Registrar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Historial',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Métricas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
