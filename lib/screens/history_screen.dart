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

  // La búsqueda es mensual por defecto; el usuario puede ampliarla a todo
  // el historial cuando el mes no da resultados.
  bool _searchAllMonths = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query == _searchQuery) return;
    setState(() {
      _searchQuery = query;
      // Cada búsqueda nueva vuelve a empezar acotada al mes.
      _searchAllMonths = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta, 1);
      _searchAllMonths = false;
    });
  }

  bool _isSameMonth(DateTime date) =>
      date.year == _selectedMonth.year && date.month == _selectedMonth.month;

  bool _matchesFilters(TransactionModel t, {required bool ignoreMonth}) {
    if (!ignoreMonth && !_isSameMonth(t.date)) return false;
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
    if (result != null && mounted) {
      setState(() => _filters = result);
    }
  }

  Future<void> _deleteTransaction(TransactionModel tx) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<TransactionProvider>();
    final deleted = await provider.deleteTransaction(tx);

    if (!deleted) {
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('No se pudo eliminar el movimiento. Intenta de nuevo.',
              style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.urban700,
        content: const Text('Movimiento eliminado', style: TextStyle(color: Colors.white)),
        action: SnackBarAction(
          label: 'DESHACER',
          textColor: AppColors.urbanBlue,
          onPressed: provider.undoDelete,
        ),
      ),
    );
  }

  void _openEditor(TransactionModel tx) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => EditTransactionScreen(transaction: tx),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
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
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = context.watch<TransactionProvider>();
    final categories = context.watch<CategoryProvider>().categories;

    final isGlobalSearch = _searchAllMonths && _searchQuery.isNotEmpty;
    final transactions = txProvider.transactions
        .where((t) => _matchesFilters(t, ignoreMonth: isGlobalSearch))
        .toList();

    // Cuando el mes no da resultados, ofrecemos ampliar a todo el
    // historial en vez de dejar al usuario creyendo que no existe.
    final canWidenSearch = !isGlobalSearch &&
        _searchQuery.isNotEmpty &&
        transactions.isEmpty &&
        txProvider.transactions.any((t) => _matchesFilters(t, ignoreMonth: true));

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
                        : () => setState(() {
                              _selectedMonth = DateTime(now.year, now.month, 1);
                              _searchAllMonths = false;
                            }),
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
                      hintText: 'Buscar en $capitalizedMonthLabel...',
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
            if (isGlobalSearch) ...[
              const SizedBox(height: 10),
              _GlobalSearchBar(
                monthLabel: capitalizedMonthLabel,
                onBackToMonth: () => setState(() => _searchAllMonths = false),
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
              child: _buildList(
                txProvider: txProvider,
                transactions: transactions,
                categories: categories,
                isGlobalSearch: isGlobalSearch,
                canWidenSearch: canWidenSearch,
                hasActiveSearchOrFilters: hasActiveSearchOrFilters,
                monthLabel: capitalizedMonthLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList({
    required TransactionProvider txProvider,
    required List<TransactionModel> transactions,
    required List<CategoryModel> categories,
    required bool isGlobalSearch,
    required bool canWidenSearch,
    required bool hasActiveSearchOrFilters,
    required String monthLabel,
  }) {
    if (txProvider.loading && txProvider.transactions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Un fallo al abrir o migrar la base no puede pasar por "no hay
    // movimientos": así fue como el bug del botón de guardar estuvo
    // invisible hasta que se revisó el código.
    if (txProvider.lastError != null && txProvider.transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.expense, size: 28),
              const SizedBox(height: 8),
              const Text(
                'No se pudieron leer los movimientos guardados.',
                style: TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                txProvider.lastError!,
                style: const TextStyle(color: AppColors.urban500, fontSize: 9),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: txProvider.load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasActiveSearchOrFilters
                  ? 'Ningún movimiento coincide con la búsqueda o los filtros.'
                  : 'No hay movimientos en $monthLabel.',
              style: const TextStyle(color: AppColors.urban300, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            if (canWidenSearch) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _searchAllMonths = true),
                icon: const Icon(Icons.travel_explore, size: 16),
                label: const Text('Buscar en todos los meses'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
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
          // Buscando fuera del mes elegido, el año evita confundir un
          // movimiento con el de la misma fecha de otro año.
          showYear: isGlobalSearch,
          onEdit: () => _openEditor(tx),
          onDelete: () => _deleteTransaction(tx),
        );
      },
    );
  }
}

/// Aviso de que la búsqueda dejó de estar acotada al mes seleccionado.
class _GlobalSearchBar extends StatelessWidget {
  final String monthLabel;
  final VoidCallback onBackToMonth;

  const _GlobalSearchBar({required this.monthLabel, required this.onBackToMonth});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.urbanBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.urbanBlue),
      ),
      child: Row(
        children: [
          const Icon(Icons.travel_explore, size: 14, color: AppColors.urbanBlue),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Buscando en todo el historial',
                style: TextStyle(fontSize: 10, color: Colors.white)),
          ),
          TextButton(
            onPressed: onBackToMonth,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Volver a $monthLabel', style: const TextStyle(fontSize: 10)),
          ),
        ],
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
      color: isActive ? AppColors.urbanBlue.withValues(alpha: 0.18) : AppColors.urban900,
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
      final names =
          categories.where((c) => filters.categoryIds.contains(c.id)).map((c) => c.name);
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
