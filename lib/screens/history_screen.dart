import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../providers/category_provider.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/history_filter_sheet.dart';
import '../widgets/transaction_tile.dart';
import 'edit_transaction_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Mes actualmente mostrado (siempre normalizado al día 1).
  late DateTime _selectedMonth;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  HistoryFilters _filters = const HistoryFilters.empty();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
    });
  }

  bool _isSameMonth(DateTime date) =>
      date.year == _selectedMonth.year && date.month == _selectedMonth.month;

  bool _matchesFilters(TransactionModel t) {
    if (!_isSameMonth(t.date)) return false;
    if (_filters.type != null && t.type != _filters.type) return false;
    if (_filters.categoryIds.isNotEmpty && !_filters.categoryIds.contains(t.categoryId)) {
      return false;
    }
    if (_searchQuery.isNotEmpty) {
      final haystack = '${t.note} ${t.categoryName}'.toLowerCase();
      if (!haystack.contains(_searchQuery)) return false;
    }
    return true;
  }

  Future<void> _openFilterSheet() async {
    final categories = context.read<CategoryProvider>().categories;
    final result = await showHistoryFilterSheet(
      context,
      current: _filters,
      categories: categories,
    );
    if (result != null) {
      setState(() => _filters = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = context.watch<TransactionProvider>();
    final categories = context.watch<CategoryProvider>().categories;
    final transactions = txProvider.transactions.where(_matchesFilters).toList();
    final hasActiveSearchOrFilters = _searchQuery.isNotEmpty || !_filters.isEmpty;

    final monthLabel = DateFormat('MMMM yyyy', 'es_CL').format(_selectedMonth);
    final capitalizedMonthLabel = monthLabel[0].toUpperCase() + monthLabel.substring(1);

    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Historial de movimientos', style: AppTheme.display(size: 16)),
            const SizedBox(height: 10),

            // Selector de mes.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.urban900,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.urban700),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left, color: AppColors.urban300),
                    visualDensity: VisualDensity.compact,
                  ),
                  GestureDetector(
                    onTap: isCurrentMonth
                        ? null
                        : () => setState(() => _selectedMonth = DateTime(now.year, now.month, 1)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          capitalizedMonthLabel,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (!isCurrentMonth)
                          const Text('Volver a hoy',
                              style: TextStyle(fontSize: 9, color: AppColors.urbanBlue)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right, color: AppColors.urban300),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Búsqueda por texto + acceso a filtros por tipo/categoría.
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Buscar por nota o categoría...',
                      prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.urban300),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 16, color: AppColors.urban300),
                              onPressed: () => _searchController.clear(),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _FilterButton(
                  activeCount: _filters.activeCount,
                  onTap: _openFilterSheet,
                ),
              ],
            ),
            if (!_filters.isEmpty) ...[
              const SizedBox(height: 10),
              _ActiveFiltersBar(
                filters: _filters,
                categories: categories,
                onClear: () => setState(() => _filters = const HistoryFilters.empty()),
              ),
            ],
            const SizedBox(height: 10),

            const Row(
              children: [
                Icon(Icons.swipe_left_alt, size: 14, color: AppColors.urbanBlue),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Desliza un movimiento a la izquierda para editarlo o borrarlo.',
                    style: TextStyle(fontSize: 10, color: AppColors.urban300),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: transactions.isEmpty
                  ? Center(
                      child: Text(
                        hasActiveSearchOrFilters
                            ? 'Ningún movimiento coincide con la búsqueda o los filtros.'
                            : 'No hay movimientos en $capitalizedMonthLabel.',
                        style: const TextStyle(color: AppColors.urban300, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        CategoryModel? category;
                        for (final c in categories) {
                          if (c.id == tx.categoryId) {
                            category = c;
                            break;
                          }
                        }
                        return TransactionTile(
                          key: ValueKey(tx.id),
                          tx: tx,
                          category: category,
                          onEdit: () {
                            Navigator.of(context).push(
                              PageRouteBuilder(
                                transitionDuration: const Duration(milliseconds: 280),
                                reverseTransitionDuration: const Duration(milliseconds: 220),
                                pageBuilder: (_, animation, __) =>
                                    EditTransactionScreen(transaction: tx),
                                transitionsBuilder: (_, animation, __, child) {
                                  final curved =
                                      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                                  return FadeTransition(
                                    opacity: curved,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.06),
                                        end: Offset.zero,
                                      ).animate(curved),
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          onDelete: () async {
                            await context.read<TransactionProvider>().deleteTransaction(tx);
                            HapticFeedback.lightImpact();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.urban700,
                                content: const Text('Movimiento eliminado',
                                    style: TextStyle(color: Colors.white)),
                                action: SnackBarAction(
                                  label: 'DESHACER',
                                  textColor: AppColors.urbanBlue,
                                  onPressed: () =>
                                      context.read<TransactionProvider>().undoDelete(),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón que abre la hoja de filtros; muestra un badge con la cantidad de
/// filtros activos (tipo y/o categoría) para que se note de un vistazo.
class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _FilterButton({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isActive = activeCount > 0;
    return Material(
      color: isActive ? AppColors.urbanBlue.withOpacity(0.18) : AppColors.urban900,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? AppColors.urbanBlue : AppColors.urban700),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.tune, size: 18, color: isActive ? Colors.white : AppColors.urban300),
              if (isActive)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.urbanBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resumen de los filtros activos, con un acceso rápido para limpiarlos.
class _ActiveFiltersBar extends StatelessWidget {
  final HistoryFilters filters;
  final List<CategoryModel> categories;
  final VoidCallback onClear;

  const _ActiveFiltersBar({
    required this.filters,
    required this.categories,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final labels = <String>[];
    if (filters.type != null) {
      labels.add(filters.type == MovementType.expense ? 'Gastos' : 'Ingresos');
    }
    if (filters.categoryIds.isNotEmpty) {
      final names = categories
          .where((c) => filters.categoryIds.contains(c.id))
          .map((c) => c.name);
      labels.addAll(names);
    }

    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: labels
                .map((label) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.urban800,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.urban700),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 10, color: AppColors.urban300),
                      ),
                    ))
                .toList(),
          ),
        ),
        TextButton(
          onPressed: onClear,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Limpiar', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }
}
