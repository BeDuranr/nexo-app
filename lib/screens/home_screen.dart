import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/category_provider.dart';
import '../providers/transaction_provider.dart';
import 'history_screen.dart';
import 'metrics_screen.dart';
import 'quick_entry_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final _screens = const [
    QuickEntryScreen(),
    HistoryScreen(),
    MetricsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Carga inicial de datos desde SQLite.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().load();
      context.read<TransactionProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
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
        ],
      ),
    );
  }
}
