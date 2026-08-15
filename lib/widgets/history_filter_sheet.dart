import 'package:flutter/material.dart';

import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';

/// Filtros aplicables al historial: tipo de movimiento y categorías.
/// La búsqueda por texto vive aparte, directo en HistoryScreen.
class HistoryFilters {
  final MovementType? type;
  final Set<int> categoryIds;

  const HistoryFilters({this.type, this.categoryIds = const {}});

  const HistoryFilters.empty()
      : type = null,
        categoryIds = const {};

  bool get isEmpty => type == null && categoryIds.isEmpty;
  int get activeCount => (type != null ? 1 : 0) + (categoryIds.isNotEmpty ? 1 : 0);
}

/// Muestra la hoja de filtros y retorna la nueva selección, o null si se
/// cierra sin aplicar (ej. deslizando hacia abajo).
Future<HistoryFilters?> showHistoryFilterSheet(
  BuildContext context, {
  required HistoryFilters current,
  required List<CategoryModel> categories,
}) {
  MovementType? selectedType = current.type;
  final selectedCategories = {...current.categoryIds};

  return showModalBottomSheet<HistoryFilters>(
    context: context,
    backgroundColor: AppColors.urban900,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final hasActiveFilters = selectedType != null || selectedCategories.isNotEmpty;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filtrar movimientos', style: AppTheme.display(size: 16)),
                    if (hasActiveFilters)
                      TextButton(
                        onPressed: () => setSheetState(() {
                          selectedType = null;
                          selectedCategories.clear();
                        }),
                        child: const Text('Limpiar'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const _SectionLabel('Tipo'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _TypeChip(
                      label: 'Todos',
                      selected: selectedType == null,
                      onTap: () => setSheetState(() => selectedType = null),
                    ),
                    const SizedBox(width: 8),
                    _TypeChip(
                      label: 'Gastos',
                      color: AppColors.expense,
                      selected: selectedType == MovementType.expense,
                      onTap: () => setSheetState(() => selectedType = MovementType.expense),
                    ),
                    const SizedBox(width: 8),
                    _TypeChip(
                      label: 'Ingresos',
                      color: AppColors.income,
                      selected: selectedType == MovementType.income,
                      onTap: () => setSheetState(() => selectedType = MovementType.income),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Categoría'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories.map((cat) {
                    final id = cat.id;
                    if (id == null) return const SizedBox.shrink();
                    final isSelected = selectedCategories.contains(id);
                    return _CategoryFilterChip(
                      category: cat,
                      selected: isSelected,
                      onTap: () => setSheetState(() {
                        if (isSelected) {
                          selectedCategories.remove(id);
                        } else {
                          selectedCategories.add(id);
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      ctx,
                      HistoryFilters(type: selectedType, categoryIds: selectedCategories),
                    ),
                    child: const Text('Aplicar filtros'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: AppColors.urban300,
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppColors.urbanBlue,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.18) : AppColors.urban800,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? color : AppColors.urban700),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : AppColors.urban300,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  final CategoryModel category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryFilterChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorForKey(category.iconKey);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.18) : AppColors.urban800,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : AppColors.urban700),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconForKey(category.iconKey), color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                category.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? Colors.white : AppColors.urban300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
